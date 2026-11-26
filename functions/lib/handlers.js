"use strict";

/**
 * What the server does when something is written. Every function here takes
 * a `store` (see store.js for the real one, test/fakeStore.js for the one
 * the tests use) so the decisions can be tested without Firebase.
 *
 * Removing a post never deletes it: its expiry is moved to "now", so it
 * drops out of everyone's feed at once (the app only shows unexpired posts)
 * and stays available to moderators and in its author's own archive.
 */

const {check} = require("./textFilter");
const {ownPhoto, chatPhotoPath, safeSearchVerdict} = require("./images");

const HOUR_MS = 60 * 60 * 1000;

/**
 * Milliseconds from a Firestore timestamp, a Date or a number.
 * @param {any} v
 * @param {number} fallback
 * @return {number}
 */
function toMs(v, fallback) {
  if (typeof v === "number" && Number.isFinite(v)) return v;
  if (v && typeof v.toMillis === "function") return v.toMillis();
  if (v instanceof Date) return v.getTime();
  return fallback;
}

/**
 * @typedef {import("./store").Store} Store
 */

/**
 * The start of a message for a notification: at most `max` characters, and
 * small enough for a push however it is written (a push that is too big is
 * not delivered at all). Never cuts an emoji or an accented letter in half.
 * @param {unknown} text
 * @param {number} [max]
 * @return {string}
 */
function preview(text, max = 180) {
  if (typeof text !== "string" || text === "") return "";
  const MAX_BYTES = 1024;
  let out = "";
  let count = 0;
  let cut = false;
  for (const {segment} of new Intl.Segmenter(undefined, {granularity: "grapheme"}).segment(text)) {
    if (count >= max || Buffer.byteLength(out + segment, "utf8") > MAX_BYTES) {
      cut = true;
      break;
    }
    out += segment;
    count += 1;
  }
  return cut ? `${out.trimEnd()}…` : out;
}

/**
 * A new post: rate limit, photo ownership, text, photo content.
 * @param {Store} store
 * @param {string} postId
 * @param {Record<string, any> | undefined} post
 * @return {Promise<string>} what happened, for logs and tests
 */
async function onPostCreated(store, postId, post) {
  if (!post || typeof post.authorUID !== "string" || !post.authorUID) {
    return "skipped";
  }
  const uid = post.authorUID;
  const settings = await store.settings();

  const over = await store.countAction(uid, "post", settings.limits);
  if (over) {
    await store.removePost(postId, "rate");
    await store.log({kind: "post", action: "removed", reason: `rate:${over}`, uid, postId});
    return "removed:rate";
  }

  // Every photo must be in the author's own folder of our bucket. (The
  // security rules already refuse anything else; this also pins the bucket.)
  const mode = settings.imageModeration;
  const urls = Array.isArray(post.imageURLs) ? post.imageURLs : [];
  const parsed = urls.map((u) => ownPhoto(u, store.bucketNames(), uid));
  const photos = /** @type {Array<{bucket: string, path: string}>} */ (parsed.filter((p) => p !== null));
  if (photos.length < urls.length && mode !== "off") {
    if (mode === "enforce") {
      await store.removePost(postId, "foreign-image");
      await store.log({kind: "post", action: "removed", reason: "foreign-image", uid, postId});
      return "removed:foreign-image";
    }
    await store.log({kind: "post", action: "flagged", reason: "foreign-image", uid, postId});
  }

  // "Just for me" posts are shown to nobody else, so their content is not
  // moderated.
  if (post.isPrivate === true) return "ok:private";

  const tags = Array.isArray(post.tags) ? post.tags.join(" ") : "";
  const verdict = check("post", post.title, post.bodyText, tags);
  if (verdict === "slur") {
    await store.removePost(postId, "text");
    await store.log({kind: "post", action: "removed", reason: "text:slur", uid, postId});
    return "removed:text";
  }
  if (verdict === "contact") {
    // The app refuses these before posting, so this came from a modified
    // app. Logged, not removed: a false match here should not cost a post.
    await store.log({kind: "post", action: "flagged", reason: "text:contact", uid, postId});
  }

  if (mode === "off" || photos.length === 0) return "ok";

  const flagged = [];
  const review = [];
  const unreadable = [];
  for (const photo of photos) {
    const annotation = await store.safeSearch(photo);
    const v = safeSearchVerdict(annotation);
    if (v === "remove") flagged.push(photo);
    if (v === "review") review.push(photo);
    if (v === "unreadable") unreadable.push(photo);
  }
  const pathsOf = (list) => list.map((photo) => photo.path);

  if (flagged.length > 0) {
    if (mode === "log") {
      await store.log({kind: "post", action: "flagged", reason: "image", uid, postId, paths: pathsOf(flagged)});
      await store.notifyAdmins("Photo would be removed", "A photo was flagged (log-only mode).", {postId});
      return "flagged:image";
    }
    await store.removePost(postId, "image");
    await store.deleteFiles(flagged);
    await store.log({kind: "post", action: "removed", reason: "image", uid, postId, paths: pathsOf(flagged)});
    await store.notifyAdmins("Post removed", "A photo was removed automatically.", {postId});
    return "removed:image";
  }
  if (review.length > 0) {
    await store.log({kind: "post", action: "flagged", reason: "image:review", uid, postId, paths: pathsOf(review)});
    await store.notifyAdmins("Photo needs a look", "A photo was flagged for review.", {postId});
    return "review:image";
  }
  if (unreadable.length > 0) {
    // Never passed silently, never removed for a technical reason.
    await store.log({kind: "post", action: "flagged", reason: "image:unreadable", uid, postId, paths: pathsOf(unreadable)});
    await store.notifyAdmins("Photo could not be checked", "A photo is in a format the check cannot read.", {postId});
    return "review:unreadable";
  }
  return "ok";
}

/**
 * What the notification says when a message is a photo with no words.
 *
 * WORDING NOT APPROVED YET. A placeholder in the same voice as the fallback
 * for a message without text ("sent you a message"). The owner decides all
 * user-facing copy; change it here and in the test, nowhere else.
 */
const PHOTO_PUSH_BODY = "sent a photo";

/**
 * The photo of a new message: is it really hers, are photos switched on, is
 * she within her daily number, and what does SafeSearch say. A photo that
 * passes is marked (imageOK) so the other person's phone shows it; until
 * then that phone shows nothing, so a photo that is removed here is never
 * seen. Nothing here trusts the phone: the security rules already refuse
 * most of this, and a modified app is exactly who gets this far.
 *
 * A photo that does not pass the check — an explicit one, or a file Vision
 * cannot read at all — is deleted, and its message stays, marked
 * (imageRemoved): both phones then show the same line in its place, so the
 * sender knows it did not go through and the other person knows something
 * was sent. (For a post an unreadable file stays up for a moderator to
 * look at; a conversation is private, nobody else would ever see it, and
 * "a picture the check cannot read" must not be a way to send one
 * unchecked. The app only ever uploads ordinary JPEGs.)
 *
 * A message that should not exist at all is still deleted with its file:
 * a path she could not have uploaded to, photos being switched off, or
 * more photos than her daily number.
 * @param {Store} store
 * @param {import("./settings").Settings} settings
 * @param {string} threadId
 * @param {string} messageId
 * @param {string} sender
 * @param {{bucket: string, path: string} | null} photo null when the path is not one she could have uploaded
 * @return {Promise<string | null>} why nothing more should happen with this message
 *   ("removed:…" it is gone, "rejected:…" it stays without its photo), or null if all is well
 */
async function checkChatPhoto(store, settings, threadId, messageId, sender, photo) {
  const remove = async (reason) => {
    await store.deleteMessage(threadId, messageId);
    if (photo) await store.deleteFiles([photo]);
    await store.log({kind: "message", action: "removed", reason, uid: sender, threadId, ...(photo ? {paths: [photo.path]} : {})});
    return `removed:${reason}`;
  };
  // The photo did not pass: the file goes, the message stays and says so.
  const reject = async (reason) => {
    await store.deleteFiles([photo]);
    await store.markPhotoRejected(threadId, messageId);
    await store.log({kind: "message", action: "photo-rejected", reason, uid: sender, threadId, paths: [photo.path]});
    return `rejected:${reason}`;
  };

  if (!photo) return remove("foreign-image");
  if (!(await store.appConfig()).chatPhotos) return remove("photos-off");
  const over = await store.countAction(sender, "photo", settings.limits);
  if (over) {
    await remove(`rate:${over}`);
    return "removed:rate";
  }

  const mode = settings.imageModeration;
  if (mode !== "off") {
    const v = safeSearchVerdict(await store.safeSearch(photo));
    if (v === "remove" || v === "unreadable") {
      const reason = v === "remove" ? "image" : "image:unreadable";
      if (mode !== "log") {
        const out = await reject(reason);
        await store.notifyAdmins("Chat photo removed", v === "remove" ?
          "A photo sent in a conversation was removed automatically." :
          "A file sent as a photo in a conversation could not be read and was removed.", {threadId});
        return out;
      }
      await store.log({kind: "message", action: "flagged", reason, uid: sender, threadId, paths: [photo.path]});
      await store.notifyAdmins("Chat photo would be removed", "A photo sent in a conversation was flagged (log-only mode).", {threadId});
    } else if (v === "review") {
      await store.log({kind: "message", action: "flagged", reason: "image:review", uid: sender, threadId, paths: [photo.path]});
      await store.notifyAdmins("Chat photo needs a look", "A photo sent in a conversation was flagged for review.", {threadId});
    }
  }
  await store.markPhotoChecked(threadId, messageId);
  return null;
}

/**
 * A new private message: rate limit, text check, photo check, then the push
 * notification.
 * @param {Store} store
 * @param {string} threadId
 * @param {string} messageId
 * @param {Record<string, any> | undefined} message
 * @return {Promise<string>}
 */
async function onMessageCreated(store, threadId, messageId, message) {
  if (!message || message.senderUID === "system") return "skipped";
  // The founder's welcome is written by onThreadCreated below, not typed by
  // anyone: it counts against nobody and notifies nobody.
  if (message.auto === true) return "skipped";
  const sender = message.senderUID;
  if (typeof sender !== "string" || !sender) return "skipped";
  const settings = await store.settings();

  const hasPhoto = message.imagePath !== undefined && message.imagePath !== null;
  const photoPath = hasPhoto ? chatPhotoPath(message.imagePath, threadId, sender) : null;
  const photo = photoPath ? store.photoAt(photoPath) : null;

  const over = await store.countAction(sender, "message", settings.limits);
  if (over) {
    await store.deleteMessage(threadId, messageId);
    if (photo) await store.deleteFiles([photo]);
    await store.log({kind: "message", action: "removed", reason: `rate:${over}`, uid: sender, threadId});
    return "removed:rate";
  }

  const verdict = check("message", message.text);
  if (verdict === "slur" || verdict === "harassment" || verdict === "sexual") {
    await store.deleteMessage(threadId, messageId);
    if (photo) await store.deleteFiles([photo]);
    await store.log({kind: "message", action: "removed", reason: `text:${verdict}`, uid: sender, threadId});
    return `removed:${verdict}`;
  }

  if (hasPhoto) {
    const removed = await checkChatPhoto(store, settings, threadId, messageId, sender, photo);
    if (removed) return removed;
  }

  const thread = await store.getThread(threadId);
  if (!thread || thread.isManuallyFrozen === true) return "ok:no-push";
  const recipient = (thread.participants || []).find((p) => p !== sender);
  if (!recipient) return "ok:no-push";

  // A deleted account (no user doc) or someone who blocked the sender gets
  // nothing: no badge bump (which would recreate a deleted user's doc) and
  // no push carrying the blocked person's text.
  const user = await store.getUser(recipient);
  if (!user) return "ok:no-push";
  if ((user.blocked || []).includes(sender)) return "ok:blocked";

  // Badge counts unread CONVERSATIONS (like iMessage), so only bump it when
  // this thread flips from read to unread, i.e. the new message is the only
  // unread one from the other participant.
  //
  // Known race: two near-simultaneous messages can each see themselves as
  // the first unread one and double-bump the badge. Accepted: the app
  // rewrites the exact count whenever the recipient opens it.
  const lastRead = (thread.lastRead || {})[recipient];
  const unreadFromSender = await store.unreadFrom(threadId, sender, lastRead);
  let unreadTotal = user.unreadTotal || 0;
  if (unreadFromSender <= 1) {
    unreadTotal += 1;
    await store.setUnreadTotal(recipient, unreadTotal);
  }

  if (!user.fcmToken) return "ok:no-token";
  // In the conversation with the founder she goes by the name in config/app,
  // not by the random name the conversation has on her own side.
  let title = thread.nickname || "New message";
  if (thread.kind === "founder") {
    const config = await store.appConfig();
    if (sender === config.founderUID && config.founderNickname) title = config.founderNickname;
  }
  const result = await store.sendPush(user.fcmToken, {
    title,
    body: preview(message.text) || (hasPhoto ? PHOTO_PUSH_BODY : "sent you a message"),
    badge: unreadTotal,
    data: {threadId},
  });
  // Token expired or app uninstalled: drop it so we stop trying.
  if (result === "gone") await store.clearToken(recipient);
  return `push:${result}`;
}

/**
 * A new conversation: limit how many one person can open per hour. In the
 * conversation with the founder (kind "founder", opened by the other person
 * with her first reply; see firestore.rules) the founder's welcome is then
 * written in as its first messages.
 * @param {Store} store
 * @param {string} threadId
 * @param {Record<string, any> | undefined} thread
 * @return {Promise<string>}
 */
async function onThreadCreated(store, threadId, thread) {
  const participants = thread && Array.isArray(thread.participants) ? thread.participants : [];
  if (participants.length !== 2) return "skipped";
  // Here's own conversation with a person (kind "system") is written by the
  // server (store.addSystemNotice); no phone can create one (firestore.rules).
  // It is not a conversation anybody opened, so it counts against nobody.
  if (thread.kind === "system") return "skipped";
  // The person who opened it is the one who did not write the post.
  let opener = participants[0];
  /** @type {import("./settings").AppConfig | null} */
  let founder = null;
  if (thread.kind === "founder") {
    const config = await store.appConfig();
    const other = participants.find((p) => p !== config.founderUID);
    // The rules only let the real one through; anything else that calls
    // itself this is ended on the spot.
    if (!config.founderUID || !participants.includes(config.founderUID) || !other || threadId !== `founder_${other}`) {
      await store.freezeThread(threadId);
      await store.log({kind: "thread", action: "ended", reason: "not-founder", uid: opener, threadId});
      return "ended:not-founder";
    }
    opener = other;
    founder = config;
  } else if (typeof thread.postId === "string" && thread.postId) {
    const post = await store.getPost(thread.postId);
    if (post && participants.includes(post.authorUID)) {
      opener = participants.find((p) => p !== post.authorUID) || opener;
    }
  }
  const settings = await store.settings();
  const over = await store.countAction(opener, "thread", settings.limits);
  if (over) {
    await store.freezeThread(threadId);
    await store.log({kind: "thread", action: "ended", reason: `rate:${over}`, uid: opener, threadId});
    return "ended:rate";
  }
  if (founder && founder.founderWelcome.length > 0) {
    await store.addWelcome(threadId, founder.founderUID, founder.founderWelcome, toMs(thread.createdAt, Date.now()));
    return "ok:welcome";
  }
  return "ok";
}

const DAY_MS = 24 * HOUR_MS;

/** Here's own conversation with one person has the id system_<her uid> (store.addSystemNotice). */
const notSystem = (id) => !String(id).startsWith("system_");

/** The 24 hours both people have to answer "another 48 hours?" (ChatThread.decisionWindow in the app). */
const DECISION_WINDOW_MS = 24 * HOUR_MS;

/**
 * Whether a conversation can no longer be continued: it was ended, or its
 * time ran out and so did the chance to extend it. (While the question
 * "another 48 hours?" is still open it is not over.) The conversation with
 * the founder has no end date, so only ending it makes it over.
 * @param {Record<string, any>} thread with expiresAtMs
 * @param {number} nowMs
 * @return {boolean}
 */
function overForGood(thread, nowMs) {
  if (thread.isManuallyFrozen === true) return true;
  const end = thread.expiresAtMs;
  if (typeof end !== "number" || !Number.isFinite(end)) return false;
  return nowMs >= (thread.hasExtendedOnce === true ? end : end + DECISION_WINDOW_MS);
}

/**
 * When a conversation became over for good, as far as its dates tell: the
 * end of its second 48 hours, or 24 hours after the first if nobody
 * extended it. A conversation that was ended by hand carries no such date.
 * @param {Record<string, any>} thread with expiresAtMs
 * @return {number | undefined}
 */
function overSinceMs(thread) {
  const end = thread.expiresAtMs;
  if (typeof end !== "number" || !Number.isFinite(end)) return undefined;
  return thread.hasExtendedOnce === true ? end : end + DECISION_WINDOW_MS;
}

/**
 * Runs every hour. A conversation that is over for good is kept for
 * settings.keepEndedDays more days (7 unless set otherwise; 0 keeps
 * everything) and then deleted whole: its messages, its photos, and the
 * conversation itself, for both people. Photos live exactly as long as
 * their conversation — never shorter.
 *
 * Two steps, so the app can tell both people the date beforehand: the
 * first run that sees a conversation over writes the date on it
 * (deleteAfter); a run after that date deletes it. What a report put aside
 * (the reported person's last messages and photos) is kept: it is stored
 * with the report, not with the conversation.
 * @param {Store} store
 * @param {number} [nowMs]
 * @return {Promise<string>} "retention:<given a date>:<deleted>:<failed>", or "retention:off"
 */
async function onRetentionSweep(store, nowMs = Date.now()) {
  const days = (await store.settings()).keepEndedDays;
  if (!(days > 0)) return "retention:off";
  const keepMs = days * DAY_MS;
  let scheduled = 0;
  let deleted = 0;
  let failed = 0;

  for (const {id, thread} of await store.threadsOverWithoutDate(nowMs)) {
    // One conversation going wrong must not hold up the others.
    try {
      if (!overForGood(thread, nowMs)) continue;
      // Ended by hand: there is no record of when, so the days count from
      // the first run that sees it (at most an hour late).
      const since = thread.isManuallyFrozen === true ? nowMs : overSinceMs(thread);
      await store.scheduleThreadDelete(id, (since ?? nowMs) + keepMs);
      scheduled += 1;
    } catch (_) {
      failed += 1;
    }
  }

  for (const id of await store.threadsDueForDelete(nowMs)) {
    try {
      const files = await store.deleteChatPhotos(id);
      await store.deleteThread(id);
      await store.log({kind: "thread", action: "deleted", threadId: id, files});
      deleted += 1;
    } catch (_) {
      failed += 1;
    }
  }
  return `retention:${scheduled}:${deleted}:${failed}`;
}

/**
 * How far back one sweep looks for conversations that ran out. Longer than
 * the gap between two sweeps (see index.js), so a few missed runs lose
 * nothing; short enough that nobody hears "time's up" hours late, and that
 * every conversation is only read a handful of times.
 */
const TIME_UP_LOOKBACK_MS = 30 * 60 * 1000;

/**
 * The notification both people get when their 48 hours run out.
 *
 * WORDING NOT APPROVED YET. Both parts are words the app already shows in
 * this situation (the top bar says "time's up", the question under the
 * messages is the body below), put together as a placeholder. The owner
 * decides all user-facing copy; change it here and in the test, nowhere else.
 */
const TIME_UP_PUSH = {
  title: "Time's up",
  body: "Continue this conversation for another 48 hours?",
};

/**
 * Runs every few minutes. When a conversation's 48 hours run out, the app
 * asks both people the same question — talk for another 48 hours? — and
 * gives them 24 hours to answer (ChatThread.decisionWindow in the app,
 * isTheOneExtension() in firestore.rules). Nothing tells them the moment has
 * come unless they happen to open the app, so this does.
 *
 * Each conversation is told about once, ever: it is marked before anything
 * is sent, so two overlapping runs cannot both send. Nobody is told about a
 * conversation that was ended, that already used its one extension (when
 * that runs out there is nothing to decide), or where one of the two has
 * blocked the other. Someone who has already answered is left alone. The
 * app's badge is not touched: it counts unread conversations.
 * @param {Store} store
 * @param {number} [nowMs]
 * @return {Promise<string>} "swept:<conversations looked at>:<pushes sent>:<conversations that failed>"
 */
async function onTimeUpSweep(store, nowMs = Date.now()) {
  const due = await store.threadsEndedBetween(nowMs - TIME_UP_LOOKBACK_MS, nowMs);
  let sent = 0;
  let failed = 0;
  for (const {id, thread} of due) {
    // One conversation going wrong must not cost the others their notice.
    try {
      sent += await tellTimeIsUp(store, id, thread);
    } catch (_) {
      failed += 1;
    }
  }
  return `swept:${due.length}:${sent}:${failed}`;
}

/**
 * One conversation of the sweep above.
 * @param {Store} store
 * @param {string} id
 * @param {Record<string, any>} thread
 * @return {Promise<number>} how many of the two were sent a notification
 */
async function tellTimeIsUp(store, id, thread) {
  if (thread.isManuallyFrozen === true || thread.hasExtendedOnce === true || thread.timeUpPushAt) return 0;
  const participants = Array.isArray(thread.participants) ? thread.participants : [];
  if (participants.length !== 2 || participants[0] === participants[1]) return 0;
  if (!(await store.claimTimeUp(id))) return 0;

  // No user document only means she has no notifications set up: she can
  // still answer in the app, so the other one is still told. (A deleted
  // account's conversations were ended when it was deleted.)
  const [a, b] = participants;
  const users = {[a]: (await store.getUser(a)) || {}, [b]: (await store.getUser(b)) || {}};
  // If either blocked the other the conversation cannot continue. The one
  // who blocked no longer sees it; the other one is not drawn back into it.
  if ((users[a].blocked || []).includes(b) || (users[b].blocked || []).includes(a)) return 0;

  const choices = thread.continueChoices || {};
  let sent = 0;
  for (const uid of participants) {
    if (choices[uid] === "yes" || choices[uid] === "no") continue;
    const token = users[uid].fcmToken;
    if (!token) continue;
    const result = await store.sendPush(token, {
      // The conversation's name, as on message notifications, so she knows
      // which one this is about.
      title: thread.nickname || TIME_UP_PUSH.title,
      body: thread.nickname ? `${TIME_UP_PUSH.title}. ${TIME_UP_PUSH.body}` : TIME_UP_PUSH.body,
      data: {threadId: id, kind: "timeUp"},
    });
    if (result === "ok") sent += 1;
    // Token expired or app uninstalled: drop it so we stop trying.
    if (result === "gone") await store.clearToken(uid);
  }
  return sent;
}

/**
 * The report reason for "I can't say which rule, it just feels wrong". The
 * same words as the last entry of ReportSheet.reasons in the app
 * (Here/Views/ReportSheet.swift): change both together.
 */
const SOFT_REASON = "Something feels off";

/**
 * A new report: tell the moderators, and take a post out of the feed once
 * enough different people have reported it.
 * @param {Store} store
 * @param {string} reportId
 * @param {Record<string, any> | undefined} report
 * @param {number} [nowMs]
 * @return {Promise<string>}
 */
/** A title short enough to quote inside a sentence. */
function shortTitle(v, max = 60) {
  const t = typeof v === "string" ? v.replace(/\s+/g, " ").trim() : "";
  const chars = Array.from(t);
  return chars.length > max ? `${chars.slice(0, max - 1).join("").trimEnd()}…` : t;
}

/** What a report was about, the way Here says it to the person who sent it. */
function aboutReport(report, thread) {
  if (report.type === "chat") {
    const name = thread && typeof thread.nickname === "string" ? shortTitle(thread.nickname, 40) : "";
    return name ? `your conversation with ${name}` : "a conversation";
  }
  const title = shortTitle(report.title);
  return title ? `the post “${title}”` : "a post";
}

/**
 * Here's first line to someone who reported something: it arrived. (Wording
 * approved by the founder, 2026-11-25. Here speaks in ordinary sentence case.)
 * @param {Record<string, any>} report
 * @param {Record<string, any> | null} thread the reported conversation, if it still exists
 * @return {string}
 */
function receivedNotice(report, thread) {
  return `We got your report about ${aboutReport(report, thread)}. Thank you for telling us. We look at every report within 24 hours.`;
}

/**
 * Here's second line, once a moderator has looked: what was done. A report is
 * closed by writing `outcome` on it in the console (functions/README.md).
 *
 * Only wording the founder has approved is ever sent. Today that is one
 * sentence: a reported post was removed. Every other outcome returns null and
 * nothing is sent, until its sentence is approved and added here:
 *   - a reported conversation, action taken  (draft, not approved)
 *   - the account was banned                 (draft, not approved)
 *   - no rule was broken                     (draft, not approved)
 * @param {Record<string, any>} report
 * @param {string} outcome lower case
 * @return {string | null}
 */
function outcomeNotice(report, outcome) {
  if (report.type !== "chat" && outcome === "removed") {
    const title = shortTitle(report.title);
    const what = title ? `your report about “${title}”` : "your report";
    return `We looked into ${what} and removed the post. Thank you for looking out for everyone here.`;
  }
  return null;
}

/**
 * Writes one line from Here into the reporter's own "system" conversation.
 * Never throws and never changes what happens to the report itself: telling
 * her is a courtesy, the report counts either way. Someone whose account is
 * gone (no user doc) is told nothing, so no conversation is created for an
 * account that no longer exists.
 * @param {Store} store
 * @param {Record<string, any>} report
 * @param {string} noticeId fixed per report and kind, so a retry writes the same line again instead of a second one
 * @param {(thread: Record<string, any> | null) => string | null} wording
 * @param {number} nowMs
 * @return {Promise<boolean>} whether a line was written
 */
async function tellReporter(store, report, noticeId, wording, nowMs) {
  try {
    const uid = report.reporterUID;
    if (!(await store.getUser(uid))) return false;
    let thread = null;
    if (report.type === "chat" && typeof report.threadId === "string" && report.threadId) {
      thread = await store.getThread(report.threadId);
    }
    const text = wording(thread);
    if (!text) return false;
    return (await store.addSystemNotice(uid, noticeId, text, nowMs)) === true;
  } catch (_) {
    return false;
  }
}

async function onReportCreated(store, reportId, report, nowMs = Date.now()) {
  if (!report || typeof report.reporterUID !== "string") return "skipped";
  const settings = await store.settings();

  const over = await store.countAction(report.reporterUID, "report", settings.limits);
  if (over) {
    await store.markReport(reportId, {ignored: "rate"});
    return "ignored:rate";
  }

  const what = report.type === "chat" ? "conversation" : "post";
  await store.notifyAdmins("New report", `A ${what} was reported: ${String(report.reason || "").slice(0, 80)}`, {reportId});
  await tellReporter(store, report, `report-${reportId}-received`, (thread) => receivedNotice(report, thread), nowMs);

  // A reported conversation: the photos the other person sent are put aside
  // for the moderators, so they outlast the conversation (which is deleted
  // a few days after it ends, see onRetentionSweep). Only for a report from
  // someone who is in it.
  if (report.type === "chat" && typeof report.threadId === "string" && report.threadId) {
    const thread = await store.getThread(report.threadId);
    const participants = thread && Array.isArray(thread.participants) ? thread.participants : [];
    const other = participants.find((p) => p !== report.reporterUID);
    if (thread && thread.hasPhotos === true && participants.length === 2 && participants.includes(report.reporterUID) && other) {
      const kept = await store.keepEvidence(report.threadId, other, reportId);
      if (kept > 0) await store.markReport(reportId, {photosKept: kept});
    }
  }

  // Two ways for a post to leave the feed before anyone has looked at it:
  //   - `threshold` different people report it for breaking a rule;
  //   - `softThreshold` different people report it for any reason at all.
  // "Something feels off" (SOFT_REASON) is the reason for when nothing else
  // fits: a real signal, but not a claim that a rule was broken, so three
  // people who merely dislike a post cannot make it disappear. Ten can.
  const threshold = settings.autoHideReports;
  const softThreshold = settings.autoHideSoftReports;
  if (report.type !== "post" || !report.postId || (!(threshold > 0) && !(softThreshold > 0))) return "notified";

  const reports = await store.reportsOf(report.postId);
  const everyone = [...new Set(reports.map((r) => r.reporterUID))];
  // Several reasons can be picked at once: a report counts as naming a
  // broken rule as soon as one of them is something other than the feeling.
  const forARule = [...new Set(reports.filter((r) => r.reasons.some((x) => x !== SOFT_REASON)).map((r) => r.reporterUID))];
  const enough = (list) => (threshold > 0 && list.filter((u) => forARule.includes(u)).length >= threshold) ||
    (softThreshold > 0 && list.length >= softThreshold);
  if (!enough(everyone)) return "notified";

  const post = await store.getPost(report.postId);
  if (!post || post.removed || !(post.expiresAtMs > nowMs)) return "notified";
  // The author reporting her own post does not count toward hiding it, and
  // neither do accounts without a verified phone number: those cost nothing
  // to create, so one person could otherwise hide any post she liked.
  const others = everyone.filter((r) => r !== post.authorUID);
  if (!enough(others)) return "notified";
  const counted = await store.verifiedAmong(others);
  if (!enough(counted)) return "notified";

  const countedForARule = counted.filter((u) => forARule.includes(u)).length;
  const byRule = threshold > 0 && countedForARule >= threshold;
  const n = byRule ? countedForARule : counted.length;
  await store.removePost(report.postId, "reports");
  await store.log({kind: "post", action: "removed", reason: `${byRule ? "reports" : "reports-any"}:${n}`, uid: post.authorUID, postId: report.postId});
  await store.notifyAdmins("Post hidden", `Hidden after ${n} reports. Please review.`, {postId: report.postId});
  return "removed:reports";
}

/**
 * A report was changed. The only change that matters here: a moderator wrote
 * `outcome` on it in the console, which closes it. The person who reported is
 * then told what was done, once per outcome (see outcomeNotice for which
 * outcomes have approved wording; the others are closed silently).
 *
 * `outcomeNotified` is written back on the report. That write triggers this
 * function again, and it is also what stops it there.
 * @param {Store} store
 * @param {string} reportId
 * @param {Record<string, any> | undefined} report the report as it is now
 * @param {number} [nowMs]
 * @return {Promise<string>}
 */
async function onReportUpdated(store, reportId, report, nowMs = Date.now()) {
  if (!report || typeof report.reporterUID !== "string") return "skipped";
  const outcome = typeof report.outcome === "string" ? report.outcome.trim().toLowerCase() : "";
  if (!outcome || report.outcomeNotified === outcome) return "skipped";
  // A report that was set aside when it came in (too many in an hour) was
  // never answered with "we got it", so it gets no second line either.
  if (report.ignored) return "skipped";
  if (!outcomeNotice(report, outcome)) return "skipped:no-wording";
  const told = await tellReporter(store, report, `report-${reportId}-outcome`, () => outcomeNotice(report, outcome), nowMs);
  if (!told) return "skipped:not-told";
  await store.markReport(reportId, {outcomeNotified: outcome});
  await store.log({kind: "report", action: "answered", reason: outcome, uid: report.reporterUID, reportId});
  return `told:${outcome}`;
}

/**
 * A phone number was banned (added to /bannedPhones in the console): take
 * that person's posts out of the feed and end her conversations.
 * @param {Store} store
 * @param {string} phone
 * @return {Promise<string>}
 */
async function onBanCreated(store, phone) {
  const tail = String(phone).slice(-4);
  const uid = await store.uidForPhone(phone);
  if (!uid) {
    await store.log({kind: "ban", action: "noted", reason: "no-account", phoneTail: tail});
    return "no-account";
  }
  const postIds = await store.livePostIdsBy(uid);
  for (const id of postIds) await store.removePost(id, "ban");
  const threadIds = (await store.openThreadIdsOf(uid)).filter(notSystem);
  for (const id of threadIds) await store.freezeThread(id);
  await store.clearToken(uid);
  await store.clearPresence(uid);
  await store.log({kind: "ban", action: "applied", uid, phoneTail: tail, posts: postIds.length, threads: threadIds.length});
  return `applied:${postIds.length}:${threadIds.length}`;
}

/**
 * The app deletes users/{uid} as the last step of "Delete Account", after
 * deleting that person's posts and photos itself. This is the safety net:
 * whatever the phone did not manage to delete is deleted here, and any
 * conversation still open is ended.
 * @param {Store} store
 * @param {string} uid
 * @return {Promise<string>}
 */
async function onUserDocDeleted(store, uid) {
  if (!uid) return "skipped";
  const removed = await store.deleteUserContent(uid);
  // What Here told her about her reports goes with the account.
  await store.deleteSystemThread(uid);
  const threadIds = (await store.openThreadIdsOf(uid)).filter(notSystem);
  for (const id of threadIds) {
    await store.freezeThread(id);
    // Her own photos in that conversation go now. The other person's stay
    // with the conversation until it is deleted (onRetentionSweep), as do
    // hers in conversations that had already ended.
    try {
      removed.files += await store.deleteChatPhotos(id, uid);
    } catch (_) {
      // left for the sweep
    }
  }
  await store.clearPresence(uid);
  if (removed.posts > 0 || removed.files > 0 || threadIds.length > 0) {
    await store.log({kind: "account", action: "cleaned", posts: removed.posts, files: removed.files, threads: threadIds.length});
  }
  return `cleaned:${removed.posts}:${removed.files}:${threadIds.length}`;
}

module.exports = {
  preview,
  TIME_UP_LOOKBACK_MS,
  TIME_UP_PUSH,
  PHOTO_PUSH_BODY,
  SOFT_REASON,
  DECISION_WINDOW_MS,
  DAY_MS,
  overForGood,
  overSinceMs,
  onPostCreated,
  onMessageCreated,
  onThreadCreated,
  onTimeUpSweep,
  onRetentionSweep,
  onReportCreated,
  onReportUpdated,
  receivedNotice,
  outcomeNotice,
  onBanCreated,
  onUserDocDeleted,
};
