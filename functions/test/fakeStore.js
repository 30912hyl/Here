"use strict";

/**
 * In-memory stand-in for lib/store.js, with the same method names. It keeps
 * a record of everything the handlers asked for so tests can assert on it.
 */

const {checksFor, bump} = require("../lib/rateLimit");
const {normalizeSettings, normalizeAppConfig} = require("../lib/settings");
const {reasonsOf} = require("../lib/reasons");

const BUCKET = "here-a6817.firebasestorage.app";

/** A download URL shaped like the ones the iOS SDK returns. */
function photoUrl(uid, folder = "F1", file = "0_a.jpg", bucket = BUCKET) {
  const path = encodeURIComponent(`posts/${uid}/${folder}/${file}`);
  return `https://firebasestorage.googleapis.com:443/v0/b/${bucket}/o/${path}?alt=media&token=t0ken`;
}

function fakeStore(init = {}) {
  const s = {
    now: init.now ?? 1_800_000_000_000,
    settingsDoc: init.settings,
    configDoc: init.config,
    posts: {...(init.posts || {})},
    threads: {...(init.threads || {})},
    users: {...(init.users || {})},
    reports: {...(init.reports || {})},
    // accounts WITHOUT a verified phone number; everyone else counts as verified
    unverified: new Set(init.unverified || []),
    phones: {...(init.phones || {})},
    annotations: {...(init.annotations || {})},
    unread: init.unread ?? 1,
    pushResult: init.pushResult || "ok",
    files: new Set(init.files || []),
    counters: {},
    removedPosts: [],
    deletedFiles: [],
    deletedFrom: [],
    deletedMessages: [],
    frozen: [],
    logs: [],
    adminNotes: [],
    pushes: [],
    clearedTokens: [],
    clearedPresence: [],
    safeSearchCalls: [],
    reportPatches: {},
    verifiedLookups: [],
    deletedUsers: [],
    sweeps: [],
    claimed: [],
    // conversations whose "told" mark cannot be written (a failed transaction)
    failClaim: new Set(init.failClaim || []),
    checkedPhotos: [],
    rejectedPhotos: [],
    deletedThreads: [],
    failSchedule: new Set(init.failSchedule || []),
    welcomes: [],
    systemNotices: [],
    deletedSystem: [],
    // people whose notice cannot be written (Firestore is down)
    failNotice: new Set(init.failNotice || []),
    evidence: [],
    // conversations whose photos cannot be deleted (Storage is down)
    failPhotoDelete: new Set(init.failPhotoDelete || []),
  };

  return {
    s,
    async settings() {
      return normalizeSettings(s.settingsDoc);
    },
    async appConfig() {
      return normalizeAppConfig(s.configDoc);
    },
    bucketNames() {
      return [BUCKET, "here-a6817.appspot.com"];
    },
    photoAt(path) {
      return {bucket: BUCKET, path};
    },
    async markPhotoChecked(threadId, messageId) {
      s.checkedPhotos.push(`${threadId}/${messageId}`);
      if (s.threads[threadId]) s.threads[threadId] = {...s.threads[threadId], hasPhotos: true};
    },
    async addWelcome(threadId, founderUID, lines, beforeMs) {
      s.welcomes.push({threadId, founderUID, lines, beforeMs});
    },
    async addSystemNotice(uid, noticeId, text, atMs) {
      if (s.failNotice.has(uid)) return false;
      const at = s.systemNotices.findIndex((n) => n.uid === uid && n.noticeId === noticeId);
      if (at >= 0) s.systemNotices[at] = {uid, noticeId, text, atMs};
      else s.systemNotices.push({uid, noticeId, text, atMs});
      return true;
    },
    async deleteSystemThread(uid) {
      s.deletedSystem.push(uid);
      s.systemNotices = s.systemNotices.filter((n) => n.uid !== uid);
    },
    async markPhotoRejected(threadId, messageId) {
      s.rejectedPhotos.push(`${threadId}/${messageId}`);
    },
    async threadsOverWithoutDate(nowMs) {
      return Object.entries(s.threads)
        .filter(([, t]) => t.deleteAfterMs === undefined &&
          (t.isManuallyFrozen === true || (typeof t.expiresAtMs === "number" && t.expiresAtMs <= nowMs)))
        .map(([id, t]) => ({id, thread: t}));
    },
    async scheduleThreadDelete(threadId, atMs) {
      if (s.failSchedule.has(threadId)) throw new Error("firestore is down");
      s.threads[threadId] = {...s.threads[threadId], deleteAfterMs: atMs};
    },
    async threadsDueForDelete(nowMs) {
      return Object.entries(s.threads).filter(([, t]) => typeof t.deleteAfterMs === "number" && t.deleteAfterMs <= nowMs).map(([id]) => id);
    },
    async deleteThread(threadId) {
      delete s.threads[threadId];
      s.deletedThreads.push(threadId);
    },
    async deleteChatPhotos(threadId, uid) {
      if (s.failPhotoDelete.has(threadId)) throw new Error("storage is down");
      const prefix = uid === undefined ? `chats/${threadId}/` : `chats/${threadId}/${uid}/`;
      let n = 0;
      for (const f of [...s.files]) {
        if (f.startsWith(prefix)) {
          s.files.delete(f);
          s.deletedFiles.push(f);
          n += 1;
        }
      }
      return n;
    },
    async keepEvidence(threadId, uid, reportId) {
      let n = 0;
      for (const f of [...s.files]) {
        if (f.startsWith(`chats/${threadId}/${uid}/`)) {
          const kept = `reportEvidence/${reportId}/${f.slice(f.lastIndexOf("/") + 1)}`;
          s.files.add(kept);
          s.evidence.push(kept);
          n += 1;
        }
      }
      return n;
    },
    async countAction(uid, kind, limits) {
      const {state, exceeded} = bump(s.counters[uid], checksFor(kind, limits), s.now);
      s.counters[uid] = state;
      return exceeded;
    },
    async removePost(postId, reason) {
      s.removedPosts.push({postId, reason});
      const post = s.posts[postId];
      if (post && post.removed) return false;
      if (post) s.posts[postId] = {...post, removed: {reason, expiresAtWas: post.expiresAtMs}, expiresAtMs: Math.min(post.expiresAtMs, s.now)};
      return true;
    },
    async deleteFiles(photos) {
      for (const photo of photos) {
        s.deletedFiles.push(photo.path);
        s.deletedFrom.push(photo.bucket);
        s.files.delete(photo.path);
      }
    },
    async safeSearch(photo) {
      s.safeSearchCalls.push(photo.path);
      return photo.path in s.annotations ? s.annotations[photo.path] : {adult: "VERY_UNLIKELY", violence: "UNLIKELY", racy: "UNLIKELY"};
    },
    async deleteMessage(threadId, messageId) {
      s.deletedMessages.push(`${threadId}/${messageId}`);
    },
    async freezeThread(threadId) {
      s.frozen.push(threadId);
      if (s.threads[threadId]) s.threads[threadId] = {...s.threads[threadId], isManuallyFrozen: true};
    },
    async log(entry) {
      s.logs.push(entry);
    },
    async notifyAdmins(title, body, data) {
      s.adminNotes.push({title, body, data});
    },
    async getThread(id) {
      return s.threads[id] || null;
    },
    async threadsEndedBetween(fromMs, toMs) {
      s.sweeps.push([fromMs, toMs]);
      return Object.entries(s.threads)
          .filter(([, t]) => t.expiresAtMs > fromMs && t.expiresAtMs <= toMs)
          .map(([id, t]) => ({id, thread: t}));
    },
    async claimTimeUp(id) {
      if (s.failClaim.has(id)) throw new Error("transaction failed");
      const t = s.threads[id];
      if (!t || t.timeUpPushAt) return false;
      s.threads[id] = {...t, timeUpPushAt: s.now};
      s.claimed.push(id);
      return true;
    },
    async getUser(uid) {
      return s.users[uid] || null;
    },
    async getPost(id) {
      return s.posts[id] || null;
    },
    async unreadFrom() {
      return s.unread;
    },
    async setUnreadTotal(uid, n) {
      s.users[uid] = {...(s.users[uid] || {}), unreadTotal: n};
    },
    async sendPush(token, push) {
      s.pushes.push({token, ...push});
      return (init.pushResults && init.pushResults[token]) || s.pushResult;
    },
    async clearToken(uid) {
      s.clearedTokens.push(uid);
    },
    async clearPresence(uid) {
      s.clearedPresence.push(uid);
    },
    async reportsOf(postId) {
      return Object.values(s.reports)
          .filter((r) => r.type === "post" && r.postId === postId && !r.ignored)
          .map((r) => ({reporterUID: r.reporterUID, reasons: reasonsOf(r)}));
    },
    async verifiedAmong(uids) {
      s.verifiedLookups.push(uids);
      return uids.filter((u) => !s.unverified.has(u));
    },
    async markReport(id, patch) {
      s.reportPatches[id] = patch;
      if (s.reports[id]) s.reports[id] = {...s.reports[id], ...patch};
    },
    async uidForPhone(phone) {
      return s.phones[phone] || null;
    },
    async livePostIdsBy(uid) {
      return Object.entries(s.posts)
          .filter(([, p]) => p.authorUID === uid && p.expiresAtMs > s.now && !p.removed)
          .map(([id]) => id);
    },
    async openThreadIdsOf(uid) {
      return Object.entries(s.threads)
          .filter(([, t]) => (t.participants || []).includes(uid) && t.isManuallyFrozen !== true)
          .map(([id]) => id);
    },
    async deleteUserContent(uid) {
      s.deletedUsers.push(uid);
      let posts = 0;
      for (const [id, p] of Object.entries(s.posts)) {
        if (p.authorUID === uid) {
          delete s.posts[id];
          posts += 1;
        }
      }
      let files = 0;
      for (const f of [...s.files]) {
        if (f.startsWith(`posts/${uid}/`)) {
          s.files.delete(f);
          files += 1;
        }
      }
      return {posts, files};
    },
  };
}

module.exports = {fakeStore, photoUrl, BUCKET};
