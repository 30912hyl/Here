"use strict";

/**
 * Fixed-window counters, one small document per person (rateLimits/{uid}).
 * Pure functions here; the document read/write lives in store.js.
 */

const MINUTE = 60 * 1000;
const HOUR = 60 * MINUTE;
const DAY = 24 * HOUR;

/** Defaults; settings/moderation.limits can override any of them. */
const DEFAULT_LIMITS = {
  postsPerHour: 6,
  postsPerDay: 20,
  threadsPerHour: 20,
  messagesPerMinute: 40,
  photosPerDay: 30,
  reportsPerHour: 20,
};

/**
 * The counters each kind of action is checked against.
 * @param {"post"|"thread"|"message"|"photo"|"report"} kind
 * @param {Partial<typeof DEFAULT_LIMITS>} [overrides]
 * @return {Array<{key: string, windowMs: number, limit: number}>}
 */
function checksFor(kind, overrides) {
  const l = {...DEFAULT_LIMITS};
  for (const [k, v] of Object.entries(overrides || {})) {
    if (k in l && Number.isFinite(v) && v > 0) l[k] = v;
  }
  switch (kind) {
    case "post":
      return [
        {key: "postH", windowMs: HOUR, limit: l.postsPerHour},
        {key: "postD", windowMs: DAY, limit: l.postsPerDay},
      ];
    case "thread":
      return [{key: "threadH", windowMs: HOUR, limit: l.threadsPerHour}];
    case "message":
      return [{key: "msgM", windowMs: MINUTE, limit: l.messagesPerMinute}];
    case "photo":
      // Photos in conversations. A photo message also counts as a message.
      return [{key: "photoD", windowMs: DAY, limit: l.photosPerDay}];
    case "report":
      return [{key: "reportH", windowMs: HOUR, limit: l.reportsPerHour}];
    default:
      return [];
  }
}

/**
 * Counts one more action against every check and says whether any limit is
 * now exceeded. `state` is the stored document (or undefined); the returned
 * `state` is what to store back.
 * @param {Record<string, {w: number, n: number}> | undefined} state
 * @param {Array<{key: string, windowMs: number, limit: number}>} checks
 * @param {number} nowMs
 * @return {{state: Record<string, {w: number, n: number}>, exceeded: string | null}}
 */
function bump(state, checks, nowMs) {
  const next = {...(state || {})};
  let exceeded = null;
  for (const {key, windowMs, limit} of checks) {
    const w = Math.floor(nowMs / windowMs);
    const cur = next[key];
    const n = cur && cur.w === w && Number.isFinite(cur.n) ? cur.n + 1 : 1;
    next[key] = {w, n};
    if (n > limit && !exceeded) exceeded = key;
  }
  return {state: next, exceeded};
}

module.exports = {DEFAULT_LIMITS, checksFor, bump};
