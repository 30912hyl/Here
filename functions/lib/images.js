"use strict";

/**
 * Photo checks for posts and for conversations.
 *
 * The app uploads post photos to Storage at posts/{authorUid}/{folder}/{file}
 * and stores their download URLs on the post. Two things are checked here:
 *   1. every URL really points at that author's folder in our own bucket
 *      (anything else would be an image we cannot scan, and one its owner
 *      could swap for another after posting);
 *   2. what Cloud Vision SafeSearch says about each photo.
 *
 * A photo sent in a conversation is uploaded to
 * chats/{conversation}/{senderUid}/{name}.jpg and the message stores that
 * path (not a URL: only the two people in the conversation may fetch it,
 * and storage.rules decides that each time). The same two checks apply.
 */

const STORAGE_HOST = "firebasestorage.googleapis.com";

/**
 * Splits a Firebase Storage download URL into bucket and object path.
 * Returns null for anything that is not one.
 * @param {unknown} url
 * @return {{bucket: string, path: string} | null}
 */
function parseStorageUrl(url) {
  if (typeof url !== "string") return null;
  let u;
  try {
    u = new URL(url);
  } catch (_) {
    return null;
  }
  if (u.protocol !== "https:" || u.hostname !== STORAGE_HOST) return null;
  // new URL() drops the default port, so ":443" (which the iOS SDK writes)
  // is fine and anything else is refused. No user:password@ part either.
  if (u.port !== "" || u.username !== "" || u.password !== "") return null;
  // /v0/b/{bucket}/o/{object path, percent-encoded as one segment}
  const m = /^\/v0\/b\/([^/]+)\/o\/(.+)$/.exec(u.pathname);
  if (!m) return null;
  let bucket;
  let path;
  try {
    bucket = decodeURIComponent(m[1]);
    path = decodeURIComponent(m[2]);
  } catch (_) {
    return null;
  }
  if (path.includes("..")) return null;
  return {bucket, path};
}

/**
 * Where the photo is stored, if `url` is a photo in `uid`'s own folder of
 * one of our buckets; otherwise null.
 * @param {unknown} url
 * @param {string[]} buckets the names our own bucket goes by
 * @param {string} uid
 * @return {{bucket: string, path: string} | null}
 */
function ownPhoto(url, buckets, uid) {
  const parsed = parseStorageUrl(url);
  if (!parsed || !buckets.includes(parsed.bucket)) return null;
  if (!uid || !parsed.path.startsWith(`posts/${uid}/`)) return null;
  return parsed;
}

/**
 * The path itself, if it names a file `uid` could have uploaded for the
 * conversation `threadId`; otherwise null.
 * @param {unknown} path
 * @param {string} threadId
 * @param {string} uid
 * @return {string | null}
 */
function chatPhotoPath(path, threadId, uid) {
  if (typeof path !== "string" || !threadId || !uid) return null;
  const parts = path.split("/");
  if (parts.length !== 4 || parts[0] !== "chats" || parts[1] !== threadId || parts[2] !== uid) return null;
  return /^[A-Za-z0-9_-]+\.jpg$/.test(parts[3]) ? path : null;
}

const LEVEL = {
  UNKNOWN: 0, VERY_UNLIKELY: 1, UNLIKELY: 2, POSSIBLE: 3, LIKELY: 4,
  VERY_LIKELY: 5,
};

/**
 * @param {unknown} v a likelihood as Vision returns it (name or number)
 * @return {number}
 */
function level(v) {
  if (typeof v === "number") return v;
  if (typeof v === "string" && v in LEVEL) return LEVEL[v];
  return 0;
}

/**
 * What to do with a photo given its SafeSearch annotation.
 *   remove     - explicit nudity or graphic violence
 *   review     - keep it up, but tell a moderator
 *   unreadable - the file is not an image Vision can read; the app only
 *                uploads JPEGs, so keep it up but tell a moderator
 *   ok         - nothing to do (also when Vision could not be asked)
 * "Racy" alone (swimwear, a low neckline) never removes a photo.
 * @param {{adult?: unknown, violence?: unknown, racy?: unknown, unreadable?: boolean} | null | undefined} a
 * @return {"ok" | "review" | "unreadable" | "remove"}
 */
function safeSearchVerdict(a) {
  if (!a) return "ok";
  if (a.unreadable === true) return "unreadable";
  if (level(a.adult) >= LEVEL.LIKELY) return "remove";
  if (level(a.violence) >= LEVEL.VERY_LIKELY) return "remove";
  if (level(a.violence) >= LEVEL.LIKELY) return "review";
  if (level(a.racy) >= LEVEL.VERY_LIKELY) return "review";
  return "ok";
}

module.exports = {parseStorageUrl, ownPhoto, chatPhotoPath, safeSearchVerdict};
