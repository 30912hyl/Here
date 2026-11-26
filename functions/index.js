"use strict";

/**
 * Cloud Functions for Here. Each one reacts to something being written in
 * Firestore; what it then does is decided in lib/handlers.js.
 *
 *   onPostCreated     rate limit, photo ownership, text check, photo check
 *   onMessageCreated  rate limit, text check, photo check, then the push notification
 *   onThreadCreated   limit on new conversations per hour; the founder's welcome
 *   onTimeUpSweep     every 5 minutes: tell both people their 48 hours are up
 *   onRetentionSweep  every hour: delete conversations (messages, photos) some days after they are over
 *   onReportCreated   tell moderators; hide a post after several reports
 *   onBanCreated      a banned number's posts and conversations come down
 *   onUserDocDeleted  safety net for "Delete Account"
 *
 * Needs the Blaze plan. Photo checks also need the Cloud Vision API enabled
 * on the project; until it is, photos are simply left alone. The sweep needs
 * the Cloud Scheduler API (the first deploy turns it on).
 */

const {initializeApp} = require("firebase-admin/app");
const {setGlobalOptions} = require("firebase-functions/v2");
const {onDocumentCreated, onDocumentDeleted, onDocumentUpdated} = require("firebase-functions/v2/firestore");
const {onSchedule} = require("firebase-functions/v2/scheduler");
const logger = require("firebase-functions/logger");
const handlers = require("./lib/handlers");
const {createStore} = require("./lib/store");

initializeApp();
// A ceiling on how far any one function can scale, so a flood of writes
// cannot run up a bill.
setGlobalOptions({maxInstances: 10});

/** @type {import("./lib/store").Store | undefined} */
let store;
/** @return {import("./lib/store").Store} */
function getStore() {
  if (!store) {
    store = createStore(() => {
      const vision = require("@google-cloud/vision");
      return new vision.ImageAnnotatorClient();
    });
  }
  return store;
}

exports.onPostCreated = onDocumentCreated("posts/{postId}", (event) =>
  handlers.onPostCreated(getStore(), event.params.postId, event.data && event.data.data()));

exports.onMessageCreated = onDocumentCreated("threads/{threadId}/messages/{messageId}", (event) =>
  handlers.onMessageCreated(getStore(), event.params.threadId, event.params.messageId, event.data && event.data.data()));

exports.onThreadCreated = onDocumentCreated("threads/{threadId}", (event) =>
  handlers.onThreadCreated(getStore(), event.params.threadId, event.data && event.data.data()));

// How often: the notice arrives at most this long after the time ran out.
// handlers.TIME_UP_LOOKBACK_MS has to stay several times longer than this.
// One run at a time and no retries: a run that failed is simply made up for
// by the next one, and nobody can be told twice.
exports.onTimeUpSweep = onSchedule({schedule: "every 5 minutes", maxInstances: 1, retryCount: 0}, async () => {
  const result = await handlers.onTimeUpSweep(getStore());
  if (!result.endsWith(":0")) logger.warn(`time-up sweep had failures: ${result}`);
  else if (!result.startsWith("swept:0:")) logger.info(`time-up sweep: ${result}`);
});

// A conversation that is over for good is deleted, with its messages and
// photos, settings.keepEndedDays days later (7 by default). One run at a time
// and no retries, like the sweep above: the next run makes up for a failed one.
exports.onRetentionSweep = onSchedule({schedule: "every 60 minutes", maxInstances: 1, retryCount: 0}, async () => {
  const result = await handlers.onRetentionSweep(getStore());
  if (!result.endsWith(":0") && result !== "retention:off") logger.warn(`retention sweep had failures: ${result}`);
  else if (result !== "retention:0:0:0" && result !== "retention:off") logger.info(`retention sweep: ${result}`);
});

exports.onReportCreated = onDocumentCreated("reports/{reportId}", (event) =>
  handlers.onReportCreated(getStore(), event.params.reportId, event.data && event.data.data()));

// A moderator closing a report in the console (writing `outcome` on it).
exports.onReportUpdated = onDocumentUpdated("reports/{reportId}", (event) =>
  handlers.onReportUpdated(getStore(), event.params.reportId, event.data && event.data.after.data()));

exports.onBanCreated = onDocumentCreated("bannedPhones/{phone}", (event) =>
  handlers.onBanCreated(getStore(), event.params.phone));

exports.onUserDocDeleted = onDocumentDeleted("users/{userId}", (event) =>
  handlers.onUserDocDeleted(getStore(), event.params.userId));
