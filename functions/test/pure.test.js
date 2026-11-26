"use strict";

const test = require("node:test");
const assert = require("node:assert/strict");

const {check, normalize, containsContactInfo} = require("../lib/textFilter");
const {parseStorageUrl, ownPhoto, safeSearchVerdict} = require("../lib/images");
const {checksFor, bump, DEFAULT_LIMITS} = require("../lib/rateLimit");
const {normalizeSettings} = require("../lib/settings");
const {photoUrl, BUCKET} = require("./fakeStore");

// One entry of the slur list, decoded at run time so the word itself is not
// written in this file.
const SLUR = Buffer.from("a2lrZQ==", "base64").toString("utf8");

test("normalize: case, accents, leetspeak, long runs, punctuation", () => {
  assert.equal(normalize("Sooooo coooool!!!"), "soo cool");
  assert.equal(normalize("Café  Münü"), "cafe munu");
  assert.equal(normalize("h3ll0 w0rld"), "hello world");
  assert.equal(normalize("K!LL"), "kill");
  assert.equal(normalize("  a   b  "), "a b");
  assert.equal(normalize(""), "");
});

test("feelings, however dark, are never filtered", () => {
  for (const text of [
    "i want to die",
    "I keep thinking about killing myself",
    "he told me to kill myself and i believed him for a while",
    "today I hate everything about my body",
    "今天真的撑不下去了",
  ]) {
    assert.equal(check("post", text), "ok", text);
    assert.equal(check("message", text), "ok", text);
  }
});

test("slurs are caught in posts and messages, through simple disguises", () => {
  const leet = SLUR.replace("i", "1").replace("e", "3");
  for (const text of [SLUR, SLUR.toUpperCase(), `you ${SLUR}!`, `you ${leet}`, `${SLUR}.`]) {
    assert.equal(check("post", "a title", text), "slur", text);
    assert.equal(check("message", text), "slur", text);
  }
  // only as a whole word
  assert.equal(check("post", `x${SLUR}x`), "ok");
});

test("slurs in tags count too", () => {
  assert.equal(check("post", "title", "body", `ok ${SLUR}`), "slur");
});

test("harassment and sexual requests are caught in messages only", () => {
  for (const text of ["kill yourself", "KYS", "kys!", "just k!ll yourself", "Go die!!", "nobody would miss you."]) {
    assert.equal(check("message", text), "harassment", text);
  }
  for (const text of ["send nudes", "Send me nudes!", "wanna fuck?"]) {
    assert.equal(check("message", text), "sexual", text);
  }
  // Posts quote what was said to the author, so the same words pass there.
  assert.equal(check("post", "he said", "kill yourself"), "ok");
  assert.equal(check("post", "he wrote", "send nudes"), "ok");
  // Whole phrases only.
  assert.equal(check("message", "the skys are blue"), "ok");
  assert.equal(check("message", "i will send pictures of my dog"), "ok");
});

test("contact details", () => {
  for (const text of [
    "mail me at jane.doe@example.com",
    "see https://example.com/x",
    "www.example.org",
    "my site is janedoe.io",
    "call 415 555 0123",
    "+1 (415) 555-0123",
    "find me @jane_doe",
    "insta: janedoe",
    "wechat：jane123",
  ]) {
    assert.equal(containsContactInfo(text), true, text);
    assert.equal(check("post", text), "contact", text);
    assert.equal(check("message", text), "contact", text);
  }
  for (const text of ["I feel 100% done", "it was 3 am again", "we met in 2019", "so. tired."]) {
    assert.equal(containsContactInfo(text), false, text);
  }
});

test("a slur outranks contact details", () => {
  assert.equal(check("message", `${SLUR} call 415 555 0123`), "slur");
});

test("non-strings are ignored", () => {
  assert.equal(check("post", undefined, null, "hello"), "ok");
});

test("parseStorageUrl reads the iOS download URL shape", () => {
  assert.deepEqual(parseStorageUrl(photoUrl("u1")), {bucket: BUCKET, path: "posts/u1/F1/0_a.jpg"});
  // without the explicit port, and with an unencoded path
  assert.deepEqual(
      parseStorageUrl(`https://firebasestorage.googleapis.com/v0/b/${BUCKET}/o/posts/u1/F1/0_a.jpg?alt=media`),
      {bucket: BUCKET, path: "posts/u1/F1/0_a.jpg"});
});

test("parseStorageUrl refuses everything else", () => {
  for (const url of [
    "https://evil.example.com/v0/b/x/o/posts%2Fu1%2Fa.jpg",
    `http://firebasestorage.googleapis.com/v0/b/${BUCKET}/o/posts%2Fu1%2Fa.jpg`,
    `https://firebasestorage.googleapis.com.evil.example/v0/b/${BUCKET}/o/posts%2Fu1%2Fa.jpg`,
    `https://firebasestorage.googleapis.com/v0/b/${BUCKET}/o/posts%2Fu1%2F..%2F..%2Fother.jpg`,
    `https://firebasestorage.googleapis.com/v0/b/${BUCKET}`,
    "not a url",
    "",
    null,
    42,
  ]) {
    assert.equal(parseStorageUrl(url), null, String(url));
  }
});

test("ownPhoto: only the author's folder in one of our buckets", () => {
  const ours = [BUCKET, "here-a6817.appspot.com"];
  assert.deepEqual(ownPhoto(photoUrl("u1"), ours, "u1"), {bucket: BUCKET, path: "posts/u1/F1/0_a.jpg"});
  // the older spelling of the same bucket is accepted, and remembered
  assert.deepEqual(ownPhoto(photoUrl("u1", "F1", "a.jpg", "here-a6817.appspot.com"), ours, "u1"),
      {bucket: "here-a6817.appspot.com", path: "posts/u1/F1/a.jpg"});
  assert.equal(ownPhoto(photoUrl("u2"), ours, "u1"), null);
  assert.equal(ownPhoto(photoUrl("u1", "F1", "a.jpg", "someone-elses-bucket"), ours, "u1"), null);
  assert.equal(ownPhoto(photoUrl("u1x"), ours, "u1"), null);
  assert.equal(ownPhoto(photoUrl("u1"), ours, ""), null);
  assert.equal(ownPhoto(photoUrl("u1"), [], "u1"), null);
});

test("safeSearchVerdict", () => {
  assert.equal(safeSearchVerdict(null), "ok");
  assert.equal(safeSearchVerdict({}), "ok");
  assert.equal(safeSearchVerdict({adult: "POSSIBLE", racy: "LIKELY", violence: "POSSIBLE"}), "ok");
  assert.equal(safeSearchVerdict({adult: "LIKELY"}), "remove");
  assert.equal(safeSearchVerdict({adult: "VERY_LIKELY"}), "remove");
  assert.equal(safeSearchVerdict({violence: "VERY_LIKELY"}), "remove");
  assert.equal(safeSearchVerdict({violence: "LIKELY"}), "review");
  assert.equal(safeSearchVerdict({racy: "VERY_LIKELY"}), "review");
  // numeric enums, as some client configurations return them
  assert.equal(safeSearchVerdict({adult: 5}), "remove");
  assert.equal(safeSearchVerdict({adult: 2, racy: 5}), "review");
  assert.equal(safeSearchVerdict({adult: "SOMETHING_NEW"}), "ok");
  // a file Vision cannot read is neither passed silently nor removed
  assert.equal(safeSearchVerdict({unreadable: true}), "unreadable");
});

test("bump: counts inside a window and starts over in the next", () => {
  const hour = 3600 * 1000;
  const checks = [{key: "k", windowMs: hour, limit: 2}];
  let r = bump(undefined, checks, 10 * hour + 5);
  assert.equal(r.exceeded, null);
  r = bump(r.state, checks, 10 * hour + 100);
  assert.equal(r.exceeded, null);
  r = bump(r.state, checks, 10 * hour + 200);
  assert.equal(r.exceeded, "k");
  assert.equal(r.state.k.n, 3);
  r = bump(r.state, checks, 11 * hour + 1);
  assert.equal(r.exceeded, null);
  assert.equal(r.state.k.n, 1);
});

test("bump: keeps other counters and reports the first limit broken", () => {
  const checks = checksFor("post", {postsPerHour: 1, postsPerDay: 1});
  let r = bump({other: {w: 1, n: 9}}, checks, 1e12);
  assert.equal(r.exceeded, null);
  assert.deepEqual(r.state.other, {w: 1, n: 9});
  r = bump(r.state, checks, 1e12 + 1);
  assert.equal(r.exceeded, "postH");
});

test("checksFor: defaults, overrides, and nonsense overrides", () => {
  assert.equal(checksFor("post")[0].limit, DEFAULT_LIMITS.postsPerHour);
  assert.equal(checksFor("message", {messagesPerMinute: 5})[0].limit, 5);
  assert.equal(checksFor("report", {reportsPerHour: -1})[0].limit, DEFAULT_LIMITS.reportsPerHour);
  assert.equal(checksFor("report", {reportsPerHour: "many"})[0].limit, DEFAULT_LIMITS.reportsPerHour);
  assert.deepEqual(checksFor("nothing"), []);
});

test("normalizeSettings: safe defaults for missing or wrong values", () => {
  assert.deepEqual(normalizeSettings(undefined), {
    adminUIDs: [], notifyEmails: [], autoHideReports: 3, autoHideSoftReports: 10, imageModeration: "enforce",
    keepEndedDays: 7, limits: {},
  });
  assert.equal(normalizeSettings({keepEndedDays: 0}).keepEndedDays, 0);
  assert.equal(normalizeSettings({keepEndedDays: 30}).keepEndedDays, 30);
  assert.equal(normalizeSettings({keepEndedDays: -1}).keepEndedDays, 7);
  assert.equal(normalizeSettings({keepEndedDays: "a week"}).keepEndedDays, 7);
  assert.equal(normalizeSettings({autoHideSoftReports: 0}).autoHideSoftReports, 0);
  assert.equal(normalizeSettings({autoHideSoftReports: 25}).autoHideSoftReports, 25);
  assert.equal(normalizeSettings({autoHideSoftReports: "many"}).autoHideSoftReports, 10);
  const s = normalizeSettings({
    adminUIDs: ["a", 3, ""], notifyEmails: "me@example.com", autoHideReports: 0,
    imageModeration: "log", limits: {postsPerHour: 2},
  });
  assert.deepEqual(s.adminUIDs, ["a"]);
  assert.deepEqual(s.notifyEmails, []);
  assert.equal(s.autoHideReports, 0);
  assert.equal(s.imageModeration, "log");
  assert.deepEqual(s.limits, {postsPerHour: 2});
  assert.equal(normalizeSettings({autoHideReports: -2}).autoHideReports, 3);
  assert.equal(normalizeSettings({imageModeration: "whatever"}).imageModeration, "enforce");
});

test("chatPhotoPath: only a .jpg in the sender's own folder of that conversation", () => {
  const {chatPhotoPath} = require("../lib/images");
  assert.equal(chatPhotoPath("chats/t1/ann/8F2C-0_1.jpg", "t1", "ann"), "chats/t1/ann/8F2C-0_1.jpg");
  for (const bad of [
    "chats/t1/bea/a.jpg", "chats/t2/ann/a.jpg", "posts/ann/F1/a.jpg", "chats/t1/ann/a.png", "chats/t1/ann/a.jpg/x",
    "chats/t1/ann/sub/a.jpg", "chats/t1/ann/../bea/a.jpg", "chats/t1/ann/a b.jpg", "chats/t1/ann/.jpg", "/chats/t1/ann/a.jpg",
    "", null, undefined, 7, ["chats/t1/ann/a.jpg"],
  ]) {
    assert.equal(chatPhotoPath(bad, "t1", "ann"), null, String(bad));
  }
  assert.equal(chatPhotoPath("chats//ann/a.jpg", "", "ann"), null);
  assert.equal(chatPhotoPath("chats/t1//a.jpg", "t1", ""), null);
});

test("checksFor: photos are counted per day, 30 unless settings say otherwise", () => {
  const {checksFor, DEFAULT_LIMITS} = require("../lib/rateLimit");
  assert.equal(DEFAULT_LIMITS.photosPerDay, 30);
  assert.deepEqual(checksFor("photo"), [{key: "photoD", windowMs: 24 * 3600 * 1000, limit: 30}]);
  assert.equal(checksFor("photo", {photosPerDay: 5})[0].limit, 5);
  assert.equal(checksFor("photo", {photosPerDay: -1})[0].limit, 30);
});

test("normalizeAppConfig: no founder and photos on unless config says otherwise", () => {
  const {normalizeAppConfig} = require("../lib/settings");
  assert.deepEqual(normalizeAppConfig(undefined), {founderUID: "", founderNickname: "", founderWelcome: [], chatPhotos: true});
  assert.deepEqual(normalizeAppConfig({founderUID: 7, founderNickname: null, founderWelcome: "hi", chatPhotos: "no"}),
      {founderUID: "", founderNickname: "", founderWelcome: [], chatPhotos: true});
  const c = normalizeAppConfig({
    founderUID: "fay", founderNickname: "first light", chatPhotos: false,
    founderWelcome: ["hi", "", 3, "x".repeat(5000), ...Array(20).fill("more")],
  });
  assert.equal(c.founderUID, "fay");
  assert.equal(c.founderNickname, "first light");
  assert.equal(c.chatPhotos, false);
  assert.equal(c.founderWelcome.length, 10);
  assert.equal(c.founderWelcome[0], "hi");
  assert.equal(c.founderWelcome[1].length, 2000);
});

test("reasonsOf: the list the app writes, or the one-line text of an older report", () => {
  const {reasonsOf} = require("../lib/reasons");
  assert.deepEqual(reasonsOf({reasons: ["Seems under 18", "Something feels off"], reason: "Seems under 18, Something feels off"}),
      ["Seems under 18", "Something feels off"]);
  assert.deepEqual(reasonsOf({reason: "Hate speech"}), ["Hate speech"]);
  assert.deepEqual(reasonsOf({reasons: [], reason: "Hate speech"}), ["Hate speech"]);
  assert.deepEqual(reasonsOf({reasons: [7, "", "Spam, ads or scam"]}), ["Spam, ads or scam"]);
  assert.deepEqual(reasonsOf({reasons: "Spam", reason: 3}), []);
  assert.deepEqual(reasonsOf(undefined), []);
});
