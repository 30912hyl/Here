"use strict";

/**
 * Server-side copy of the app's on-device text check
 * (Here/Services/ContentFilter.swift). The app runs the same check before
 * anything is sent; this copy exists so that a modified app cannot skip it.
 *
 * Keep the two in step: a change to one list belongs in both files.
 *
 * Deliberately narrow, like the app's: expressing sadness or dark feelings
 * is never filtered. What is caught: slurs, telling someone to kill
 * themselves, sexual solicitation, and contact details.
 */

// Stored base64-encoded, as in the Swift file, so the words themselves do
// not appear in the source.
const SLURS = new Set([
  "bmlnZ2Vy",
  "bmlnZ2E=",
  "ZmFnZ290",
  "dHJhbm55",
  "Y2hpbms=",
  "c3BpYw==",
  "a2lrZQ==",
  "d2V0YmFjaw==",
  "Z29vaw==",
  "Y29vbg==",
  "cGFraQ==",
  "cmFnaGVhZA==",
  "dG93ZWxoZWFk",
  "YmVhbmVy",
].map((b64) => Buffer.from(b64, "base64").toString("utf8")));

const LEET = {
  "0": "o", "1": "i", "3": "e", "4": "a", "5": "s", "7": "t",
  "@": "a", "$": "s", "!": "i",
};

const IS_LETTER = /\p{L}/u;

/**
 * Lowercase, fold accents, undo common letter substitutions, turn everything
 * that is not a letter into a space, and squeeze long letter runs
 * ("sooooo" -> "soo") so trivial disguises still match.
 *
 * One deliberate difference from the app: the app reads every "!" as the
 * letter i (to catch "k!ll"), which also glues an i onto any word followed
 * by an exclamation mark, so "... yourself!" slips through. Here a "!" only
 * counts as a letter when a letter follows it. The same fix belongs in
 * ContentFilter.swift.
 * @param {string} s
 * @return {string}
 */
function normalize(s) {
  const chars = [...String(s)
      .normalize("NFD")
      .replace(/\p{M}+/gu, "")
      .toLowerCase()];
  let out = "";
  let last = " ";
  let run = 0;
  for (let i = 0; i < chars.length; i++) {
    const ch = chars[i];
    let c = LEET[ch] ?? ch;
    if (ch === "!") {
      const next = chars[i + 1];
      const nextIsLetter = next !== undefined && next !== "!" && IS_LETTER.test(LEET[next] ?? next);
      c = nextIsLetter ? "i" : " ";
    }
    if (!IS_LETTER.test(c)) c = " ";
    if (c === last) {
      run += 1;
      if (c === " ") continue;
      if (run >= 2) continue;
    } else {
      run = 0;
    }
    out += c;
    last = c;
  }
  return out.trim();
}

const HARASSMENT = [
  "kill yourself", "kill urself", "kys", "go die", "you should die",
  "end yourself", "nobody would miss you", "hope you die",
].map(normalize);

const SEXUAL = [
  "send nudes", "send nude", "send me nudes", "send pics", "dick pic",
  "dickpic", "sext me", "show me your body", "show me your tits",
  "show me your boobs", "wanna fuck", "want to fuck", "lets fuck",
  "come over tonight",
].map(normalize);

const CONTACT = [
  // email
  /[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}/i,
  // links
  /(https?:\/\/|www\.)\S+/i,
  /\b[a-z0-9-]+\.(com|net|org|io|me|app|co|ly|gg|tv|xyz)\b/i,
  // phone numbers: 7+ digits, allowing spaces, dots, dashes, brackets
  /(\+?\d[\s\-.()]*){7,}/,
  // @handles
  /(^|\s)@[a-z0-9._]{3,}/i,
  // "insta: name", "snap - name", "wechat：name"
  /\b(snap(chat)?|insta(gram)?|ig|telegram|tg|whatsapp|wechat|discord|kik|line|tiktok)\s*[:：-]\s*@?[a-z0-9._]{3,}/i,
];

/**
 * @param {string} text
 * @return {boolean}
 */
function containsContactInfo(text) {
  return CONTACT.some((re) => re.test(text));
}

/**
 * @typedef {"ok"|"slur"|"harassment"|"sexual"|"contact"} Verdict
 */

/**
 * Same order of checks as the app. `contact` means "the app refuses this in
 * a post, and asks the sender to confirm in a private message".
 * @param {"post"|"message"} context
 * @param {...(string|undefined|null)} texts
 * @return {Verdict}
 */
function check(context, ...texts) {
  const raw = texts.filter((t) => typeof t === "string").join("\n");
  const normalized = normalize(raw);
  const tokens = normalized.split(" ");
  if (tokens.some((t) => SLURS.has(t))) return "slur";
  if (context === "message") {
    const padded = ` ${normalized} `;
    if (HARASSMENT.some((p) => padded.includes(` ${p} `))) return "harassment";
    if (SEXUAL.some((p) => padded.includes(` ${p} `))) return "sexual";
  }
  if (containsContactInfo(raw)) return "contact";
  return "ok";
}

module.exports = {check, normalize, containsContactInfo};
