"use strict";

/**
 * The only file that talks to Firebase. handlers.js decides; this file reads
 * and writes. Kept thin on purpose: nothing here is covered by the unit
 * tests (they use test/fakeStore.js), so nothing here should decide anything.
 *
 * Failures are logged and swallowed where the safe outcome is "do nothing":
 * a broken rate limiter or a Vision outage must not take posts down.
 */

const {getFirestore, FieldValue, Timestamp} = require("firebase-admin/firestore");
const {getMessaging} = require("firebase-admin/messaging");
const {getStorage} = require("firebase-admin/storage");
const {getAuth} = require("firebase-admin/auth");
const logger = require("firebase-functions/logger");
const {checksFor, bump} = require("./rateLimit");
const {normalizeSettings, normalizeAppConfig} = require("./settings");
const {reasonsOf} = require("./reasons");

const SETTINGS_TTL_MS = 60 * 1000;

/**
 * @typedef {import("./settings").Settings} Settings
 * @typedef {import("./settings").AppConfig} AppConfig
 * @typedef {{title: string, body: string, badge?: number, data?: Record<string, string>}} Push
 * @typedef {ReturnType<typeof createStore>} Store
 */

const PROJECT = "here-a6817";

/** Who "says" Here's own lines (never a real account: uids are 28 characters). */
const SYSTEM_SENDER = "here";
/** "Never runs out", written as one fixed date: 2100-01-01 UTC (firestore.rules, ChatThread.never in the app). */
const NEVER_MS = Date.UTC(2100, 0, 1);

/** @return {{projectId?: unknown, storageBucket?: unknown}} */
function firebaseConfig() {
  try {
    const cfg = JSON.parse(process.env.FIREBASE_CONFIG || "{}");
    return cfg && typeof cfg === "object" ? cfg : {};
  } catch (_) {
    return {};
  }
}

/**
 * The bucket photos are uploaded to. Cloud Functions provides it in
 * FIREBASE_CONFIG; the fallback is the project's default bucket.
 * @return {string}
 */
function defaultBucketName() {
  const cfg = firebaseConfig();
  if (typeof cfg.storageBucket === "string" && cfg.storageBucket) return cfg.storageBucket;
  return `${PROJECT}.firebasestorage.app`;
}

/**
 * Every name a photo URL may carry for our own bucket: the configured one
 * plus both spellings Firebase has used for a project's default bucket. If
 * the configured name and the name in the app's URLs ever disagreed, a
 * single-name check would take down every photo post.
 * @return {string[]}
 */
function ownBucketNames() {
  const cfg = firebaseConfig();
  const project = (typeof cfg.projectId === "string" && cfg.projectId) ||
    process.env.GCLOUD_PROJECT || PROJECT;
  return [...new Set([defaultBucketName(), `${project}.firebasestorage.app`, `${project}.appspot.com`])];
}

/**
 * @param {() => {safeSearchDetection: (uri: string) => Promise<any[]>}} visionFactory
 *   creates the Cloud Vision client on first use
 */
function createStore(visionFactory) {
  const db = getFirestore();
  const bucketName = defaultBucketName();
  const buckets = ownBucketNames();
  const bucket = () => getStorage().bucket(bucketName);

  /** @type {Settings | null} */
  let cached = null;
  let cachedAt = 0;
  /** @type {AppConfig | null} */
  let cachedConfig = null;
  let cachedConfigAt = 0;
  /** @type {{safeSearchDetection: (uri: string) => Promise<any[]>} | null} */
  let vision = null;

  /** @return {Promise<Settings>} */
  async function settings() {
    const now = Date.now();
    if (cached && now - cachedAt < SETTINGS_TTL_MS) return cached;
    try {
      const snap = await db.doc("settings/moderation").get();
      cached = normalizeSettings(snap.exists ? snap.data() : undefined);
      cachedAt = now;
      return cached;
    } catch (err) {
      // Keep using what was read last. The defaults are only a stand-in for
      // this one call and are never remembered as if they had been read: a
      // hiccup must not switch "log only" back to "enforce" for a minute.
      logger.error("could not read settings/moderation", err);
      return cached || normalizeSettings(undefined);
    }
  }

  /**
   * config/app: who the founder is, what she says first, whether photos in
   * conversations are on. Read the same way as the settings above.
   * @return {Promise<AppConfig>}
   */
  async function appConfig() {
    const now = Date.now();
    if (cachedConfig && now - cachedConfigAt < SETTINGS_TTL_MS) return cachedConfig;
    try {
      const snap = await db.doc("config/app").get();
      cachedConfig = normalizeAppConfig(snap.exists ? snap.data() : undefined);
      cachedConfigAt = now;
      return cachedConfig;
    } catch (err) {
      logger.error("could not read config/app", err);
      return cachedConfig || normalizeAppConfig(undefined);
    }
  }

  /**
   * Every file under one conversation's photo folder (or one person's part
   * of it). An id with a slash in it would reach outside that folder, so it
   * matches nothing.
   * @param {string} threadId
   * @param {string} [uid]
   */
  async function chatFiles(threadId, uid) {
    if (!threadId || threadId.includes("/") || (uid !== undefined && (!uid || uid.includes("/")))) return [];
    const prefix = uid === undefined ? `chats/${threadId}/` : `chats/${threadId}/${uid}/`;
    const [list] = await bucket().getFiles({prefix});
    return list;
  }

  /**
   * @param {string} uid
   * @return {Promise<Record<string, any> | null>}
   */
  async function getUser(uid) {
    if (!uid) return null;
    const snap = await db.doc(`users/${uid}`).get();
    return snap.exists ? snap.data() || {} : null;
  }

  /**
   * @param {string} token
   * @param {Push} push
   * @return {Promise<"ok"|"gone"|"error">}
   */
  async function sendPush(token, push) {
    /** @type {Record<string, string>} */
    const data = {};
    for (const [k, v] of Object.entries(push.data || {})) data[k] = String(v);
    /** @type {Record<string, any>} */
    const aps = {sound: "default"};
    if (typeof push.badge === "number") aps.badge = push.badge;
    try {
      await getMessaging().send({
        token,
        notification: {title: push.title, body: push.body},
        apns: {payload: {aps}},
        data,
      });
      return "ok";
    } catch (err) {
      const code = err && typeof err === "object" && "code" in err ? err.code : "";
      if (code === "messaging/registration-token-not-registered") return "gone";
      logger.error("push send failed", err);
      return "error";
    }
  }

  return {
    settings,
    appConfig,
    getUser,
    sendPush,

    /**
     * Where a conversation photo is stored, given its path in our bucket.
     * @param {string} path
     * @return {{bucket: string, path: string}}
     */
    photoAt(path) {
      return {bucket: bucketName, path};
    },

    /**
     * A conversation photo passed its check: the message is marked so the
     * other person's phone shows it, and the conversation is marked as one
     * that has photos to delete when it is over.
     * @param {string} threadId
     * @param {string} messageId
     */
    async markPhotoChecked(threadId, messageId) {
      try {
        const batch = db.batch();
        batch.update(db.doc(`threads/${threadId}/messages/${messageId}`), {imageOK: true});
        batch.update(db.doc(`threads/${threadId}`), {hasPhotos: true});
        await batch.commit();
      } catch (err) {
        logger.error(`could not mark the photo of ${threadId}/${messageId} as checked`, err);
      }
    },

    /**
     * Writes the founder's welcome into a new conversation with her, dated
     * just before the conversation began so it reads as what came first.
     * The ids are fixed, so doing this twice changes nothing.
     * @param {string} threadId
     * @param {string} founderUID
     * @param {string[]} lines
     * @param {number} beforeMs when the conversation was created
     */
    async addWelcome(threadId, founderUID, lines, beforeMs) {
      try {
        const batch = db.batch();
        lines.forEach((text, i) => {
          batch.set(db.doc(`threads/${threadId}/messages/welcome-${i}`), {
            text,
            senderUID: founderUID,
            createdAt: Timestamp.fromMillis(beforeMs - (lines.length - i) * 1000),
            auto: true,
          });
        });
        await batch.commit();
      } catch (err) {
        logger.error(`could not write the welcome into ${threadId}`, err);
      }
    },

    /**
     * One line from Here in a person's own "system" conversation (what
     * happened to a report of hers). The conversation, threads/system_<uid>,
     * is created the first time it is needed and has no end; a phone can
     * neither create it nor write in it (firestore.rules), and its lines are
     * marked `auto` like the founder's welcome, so onMessageCreated leaves
     * them alone (no filter, no count, no push). `noticeId` is the message
     * id: writing the same notice twice changes nothing.
     * @param {string} uid
     * @param {string} noticeId
     * @param {string} text
     * @param {number} atMs
     * @return {Promise<boolean>} false when it could not be written
     */
    async addSystemNotice(uid, noticeId, text, atMs) {
      const ref = db.doc(`threads/system_${uid}`);
      try {
        try {
          // The fields the app reads on every conversation (ChatThread.swift).
          await ref.create({
            kind: "system",
            postTitle: "",
            participants: [uid, SYSTEM_SENDER],
            createdAt: Timestamp.fromMillis(atMs),
            expiresAt: Timestamp.fromMillis(NEVER_MS),
            isManuallyFrozen: false,
            hasExtendedOnce: false,
            continueChoices: {},
            nickname: "Here",
            lastRead: {},
          });
        } catch (err) {
          // 6 = ALREADY_EXISTS: the usual case from the second notice on
          if (!err || /** @type {any} */ (err).code !== 6) throw err;
        }
        await ref.collection("messages").doc(noticeId).set({
          text,
          senderUID: SYSTEM_SENDER,
          createdAt: Timestamp.fromMillis(atMs),
          auto: true,
        });
        return true;
      } catch (err) {
        logger.error(`could not write notice ${noticeId} for ${uid}`, err);
        return false;
      }
    },

    /**
     * Deletes a person's "system" conversation with everything in it (her
     * account is gone).
     * @param {string} uid
     */
    async deleteSystemThread(uid) {
      try {
        await db.recursiveDelete(db.doc(`threads/system_${uid}`));
      } catch (err) {
        logger.error(`could not delete the system conversation of ${uid}`, err);
      }
    },

    /**
     * A conversation photo did not pass its check: the message stays and is
     * marked, so both phones show the same line where the photo would be.
     * (The file itself is deleted by the caller.)
     * @param {string} threadId
     * @param {string} messageId
     */
    async markPhotoRejected(threadId, messageId) {
      try {
        await db.doc(`threads/${threadId}/messages/${messageId}`).update({imageRemoved: true});
      } catch (err) {
        logger.error(`could not mark the photo of ${threadId}/${messageId} as rejected`, err);
      }
    },

    /**
     * Conversations that may be over for good and have no date yet for
     * being deleted: the ones ended by hand, and the ones whose time has
     * run out. (Both lists only ever hold the conversations of the last
     * few days — everything older has been deleted — so reading them every
     * hour stays cheap; the limit is a ceiling for a far busier app than
     * this one is today.) Each comes with its expiry in milliseconds.
     * @param {number} nowMs
     * @return {Promise<Array<{id: string, thread: Record<string, any>}>>}
     */
    async threadsOverWithoutDate(nowMs) {
      const threads = db.collection("threads");
      const [ended, ranOut] = await Promise.all([
        threads.where("isManuallyFrozen", "==", true).limit(1000).get(),
        threads.where("expiresAt", "<=", Timestamp.fromMillis(nowMs)).limit(1000).get(),
      ]);
      const out = new Map();
      for (const d of [...ended.docs, ...ranOut.docs]) {
        const data = d.data();
        if (data.deleteAfter !== undefined || out.has(d.id)) continue;
        const end = data.expiresAt && typeof data.expiresAt.toMillis === "function" ? data.expiresAt.toMillis() : undefined;
        out.set(d.id, {id: d.id, thread: {...data, expiresAtMs: end}});
      }
      return [...out.values()];
    },

    /**
     * Writes on a conversation when it will be deleted. The app reads this
     * date to tell both people how many days are left.
     * @param {string} threadId
     * @param {number} atMs
     */
    async scheduleThreadDelete(threadId, atMs) {
      await db.doc(`threads/${threadId}`).update({deleteAfter: Timestamp.fromMillis(atMs)});
    },

    /**
     * @param {number} nowMs
     * @return {Promise<string[]>} ids of the conversations whose date has come
     */
    async threadsDueForDelete(nowMs) {
      const snap = await db.collection("threads").where("deleteAfter", "<=", Timestamp.fromMillis(nowMs)).limit(300).get();
      return snap.docs.map((d) => d.id);
    },

    /**
     * Deletes the photos of one conversation: everyone's, or only `uid`'s.
     * @param {string} threadId
     * @param {string} [uid]
     * @return {Promise<number>} how many files were deleted
     */
    async deleteChatPhotos(threadId, uid) {
      let n = 0;
      for (const f of await chatFiles(threadId, uid)) {
        await f.delete({ignoreNotFound: true});
        n += 1;
      }
      return n;
    },

    /**
     * Deletes a conversation for good: the document and everything under
     * it (its messages). Its photos are deleted by the caller first.
     * @param {string} threadId
     */
    async deleteThread(threadId) {
      await db.recursiveDelete(db.doc(`threads/${threadId}`));
    },

    /**
     * Copies the photos `uid` sent in a reported conversation to
     * reportEvidence/{reportId}/, where no phone can read them
     * (storage.rules) and where they outlive the conversation.
     * @param {string} threadId
     * @param {string} uid
     * @param {string} reportId
     * @return {Promise<number>} how many were kept
     */
    async keepEvidence(threadId, uid, reportId) {
      if (!reportId || reportId.includes("/")) return 0;
      let n = 0;
      try {
        for (const f of (await chatFiles(threadId, uid)).slice(0, 50)) {
          const name = f.name.slice(f.name.lastIndexOf("/") + 1);
          await f.copy(bucket().file(`reportEvidence/${reportId}/${name}`));
          n += 1;
        }
      } catch (err) {
        logger.error(`could not keep the photos of ${threadId} for report ${reportId}`, err);
      }
      return n;
    },

    /** @return {string[]} the names our own photo bucket goes by */
    bucketNames() {
      return buckets;
    },

    /**
     * Counts one action and returns the name of the limit it broke, or null.
     * @param {string} uid
     * @param {"post"|"thread"|"message"|"photo"|"report"} kind
     * @param {Record<string, number>} [limits]
     * @return {Promise<string | null>}
     */
    async countAction(uid, kind, limits) {
      const checks = checksFor(kind, limits);
      if (!uid || checks.length === 0) return null;
      const ref = db.doc(`rateLimits/${uid}`);
      try {
        return await db.runTransaction(async (tx) => {
          const snap = await tx.get(ref);
          const data = snap.exists ? snap.data() : undefined;
          const {state, exceeded} = bump(data && data.counters, checks, Date.now());
          tx.set(ref, {counters: state, updatedAt: FieldValue.serverTimestamp()}, {merge: true});
          return exceeded;
        });
      } catch (err) {
        logger.error("rate limit check failed; allowing", err);
        return null;
      }
    },

    /**
     * Takes a post out of the feed without deleting it: its expiry moves to
     * now. The expiry it had is kept in removed.expiresAtWas, so a moderator
     * can put the post back by copying that value into expiresAt and
     * deleting the `removed` field. Does nothing to a post that is gone or
     * was removed before.
     * @param {string} postId
     * @param {string} reason
     * @return {Promise<boolean>} whether this call removed it
     */
    async removePost(postId, reason) {
      const ref = db.doc(`posts/${postId}`);
      try {
        return await db.runTransaction(async (tx) => {
          const snap = await tx.get(ref);
          const data = snap.exists ? snap.data() : undefined;
          if (!data || data.removed) return false;
          const now = Timestamp.now();
          const was = data.expiresAt;
          /** @type {Record<string, any>} */
          const patch = {
            removed: {reason, at: FieldValue.serverTimestamp(), expiresAtWas: was === undefined ? null : was},
          };
          // Never move an expiry later: a post that already ran out stays as it is.
          if (!(was instanceof Timestamp) || was.toMillis() > now.toMillis()) patch.expiresAt = now;
          tx.update(ref, patch);
          return true;
        });
      } catch (err) {
        logger.error(`could not remove post ${postId}`, err);
        return false;
      }
    },

    /** @param {Array<{bucket: string, path: string}>} photos */
    async deleteFiles(photos) {
      for (const photo of photos) {
        try {
          await getStorage().bucket(photo.bucket).file(photo.path).delete({ignoreNotFound: true});
        } catch (err) {
          logger.error(`could not delete ${photo.path}`, err);
        }
      }
    },

    /**
     * SafeSearch annotation for one photo.
     *   {unreadable: true}  Vision answered that this file is not an image
     *                       it can read (a moderator is told; see images.js)
     *   null                Vision could not be asked at all (not enabled,
     *                       outage, file already gone): nothing happens
     * @param {{bucket: string, path: string}} photo
     * @return {Promise<{adult?: unknown, violence?: unknown, racy?: unknown, unreadable?: boolean} | null>}
     */
    async safeSearch(photo) {
      try {
        if (!vision) vision = visionFactory();
        const [result] = await vision.safeSearchDetection(`gs://${photo.bucket}/${photo.path}`);
        if (result && result.error && (result.error.message || result.error.code)) {
          logger.warn(`SafeSearch could not read ${photo.path}: ${result.error.code} ${result.error.message}`);
          // 3 = INVALID_ARGUMENT: the file itself is the problem ("Bad image data").
          return result.error.code === 3 ? {unreadable: true} : null;
        }
        return (result && result.safeSearchAnnotation) || null;
      } catch (err) {
        logger.error("SafeSearch failed; leaving the photo up", err);
        return null;
      }
    },

    /**
     * @param {string} threadId
     * @param {string} messageId
     */
    async deleteMessage(threadId, messageId) {
      try {
        await db.doc(`threads/${threadId}/messages/${messageId}`).delete();
      } catch (err) {
        logger.error(`could not delete message ${threadId}/${messageId}`, err);
      }
    },

    /** @param {string} threadId */
    async freezeThread(threadId) {
      try {
        await db.doc(`threads/${threadId}`).update({isManuallyFrozen: true});
      } catch (err) {
        logger.error(`could not end thread ${threadId}`, err);
      }
    },

    /** @param {Record<string, any>} entry */
    async log(entry) {
      try {
        await db.collection("modLog").add({...entry, at: FieldValue.serverTimestamp()});
      } catch (err) {
        logger.error("could not write modLog", err, entry);
      }
    },

    /**
     * @param {string} title
     * @param {string} body
     * @param {Record<string, string>} data
     */
    async notifyAdmins(title, body, data) {
      try {
        const s = await settings();
        for (const uid of s.adminUIDs) {
          const user = await getUser(uid);
          if (user && user.fcmToken) await sendPush(user.fcmToken, {title, body, data});
        }
        if (s.notifyEmails.length > 0) {
          await db.collection("mail").add({
            to: s.notifyEmails,
            message: {subject: `[Here] ${title}`, text: `${body}\n\n${JSON.stringify(data)}`},
          });
        }
      } catch (err) {
        logger.error("could not notify moderators", err);
      }
    },

    /**
     * @param {string} threadId
     * @return {Promise<Record<string, any> | null>}
     */
    async getThread(threadId) {
      const snap = await db.doc(`threads/${threadId}`).get();
      return snap.exists ? snap.data() || {} : null;
    },

    /**
     * Conversations whose time ran out after `fromMs` and no later than
     * `toMs`. One range on one field, so no extra index is needed.
     * @param {number} fromMs
     * @param {number} toMs
     * @return {Promise<Array<{id: string, thread: Record<string, any>}>>}
     */
    async threadsEndedBetween(fromMs, toMs) {
      const snap = await db.collection("threads")
          .where("expiresAt", ">", Timestamp.fromMillis(fromMs))
          .where("expiresAt", "<=", Timestamp.fromMillis(toMs))
          .limit(500)
          .get();
      return snap.docs.map((d) => ({id: d.id, thread: d.data()}));
    },

    /**
     * Marks a conversation as told that its time is up. Returns false if it
     * was marked before (or is gone), so that of two runs happening at once
     * only one goes on to send.
     * @param {string} threadId
     * @return {Promise<boolean>} whether this call was the one that marked it
     */
    async claimTimeUp(threadId) {
      const ref = db.doc(`threads/${threadId}`);
      return db.runTransaction(async (tx) => {
        const snap = await tx.get(ref);
        const data = snap.exists ? snap.data() : undefined;
        if (!data || data.timeUpPushAt) return false;
        tx.update(ref, {timeUpPushAt: FieldValue.serverTimestamp()});
        return true;
      });
    },

    /**
     * @param {string} postId
     * @return {Promise<(Record<string, any> & {expiresAtMs: number}) | null>}
     */
    async getPost(postId) {
      const snap = await db.doc(`posts/${postId}`).get();
      if (!snap.exists) return null;
      const data = snap.data() || {};
      const exp = data.expiresAt;
      return {...data, expiresAtMs: exp && typeof exp.toMillis === "function" ? exp.toMillis() : 0};
    },

    /**
     * How many of the newest messages after `lastRead` came from `sender`.
     * @param {string} threadId
     * @param {string} sender
     * @param {FirebaseFirestore.Timestamp | undefined} lastRead
     * @return {Promise<number>}
     */
    async unreadFrom(threadId, sender, lastRead) {
      /** @type {FirebaseFirestore.Query} */
      let q = db.collection(`threads/${threadId}/messages`);
      if (lastRead) q = q.where("createdAt", ">", lastRead);
      const snap = await q.orderBy("createdAt", "desc").limit(10).get();
      return snap.docs.filter((d) => d.data().senderUID === sender).length;
    },

    /**
     * @param {string} uid
     * @param {number} n
     */
    async setUnreadTotal(uid, n) {
      try {
        // update(), not set(): never recreate the doc of a deleted account
        await db.doc(`users/${uid}`).update({unreadTotal: n});
      } catch (err) {
        logger.debug(`no user doc to set a badge on (${uid})`);
      }
    },

    /** @param {string} uid */
    async clearToken(uid) {
      try {
        // update(), not set(): never recreate the doc of a deleted account
        await db.doc(`users/${uid}`).update({fcmToken: FieldValue.delete()});
      } catch (err) {
        logger.debug(`no user doc to clear a token on (${uid})`);
      }
    },

    /** @param {string} uid */
    async clearPresence(uid) {
      try {
        await db.doc(`voicePresence/${uid}`).delete();
      } catch (err) {
        logger.error(`could not clear presence for ${uid}`, err);
      }
    },

    /**
     * The reports on this post, one entry per report with who filed it and
     * the reasons she picked (ignored reports excluded). A report from before
     * several reasons could be picked has one.
     * @param {string} postId
     * @return {Promise<Array<{reporterUID: string, reasons: string[]}>>}
     */
    async reportsOf(postId) {
      const snap = await db.collection("reports").where("postId", "==", postId).limit(200).get();
      /** @type {Array<{reporterUID: string, reasons: string[]}>} */
      const list = [];
      for (const d of snap.docs) {
        const r = d.data();
        if (r.type === "post" && !r.ignored && typeof r.reporterUID === "string") {
          list.push({reporterUID: r.reporterUID, reasons: reasonsOf(r)});
        }
      }
      return list;
    },

    /**
     * Which of these accounts have a verified phone number. Anonymous
     * accounts cost nothing to create, so only verified ones count toward
     * hiding a post. If the lookup fails, nobody counts.
     * @param {string[]} uids
     * @return {Promise<string[]>}
     */
    async verifiedAmong(uids) {
      /** @type {string[]} */
      const out = [];
      try {
        for (let i = 0; i < uids.length; i += 100) {
          const result = await getAuth().getUsers(uids.slice(i, i + 100).map((uid) => ({uid})));
          for (const user of result.users) {
            if (user.phoneNumber && !user.disabled) out.push(user.uid);
          }
        }
      } catch (err) {
        logger.error("could not look up reporters", err);
        return [];
      }
      return out;
    },

    /**
     * @param {string} reportId
     * @param {Record<string, any>} patch
     */
    async markReport(reportId, patch) {
      try {
        await db.doc(`reports/${reportId}`).update(patch);
      } catch (err) {
        logger.error(`could not update report ${reportId}`, err);
      }
    },

    /**
     * @param {string} phone E.164, e.g. +14155551234
     * @return {Promise<string | null>}
     */
    async uidForPhone(phone) {
      try {
        const user = await getAuth().getUserByPhoneNumber(phone);
        return user.uid;
      } catch (err) {
        const code = err && typeof err === "object" && "code" in err ? err.code : "";
        if (code !== "auth/user-not-found") logger.error("phone lookup failed", err);
        return null;
      }
    },

    /**
     * Posts by this person that are still in the feed.
     * @param {string} uid
     * @return {Promise<string[]>}
     */
    async livePostIdsBy(uid) {
      const now = Date.now();
      const snap = await db.collection("posts").where("authorUID", "==", uid).get();
      return snap.docs
          .filter((d) => {
            const p = d.data();
            const exp = p.expiresAt && typeof p.expiresAt.toMillis === "function" ? p.expiresAt.toMillis() : 0;
            return exp > now && !p.removed;
          })
          .map((d) => d.id);
    },

    /**
     * Conversations this person is in that have not been ended.
     * @param {string} uid
     * @return {Promise<string[]>}
     */
    async openThreadIdsOf(uid) {
      const snap = await db.collection("threads").where("participants", "array-contains", uid).get();
      return snap.docs.filter((d) => d.data().isManuallyFrozen !== true).map((d) => d.id);
    },

    /**
     * Deletes every post and post photo of this person, and her counters.
     * (Her photos in conversations: see deleteChatPhotos.)
     * @param {string} uid
     * @return {Promise<{posts: number, files: number}>}
     */
    async deleteUserContent(uid) {
      let posts = 0;
      let files = 0;
      try {
        const snap = await db.collection("posts").where("authorUID", "==", uid).get();
        for (const d of snap.docs) {
          await d.ref.delete();
          posts += 1;
        }
      } catch (err) {
        logger.error(`could not delete posts of ${uid}`, err);
      }
      try {
        const [list] = await bucket().getFiles({prefix: `posts/${uid}/`});
        for (const f of list) {
          await f.delete({ignoreNotFound: true});
          files += 1;
        }
      } catch (err) {
        logger.error(`could not delete photos of ${uid}`, err);
      }
      try {
        await db.doc(`rateLimits/${uid}`).delete();
      } catch (err) {
        logger.error(`could not delete counters of ${uid}`, err);
      }
      return {posts, files};
    },
  };
}

module.exports = {createStore, defaultBucketName, ownBucketNames};
