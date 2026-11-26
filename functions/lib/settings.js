"use strict";

/**
 * Moderation settings live in one Firestore document, settings/moderation,
 * edited by hand in the Firebase console. Every field is optional:
 *
 *   requireApproval  bool      emergency switch read by firestore.rules
 *   adminUIDs        [string]  accounts that get a push for every report
 *   notifyEmails     [string]  addresses that get an email for every report
 *                              (needs the "Trigger Email" extension)
 *   autoHideReports  number    reports from different people that take a
 *                              post out of the feed; 0 turns this off.
 *                              "Something feels off" reports do not count here
 *   autoHideSoftReports number different people reporting a post for any
 *                              reason at all, "Something feels off" included,
 *                              that take it out of the feed; 0 turns this off
 *   imageModeration  string    "enforce" (default) | "log" | "off"
 *   limits           map       see rateLimit.js for the keys
 *
 * What every phone has to know lives in a second document, config/app. The
 * app can read it (firestore.rules), nobody can change it from a phone, and
 * nothing private belongs in it:
 *
 *   founderUID          string    the founder's account; absent or "" means
 *                                 there is no conversation with the founder
 *   founderNickname     string    the name people see on that conversation
 *   founderWelcome      [string]  what she says first, one message per entry
 *   founderThreadHours  number    how long that conversation lasts; absent
 *                                 or 0 = it never runs out (read by
 *                                 firestore.rules and the app, not by the
 *                                 functions)
 *   chatPhotos          bool      false switches photos in conversations
 *                                 off for everyone; absent = on
 */

/**
 * @typedef {Object} Settings
 * @property {string[]} adminUIDs
 * @property {string[]} notifyEmails
 * @property {number} autoHideReports
 * @property {number} autoHideSoftReports
 * @property {"enforce"|"log"|"off"} imageModeration
 * @property {number} keepEndedDays days a conversation is kept after it is over for good; 0 = never deleted
 * @property {Record<string, number>} limits
 */

const strings = (v) => (Array.isArray(v) ? v.filter((x) => typeof x === "string" && x) : []);

/**
 * @param {Record<string, any> | undefined | null} data
 * @return {Settings}
 */
function normalizeSettings(data) {
  const d = data || {};
  const hide = d.autoHideReports;
  const soft = d.autoHideSoftReports;
  const mode = d.imageModeration;
  const keep = d.keepEndedDays;
  return {
    adminUIDs: strings(d.adminUIDs),
    notifyEmails: strings(d.notifyEmails),
    autoHideReports: Number.isInteger(hide) && hide >= 0 ? hide : 3,
    autoHideSoftReports: Number.isInteger(soft) && soft >= 0 ? soft : 10,
    imageModeration: mode === "log" || mode === "off" ? mode : "enforce",
    keepEndedDays: Number.isInteger(keep) && keep >= 0 ? keep : 7,
    limits: d.limits && typeof d.limits === "object" && !Array.isArray(d.limits) ? d.limits : {},
  };
}

/**
 * @typedef {Object} AppConfig
 * @property {string} founderUID "" when there is no founder conversation
 * @property {string} founderNickname
 * @property {string[]} founderWelcome
 * @property {boolean} chatPhotos
 */

/** At most this many welcome messages, each at most this long. */
const WELCOME_MAX_LINES = 10;
const WELCOME_MAX_CHARS = 2000;

/**
 * @param {Record<string, any> | undefined | null} data
 * @return {AppConfig}
 */
function normalizeAppConfig(data) {
  const d = data || {};
  return {
    founderUID: typeof d.founderUID === "string" ? d.founderUID : "",
    founderNickname: typeof d.founderNickname === "string" ? d.founderNickname.slice(0, 60) : "",
    founderWelcome: strings(d.founderWelcome).slice(0, WELCOME_MAX_LINES).map((s) => s.slice(0, WELCOME_MAX_CHARS)),
    chatPhotos: d.chatPhotos !== false,
  };
}

module.exports = {normalizeSettings, normalizeAppConfig};
