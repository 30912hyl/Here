"use strict";

const test = require("node:test");
const assert = require("node:assert/strict");

const h = require("../lib/handlers");
const {fakeStore, photoUrl} = require("./fakeStore");

const SLUR = Buffer.from("a2lrZQ==", "base64").toString("utf8");
const NOW = 1_800_000_000_000;
const HOUR = 3600 * 1000;

const post = (over = {}) => ({
  title: "Can't sleep", bodyText: "Anyone else up late?", imageURLs: [], authorUID: "ann",
  tags: ["😴"], isPrivate: false, ...over,
});

// ---------------------------------------------------------------- posts

test("post: an ordinary post is left alone", async () => {
  const store = fakeStore();
  assert.equal(await h.onPostCreated(store, "p1", post()), "ok");
  assert.deepEqual(store.s.removedPosts, []);
  assert.deepEqual(store.s.logs, []);
  assert.deepEqual(store.s.safeSearchCalls, []);
});

test("post: malformed documents are skipped, not crashed on", async () => {
  const store = fakeStore();
  assert.equal(await h.onPostCreated(store, "p1", undefined), "skipped");
  assert.equal(await h.onPostCreated(store, "p1", {title: "x"}), "skipped");
});

test("post: the seventh post within an hour is removed", async () => {
  const store = fakeStore();
  for (let i = 0; i < 6; i++) assert.equal(await h.onPostCreated(store, `p${i}`, post()), "ok");
  assert.equal(await h.onPostCreated(store, "p6", post()), "removed:rate");
  assert.deepEqual(store.s.removedPosts, [{postId: "p6", reason: "rate"}]);
  // someone else is unaffected, and so is the same person an hour later
  assert.equal(await h.onPostCreated(store, "q1", post({authorUID: "bea"})), "ok");
  store.s.now += HOUR;
  assert.equal(await h.onPostCreated(store, "p7", post()), "ok");
});

test("post: the per-hour limit can be changed in settings", async () => {
  const store = fakeStore({settings: {limits: {postsPerHour: 1}}});
  assert.equal(await h.onPostCreated(store, "p1", post()), "ok");
  assert.equal(await h.onPostCreated(store, "p2", post()), "removed:rate");
});

test("post: photos must sit in the author's own folder of our bucket", async () => {
  for (const url of [
    "https://evil.example.com/tracker.jpg",
    photoUrl("someone-else"),
    photoUrl("ann", "F1", "a.jpg", "another-bucket"),
  ]) {
    const store = fakeStore();
    assert.equal(await h.onPostCreated(store, "p1", post({imageURLs: [photoUrl("ann"), url]})), "removed:foreign-image", url);
    assert.deepEqual(store.s.removedPosts, [{postId: "p1", reason: "foreign-image"}]);
    assert.deepEqual(store.s.safeSearchCalls, []);
  }
});

test("post: a photo under the older spelling of our bucket is ours, and is checked there", async () => {
  const old = "here-a6817.appspot.com";
  const store = fakeStore({annotations: {"posts/ann/F1/0_a.jpg": {adult: "VERY_LIKELY"}}, files: ["posts/ann/F1/0_a.jpg"]});
  const p = post({imageURLs: [photoUrl("ann", "F1", "0_a.jpg", old)]});
  assert.equal(await h.onPostCreated(store, "p1", p), "removed:image");
  assert.deepEqual(store.s.deletedFrom, [old]);
});

test("post: in log-only mode a foreign image is recorded and the post stays; with checks off it is ignored", async () => {
  const urls = [photoUrl("ann"), "https://evil.example.com/tracker.jpg"];
  const log = fakeStore({settings: {imageModeration: "log"}});
  assert.equal(await h.onPostCreated(log, "p1", post({imageURLs: urls})), "ok");
  assert.deepEqual(log.s.removedPosts, []);
  assert.deepEqual(log.s.logs.map((l) => `${l.action}:${l.reason}`), ["flagged:foreign-image"]);
  // the photo that is ours is still checked
  assert.deepEqual(log.s.safeSearchCalls, ["posts/ann/F1/0_a.jpg"]);

  const off = fakeStore({settings: {imageModeration: "off"}});
  assert.equal(await h.onPostCreated(off, "p1", post({imageURLs: urls})), "ok");
  assert.deepEqual(off.s.removedPosts, []);
  assert.deepEqual(off.s.logs, []);
});

test("post: 'just for me' posts are not moderated, but still cannot point at foreign images", async () => {
  const store = fakeStore({annotations: {"posts/ann/F1/0_a.jpg": {adult: "VERY_LIKELY"}}});
  const priv = post({isPrivate: true, bodyText: SLUR, imageURLs: [photoUrl("ann")]});
  assert.equal(await h.onPostCreated(store, "p1", priv), "ok:private");
  assert.deepEqual(store.s.removedPosts, []);
  assert.deepEqual(store.s.safeSearchCalls, []);
  assert.equal(await h.onPostCreated(store, "p2", post({isPrivate: true, imageURLs: ["https://evil.example.com/x.jpg"]})), "removed:foreign-image");
});

test("post: a slur in the title, body or tags removes it", async () => {
  for (const over of [{title: SLUR}, {bodyText: `you ${SLUR}!`}, {tags: ["😴", SLUR]}]) {
    const store = fakeStore();
    assert.equal(await h.onPostCreated(store, "p1", post(over)), "removed:text");
    assert.equal(store.s.logs[0].reason, "text:slur");
  }
});

test("post: contact details are logged, not removed", async () => {
  const store = fakeStore();
  assert.equal(await h.onPostCreated(store, "p1", post({bodyText: "text me 415 555 0123"})), "ok");
  assert.deepEqual(store.s.removedPosts, []);
  assert.equal(store.s.logs[0].reason, "text:contact");
});

test("post: an explicit photo takes the post down and deletes that photo only", async () => {
  const store = fakeStore({
    annotations: {"posts/ann/F1/1_b.jpg": {adult: "LIKELY"}},
    files: ["posts/ann/F1/0_a.jpg", "posts/ann/F1/1_b.jpg"],
  });
  const p = post({imageURLs: [photoUrl("ann", "F1", "0_a.jpg"), photoUrl("ann", "F1", "1_b.jpg")]});
  assert.equal(await h.onPostCreated(store, "p1", p), "removed:image");
  assert.deepEqual(store.s.removedPosts, [{postId: "p1", reason: "image"}]);
  assert.deepEqual(store.s.deletedFiles, ["posts/ann/F1/1_b.jpg"]);
  assert.deepEqual([...store.s.files], ["posts/ann/F1/0_a.jpg"]);
  assert.equal(store.s.adminNotes.length, 1);
  assert.deepEqual(store.s.safeSearchCalls, ["posts/ann/F1/0_a.jpg", "posts/ann/F1/1_b.jpg"]);
});

test("post: in log-only mode an explicit photo is reported but stays", async () => {
  const store = fakeStore({
    settings: {imageModeration: "log"},
    annotations: {"posts/ann/F1/0_a.jpg": {adult: "VERY_LIKELY"}},
  });
  assert.equal(await h.onPostCreated(store, "p1", post({imageURLs: [photoUrl("ann")]})), "flagged:image");
  assert.deepEqual(store.s.removedPosts, []);
  assert.deepEqual(store.s.deletedFiles, []);
  assert.equal(store.s.adminNotes.length, 1);
});

test("post: with photo checks off, Vision is never called", async () => {
  const store = fakeStore({settings: {imageModeration: "off"}, annotations: {"posts/ann/F1/0_a.jpg": {adult: "VERY_LIKELY"}}});
  assert.equal(await h.onPostCreated(store, "p1", post({imageURLs: [photoUrl("ann")]})), "ok");
  assert.deepEqual(store.s.safeSearchCalls, []);
});

test("post: a borderline photo stays up and a moderator is told", async () => {
  const store = fakeStore({annotations: {"posts/ann/F1/0_a.jpg": {racy: "VERY_LIKELY", adult: "POSSIBLE"}}});
  assert.equal(await h.onPostCreated(store, "p1", post({imageURLs: [photoUrl("ann")]})), "review:image");
  assert.deepEqual(store.s.removedPosts, []);
  assert.equal(store.s.adminNotes.length, 1);
});

test("post: if Vision cannot answer, the photo is left alone", async () => {
  const store = fakeStore({annotations: {"posts/ann/F1/0_a.jpg": null}});
  assert.equal(await h.onPostCreated(store, "p1", post({imageURLs: [photoUrl("ann")]})), "ok");
  assert.deepEqual(store.s.removedPosts, []);
  assert.deepEqual(store.s.adminNotes, []);
});

test("post: a file Vision cannot read stays up, and a moderator is told", async () => {
  const store = fakeStore({annotations: {"posts/ann/F1/0_a.jpg": {unreadable: true}}});
  assert.equal(await h.onPostCreated(store, "p1", post({imageURLs: [photoUrl("ann")]})), "review:unreadable");
  assert.deepEqual(store.s.removedPosts, []);
  assert.deepEqual(store.s.deletedFiles, []);
  assert.equal(store.s.adminNotes.length, 1);
  assert.equal(store.s.logs.at(-1).reason, "image:unreadable");
});

test("post: an explicit photo still wins over an unreadable one in the same post", async () => {
  const store = fakeStore({annotations: {
    "posts/ann/F1/0_a.jpg": {unreadable: true},
    "posts/ann/F1/1_b.jpg": {adult: "VERY_LIKELY"},
  }});
  const p = post({imageURLs: [photoUrl("ann", "F1", "0_a.jpg"), photoUrl("ann", "F1", "1_b.jpg")]});
  assert.equal(await h.onPostCreated(store, "p1", p), "removed:image");
  assert.deepEqual(store.s.deletedFiles, ["posts/ann/F1/1_b.jpg"]);
});

// ---------------------------------------------------------------- messages

const thread = (over = {}) => ({participants: ["ann", "bea"], nickname: "quiet moon", lastRead: {}, ...over});
const msg = (over = {}) => ({text: "hey, your post really resonated with me", senderUID: "bea", ...over});

test("message: delivered with the thread's nickname and a badge", async () => {
  const store = fakeStore({threads: {t1: thread()}, users: {ann: {fcmToken: "tok", unreadTotal: 2}}});
  assert.equal(await h.onMessageCreated(store, "t1", "m1", msg()), "push:ok");
  assert.deepEqual(store.s.pushes, [{
    token: "tok", title: "quiet moon", body: "hey, your post really resonated with me", badge: 3, data: {threadId: "t1"},
  }]);
  assert.equal(store.s.users.ann.unreadTotal, 3);
});

test("message: the badge does not grow when the conversation was already unread", async () => {
  const store = fakeStore({threads: {t1: thread()}, users: {ann: {fcmToken: "tok", unreadTotal: 2}}, unread: 2});
  await h.onMessageCreated(store, "t1", "m1", msg());
  assert.equal(store.s.pushes[0].badge, 2);
  assert.equal(store.s.users.ann.unreadTotal, 2);
});

test("message: system messages and malformed ones are skipped", async () => {
  const store = fakeStore({threads: {t1: thread()}, users: {ann: {fcmToken: "tok"}}});
  assert.equal(await h.onMessageCreated(store, "t1", "m1", msg({senderUID: "system"})), "skipped");
  assert.equal(await h.onMessageCreated(store, "t1", "m1", undefined), "skipped");
  assert.equal(await h.onMessageCreated(store, "t1", "m1", {text: "x"}), "skipped");
  assert.deepEqual(store.s.pushes, []);
  assert.deepEqual(store.s.counters, {});
});

test("message: harassment, sexual requests and slurs are deleted and never pushed", async () => {
  for (const [text, why] of [["kill yourself!", "harassment"], ["send nudes", "sexual"], [SLUR, "slur"]]) {
    const store = fakeStore({threads: {t1: thread()}, users: {ann: {fcmToken: "tok"}}});
    assert.equal(await h.onMessageCreated(store, "t1", "m1", msg({text})), `removed:${why}`);
    assert.deepEqual(store.s.deletedMessages, ["t1/m1"]);
    assert.deepEqual(store.s.pushes, []);
    assert.equal(store.s.users.ann.unreadTotal, undefined);
  }
});

test("message: contact details pass (the app already asked the sender to confirm)", async () => {
  const store = fakeStore({threads: {t1: thread()}, users: {ann: {fcmToken: "tok"}}});
  assert.equal(await h.onMessageCreated(store, "t1", "m1", msg({text: "my insta: janedoe"})), "push:ok");
  assert.deepEqual(store.s.deletedMessages, []);
});

test("message: nothing reaches someone who blocked the sender", async () => {
  const store = fakeStore({threads: {t1: thread()}, users: {ann: {fcmToken: "tok", blocked: ["bea"], unreadTotal: 1}}});
  assert.equal(await h.onMessageCreated(store, "t1", "m1", msg()), "ok:blocked");
  assert.deepEqual(store.s.pushes, []);
  assert.equal(store.s.users.ann.unreadTotal, 1);
});

test("message: a deleted account is not written to", async () => {
  const store = fakeStore({threads: {t1: thread()}});
  assert.equal(await h.onMessageCreated(store, "t1", "m1", msg()), "ok:no-push");
  assert.equal(store.s.users.ann, undefined);
});

test("message: no push for an ended conversation or a missing thread", async () => {
  const store = fakeStore({threads: {t1: thread({isManuallyFrozen: true})}, users: {ann: {fcmToken: "tok"}}});
  assert.equal(await h.onMessageCreated(store, "t1", "m1", msg()), "ok:no-push");
  assert.equal(await h.onMessageCreated(store, "nope", "m1", msg()), "ok:no-push");
  assert.deepEqual(store.s.pushes, []);
});

test("message: without a token the badge still updates", async () => {
  const store = fakeStore({threads: {t1: thread()}, users: {ann: {}}});
  assert.equal(await h.onMessageCreated(store, "t1", "m1", msg()), "ok:no-token");
  assert.equal(store.s.users.ann.unreadTotal, 1);
});

test("message: a dead token is cleared", async () => {
  const store = fakeStore({threads: {t1: thread()}, users: {ann: {fcmToken: "old"}}, pushResult: "gone"});
  assert.equal(await h.onMessageCreated(store, "t1", "m1", msg()), "push:gone");
  assert.deepEqual(store.s.clearedTokens, ["ann"]);
});

test("message: a long message is shortened for the notification", async () => {
  const store = fakeStore({threads: {t1: thread()}, users: {ann: {fcmToken: "tok"}}});
  const long = "I read your post three times. ".repeat(400); // 12,000 characters
  await h.onMessageCreated(store, "t1", "m1", msg({text: long}));
  const body = store.s.pushes[0].body;
  assert.ok(body.length <= 181, `got ${body.length}`);
  assert.ok(body.endsWith("…"));
  assert.ok(long.startsWith(body.slice(0, -1)));
});

test("preview: counts what a person sees as one character, and stays small", () => {
  assert.equal(h.preview("short"), "short");
  assert.equal(h.preview(""), "");
  assert.equal(h.preview(undefined), "");
  assert.equal(h.preview("x".repeat(180)), "x".repeat(180));
  assert.equal(h.preview("x".repeat(181)), `${"x".repeat(180)}…`);
  // a family emoji is 7 code points joined together: never cut inside one
  const family = "👨‍👩‍👧‍👦";
  assert.equal(h.preview(family.repeat(5), 3), `${family.repeat(3)}…`);
  // text built to be huge per character still fits in a push
  const stacked = `a${"\u0301".repeat(200)}`.repeat(100);
  assert.ok(Buffer.byteLength(h.preview(stacked), "utf8") <= 1024 + 3);
});

test("message: an empty text falls back to a neutral notification", async () => {
  const store = fakeStore({threads: {t1: thread({nickname: ""})}, users: {ann: {fcmToken: "tok"}}});
  await h.onMessageCreated(store, "t1", "m1", msg({text: ""}));
  assert.equal(store.s.pushes[0].title, "New message");
  assert.equal(store.s.pushes[0].body, "sent you a message");
});

test("message: the 41st message within a minute is deleted", async () => {
  const store = fakeStore({threads: {t1: thread()}, users: {ann: {fcmToken: "tok"}}});
  for (let i = 0; i < 40; i++) assert.equal(await h.onMessageCreated(store, "t1", `m${i}`, msg()), "push:ok");
  assert.equal(await h.onMessageCreated(store, "t1", "m40", msg()), "removed:rate");
  assert.deepEqual(store.s.deletedMessages, ["t1/m40"]);
  assert.equal(store.s.pushes.length, 40);
});

// ---------------------------------------------------------------- threads

test("thread: the limit counts against whoever opened it, not the post's author", async () => {
  const store = fakeStore({posts: {p1: {authorUID: "ann"}}, settings: {limits: {threadsPerHour: 2}}});
  const t = {participants: ["ann", "bea"], postId: "p1"};
  assert.equal(await h.onThreadCreated(store, "t1", t), "ok");
  assert.equal(await h.onThreadCreated(store, "t2", t), "ok");
  assert.equal(await h.onThreadCreated(store, "t3", t), "ended:rate");
  assert.deepEqual(store.s.frozen, ["t3"]);
  assert.equal(store.s.counters.bea.threadH.n, 3);
  assert.equal(store.s.counters.ann, undefined);
});

test("thread: without a readable post the first participant is taken as the opener", async () => {
  const store = fakeStore();
  assert.equal(await h.onThreadCreated(store, "t1", {participants: ["bea", "ann"], postId: "gone"}), "ok");
  assert.equal(store.s.counters.bea.threadH.n, 1);
  assert.equal(await h.onThreadCreated(store, "t1", {participants: ["bea"]}), "skipped");
  assert.equal(await h.onThreadCreated(store, "t1", undefined), "skipped");
});

// ---------------------------------------------------------------- reports

const livePost = (over = {}) => ({authorUID: "ann", expiresAtMs: NOW + HOUR, ...over});
const report = (reporterUID, over = {}) => ({type: "post", postId: "p1", reporterUID, reason: "Harassment, threats or hate", ...over});

test("report: moderators hear about every report", async () => {
  const store = fakeStore({posts: {p1: livePost()}, reports: {r1: report("bea")}});
  assert.equal(await h.onReportCreated(store, "r1", report("bea"), NOW), "notified");
  assert.equal(store.s.adminNotes.length, 1);
  assert.deepEqual(store.s.adminNotes[0].data, {reportId: "r1"});
  assert.deepEqual(store.s.removedPosts, []);
});

test("report: the third different reporter takes the post out of the feed", async () => {
  const store = fakeStore({posts: {p1: livePost()}, reports: {r1: report("bea"), r2: report("cat"), r3: report("dee")}});
  assert.equal(await h.onReportCreated(store, "r3", report("dee"), NOW), "removed:reports");
  assert.deepEqual(store.s.removedPosts, [{postId: "p1", reason: "reports"}]);
  // a fourth report does not remove it again
  store.s.reports.r4 = report("eve");
  assert.equal(await h.onReportCreated(store, "r4", report("eve"), NOW), "notified");
  assert.equal(store.s.removedPosts.length, 1);
});

test("report: accounts without a verified phone number do not count toward hiding", async () => {
  const reports = {r1: report("bea"), r2: report("cat"), r3: report("dee")};
  const store = fakeStore({posts: {p1: livePost()}, reports, unverified: ["cat", "dee"]});
  assert.equal(await h.onReportCreated(store, "r3", report("dee"), NOW), "notified");
  assert.deepEqual(store.s.removedPosts, []);
  // moderators still hear about it
  assert.equal(store.s.adminNotes.length, 1);
  // a third verified reporter tips it over
  store.s.reports.r4 = report("eve");
  store.s.reports.r5 = report("fay");
  assert.equal(await h.onReportCreated(store, "r5", report("fay"), NOW), "removed:reports");
  assert.equal(store.s.logs.at(-1).reason, "reports:3");
});

test("report: the same person reporting three times is one reporter", async () => {
  const store = fakeStore({posts: {p1: livePost()}, reports: {r1: report("bea"), r2: report("bea"), r3: report("bea")}});
  assert.equal(await h.onReportCreated(store, "r3", report("bea"), NOW), "notified");
  assert.deepEqual(store.s.removedPosts, []);
});

test("report: the author's own report does not count toward hiding", async () => {
  const store = fakeStore({posts: {p1: livePost()}, reports: {r1: report("bea"), r2: report("cat"), r3: report("ann")}});
  assert.equal(await h.onReportCreated(store, "r3", report("ann"), NOW), "notified");
  assert.deepEqual(store.s.removedPosts, []);
});

test("report: expired or missing posts are not touched", async () => {
  const reports = {r1: report("bea"), r2: report("cat"), r3: report("dee")};
  const expired = fakeStore({posts: {p1: livePost({expiresAtMs: NOW - 1})}, reports});
  assert.equal(await h.onReportCreated(expired, "r3", report("dee"), NOW), "notified");
  const missing = fakeStore({reports});
  assert.equal(await h.onReportCreated(missing, "r3", report("dee"), NOW), "notified");
  assert.deepEqual(expired.s.removedPosts, []);
  assert.deepEqual(missing.s.removedPosts, []);
});

test("report: auto-hide can be turned off or its threshold changed", async () => {
  const reports = {r1: report("bea"), r2: report("cat"), r3: report("dee")};
  const off = fakeStore({posts: {p1: livePost()}, reports, settings: {autoHideReports: 0}});
  assert.equal(await h.onReportCreated(off, "r3", report("dee"), NOW), "notified");
  const two = fakeStore({posts: {p1: livePost()}, reports: {r1: report("bea"), r2: report("cat")}, settings: {autoHideReports: 2}});
  assert.equal(await h.onReportCreated(two, "r2", report("cat"), NOW), "removed:reports");
});

test("report: conversation reports only notify", async () => {
  const store = fakeStore();
  const r = {type: "chat", threadId: "t1", reporterUID: "bea", reason: "Spam or scam"};
  assert.equal(await h.onReportCreated(store, "r1", r, NOW), "notified");
  assert.match(store.s.adminNotes[0].body, /conversation/);
});

test("report: someone filing reports in bulk is ignored after the limit", async () => {
  const store = fakeStore({settings: {limits: {reportsPerHour: 2}}, posts: {p1: livePost()}});
  assert.equal(await h.onReportCreated(store, "r1", report("bea"), NOW), "notified");
  assert.equal(await h.onReportCreated(store, "r2", report("bea"), NOW), "notified");
  assert.equal(await h.onReportCreated(store, "r3", report("bea"), NOW), "ignored:rate");
  assert.deepEqual(store.s.reportPatches, {r3: {ignored: "rate"}});
  assert.equal(store.s.adminNotes.length, 2);
});

test("report: ignored reports do not count toward hiding", async () => {
  const store = fakeStore({
    posts: {p1: livePost()},
    reports: {r1: report("bea"), r2: report("cat", {ignored: "rate"}), r3: report("dee")},
  });
  assert.equal(await h.onReportCreated(store, "r3", report("dee"), NOW), "notified");
  assert.deepEqual(store.s.removedPosts, []);
});

// ---------------------------------------------------------------- bans

test("ban: posts come down, conversations end, the device stops getting pushes", async () => {
  const store = fakeStore({
    phones: {"+14155550123": "mal"},
    posts: {
      a: {authorUID: "mal", expiresAtMs: NOW + HOUR},
      b: {authorUID: "mal", expiresAtMs: NOW - HOUR},
      c: {authorUID: "ann", expiresAtMs: NOW + HOUR},
    },
    threads: {
      t1: {participants: ["mal", "ann"]},
      t2: {participants: ["mal", "bea"], isManuallyFrozen: true},
      t3: {participants: ["ann", "bea"]},
    },
  });
  assert.equal(await h.onBanCreated(store, "+14155550123"), "applied:1:1");
  assert.deepEqual(store.s.removedPosts, [{postId: "a", reason: "ban"}]);
  assert.deepEqual(store.s.frozen, ["t1"]);
  assert.deepEqual(store.s.clearedTokens, ["mal"]);
  assert.deepEqual(store.s.clearedPresence, ["mal"]);
  // the full number is never written to the log
  assert.equal(JSON.stringify(store.s.logs).includes("4155550123"), false);
  assert.equal(store.s.logs[0].phoneTail, "0123");
});

test("ban: a number with no account is only noted", async () => {
  const store = fakeStore();
  assert.equal(await h.onBanCreated(store, "+14155550123"), "no-account");
  assert.deepEqual(store.s.removedPosts, []);
});

// ---------------------------------------------------------------- account deletion

test("account deletion: whatever the phone left behind is removed", async () => {
  const store = fakeStore({
    posts: {a: {authorUID: "ann"}, b: {authorUID: "ann"}, c: {authorUID: "bea"}},
    files: ["posts/ann/F1/0_a.jpg", "posts/bea/F9/0_z.jpg"],
    threads: {t1: {participants: ["ann", "bea"]}, t2: {participants: ["bea", "cat"]}},
  });
  assert.equal(await h.onUserDocDeleted(store, "ann"), "cleaned:2:1:1");
  assert.deepEqual(Object.keys(store.s.posts), ["c"]);
  assert.deepEqual([...store.s.files], ["posts/bea/F9/0_z.jpg"]);
  assert.deepEqual(store.s.frozen, ["t1"]);
  assert.deepEqual(store.s.clearedPresence, ["ann"]);
  // the log keeps counts, not who it was
  assert.equal(JSON.stringify(store.s.logs).includes("ann"), false);
});

test("account deletion: nothing left means nothing logged", async () => {
  const store = fakeStore();
  assert.equal(await h.onUserDocDeleted(store, "ann"), "cleaned:0:0:0");
  assert.deepEqual(store.s.logs, []);
  assert.equal(await h.onUserDocDeleted(store, ""), "skipped");
});

// ---------------------------------------------------------------- time's up

const MIN = 60 * 1000;
/** A conversation whose 48 hours ran out `agoMs` before NOW. */
const ended = (agoMs, over = {}) => ({
  participants: ["ann", "bea"], nickname: "quiet moon", expiresAtMs: NOW - agoMs,
  isManuallyFrozen: false, hasExtendedOnce: false, continueChoices: {ann: "undecided", bea: "undecided"}, ...over,
});
const both = {ann: {fcmToken: "tok-ann"}, bea: {fcmToken: "tok-bea"}};

test("time's up: both people are told once, with the conversation's name and no badge", async () => {
  const store = fakeStore({now: NOW, threads: {t1: ended(2 * MIN)}, users: both});
  assert.equal(await h.onTimeUpSweep(store, NOW), "swept:1:2:0");
  const expected = {
    title: "quiet moon", body: "Time's up. Continue this conversation for another 48 hours?",
    data: {threadId: "t1", kind: "timeUp"},
  };
  assert.deepEqual(store.s.pushes, [{token: "tok-ann", ...expected}, {token: "tok-bea", ...expected}]);
  assert.equal("badge" in store.s.pushes[0], false);
  // the next runs find it again and stay quiet
  assert.equal(await h.onTimeUpSweep(store, NOW + 5 * MIN), "swept:1:0:0");
  assert.equal(await h.onTimeUpSweep(store, NOW + 10 * MIN), "swept:1:0:0");
  assert.equal(store.s.pushes.length, 2);
  assert.deepEqual(store.s.claimed, ["t1"]);
});

test("time's up: the wording comes from one place", () => {
  assert.deepEqual(h.TIME_UP_PUSH, {title: "Time's up", body: "Continue this conversation for another 48 hours?"});
});

test("time's up: only conversations that ran out in the last half hour are looked at", async () => {
  const store = fakeStore({
    now: NOW,
    threads: {
      running: ended(-HOUR), // an hour still to go
      justNow: ended(0),
      edge: ended(30 * MIN - 1),
      old: ended(30 * MIN),
      yesterday: ended(23 * HOUR),
    },
    users: both,
  });
  assert.equal(await h.onTimeUpSweep(store, NOW), "swept:2:4:0");
  assert.deepEqual(store.s.sweeps, [[NOW - h.TIME_UP_LOOKBACK_MS, NOW]]);
  assert.deepEqual(store.s.claimed.sort(), ["edge", "justNow"]);
});

test("time's up: the look-back covers several missed runs", () => {
  // index.js schedules a run every 5 minutes
  assert.ok(h.TIME_UP_LOOKBACK_MS >= 3 * 5 * MIN);
  assert.ok(h.TIME_UP_LOOKBACK_MS <= 2 * HOUR);
});

test("time's up: nothing for a conversation that was ended, or that already had its extension", async () => {
  const store = fakeStore({
    now: NOW,
    threads: {
      endedByHand: ended(MIN, {isManuallyFrozen: true}),
      secondRound: ended(MIN, {hasExtendedOnce: true}),
    },
    users: both,
  });
  assert.equal(await h.onTimeUpSweep(store, NOW), "swept:2:0:0");
  assert.deepEqual(store.s.pushes, []);
  assert.deepEqual(store.s.claimed, []);
});

test("time's up: nobody is told when one has blocked the other", async () => {
  for (const users of [
    {ann: {fcmToken: "tok-ann", blocked: ["bea"]}, bea: {fcmToken: "tok-bea"}},
    {ann: {fcmToken: "tok-ann"}, bea: {fcmToken: "tok-bea", blocked: ["ann"]}},
  ]) {
    const store = fakeStore({now: NOW, threads: {t1: ended(MIN)}, users});
    assert.equal(await h.onTimeUpSweep(store, NOW), "swept:1:0:0");
    assert.deepEqual(store.s.pushes, []);
  }
});

test("time's up: someone who already answered is left alone", async () => {
  const store = fakeStore({
    now: NOW,
    threads: {t1: ended(MIN, {continueChoices: {ann: "yes", bea: "undecided"}})},
    users: both,
  });
  assert.equal(await h.onTimeUpSweep(store, NOW), "swept:1:1:0");
  assert.deepEqual(store.s.pushes.map((p) => p.token), ["tok-bea"]);
});

test("time's up: someone without notifications is skipped, the other is still told", async () => {
  // bea has no user document at all, cat's has no token
  const store = fakeStore({
    now: NOW,
    threads: {t1: ended(MIN), t2: ended(MIN, {participants: ["ann", "cat"]})},
    users: {ann: {fcmToken: "tok-ann"}, cat: {}},
  });
  assert.equal(await h.onTimeUpSweep(store, NOW), "swept:2:2:0");
  assert.deepEqual(store.s.pushes.map((p) => p.token), ["tok-ann", "tok-ann"]);
  // and no user document is created for the one who has none
  assert.equal(store.s.users.bea, undefined);
});

test("time's up: a dead token is cleared, and only real deliveries are counted", async () => {
  const store = fakeStore({
    now: NOW, threads: {t1: ended(MIN)}, users: both, pushResults: {"tok-ann": "gone", "tok-bea": "error"},
  });
  assert.equal(await h.onTimeUpSweep(store, NOW), "swept:1:0:0");
  assert.deepEqual(store.s.clearedTokens, ["ann"]);
});

test("time's up: a conversation without a name still gets a sensible notification", async () => {
  const store = fakeStore({now: NOW, threads: {t1: ended(MIN, {nickname: undefined})}, users: both});
  await h.onTimeUpSweep(store, NOW);
  assert.equal(store.s.pushes[0].title, "Time's up");
  assert.equal(store.s.pushes[0].body, "Continue this conversation for another 48 hours?");
});

test("time's up: malformed conversations are skipped, and one failure does not stop the rest", async () => {
  const store = fakeStore({
    now: NOW,
    threads: {
      a: ended(MIN, {participants: ["ann"]}),
      b: ended(MIN, {participants: ["ann", "ann"]}),
      c: ended(MIN, {participants: undefined}),
      d: ended(MIN),
      e: ended(MIN, {participants: ["ann", "cat"]}),
    },
    users: {...both, cat: {fcmToken: "tok-cat"}},
    failClaim: ["d"],
  });
  assert.equal(await h.onTimeUpSweep(store, NOW), "swept:5:2:1");
  assert.deepEqual(store.s.pushes.map((p) => p.token), ["tok-ann", "tok-cat"]);
  // the one that failed was not marked, so the next run tries it again
  store.s.failClaim.clear();
  assert.equal(await h.onTimeUpSweep(store, NOW + 5 * MIN), "swept:5:2:0");
});

test("time's up: with nothing due, nothing happens", async () => {
  const store = fakeStore({now: NOW, users: both});
  assert.equal(await h.onTimeUpSweep(store, NOW), "swept:0:0:0");
  assert.deepEqual(store.s.pushes, []);
});

// ---------------------------------------------------------------- photos in conversations

const PHOTO = "chats/t1/bea/p1.jpg";
const photoMsg = (over = {}) => ({text: "", senderUID: "bea", imagePath: PHOTO, ...over});
const withPhoto = (over = {}) => fakeStore({
  threads: {t1: thread()}, users: {ann: {fcmToken: "tok", unreadTotal: 0}}, files: [PHOTO], ...over,
});

test("photo: checked, marked as checked, and announced in a notification of its own", async () => {
  const store = withPhoto();
  assert.equal(await h.onMessageCreated(store, "t1", "m1", photoMsg()), "push:ok");
  assert.deepEqual(store.s.safeSearchCalls, [PHOTO]);
  assert.deepEqual(store.s.checkedPhotos, ["t1/m1"]);
  assert.equal(store.s.threads.t1.hasPhotos, true);
  assert.equal(store.s.pushes[0].body, h.PHOTO_PUSH_BODY);
  assert.equal(h.PHOTO_PUSH_BODY, "sent a photo");
  assert.deepEqual(store.s.deletedMessages, []);
  assert.equal(store.s.files.has(PHOTO), true);
});

test("photo: with words, the notification says the words", async () => {
  const store = withPhoto();
  await h.onMessageCreated(store, "t1", "m1", photoMsg({text: "look at her"}));
  assert.equal(store.s.pushes[0].body, "look at her");
});

test("photo: an explicit one loses its file but keeps its message, marked for both phones; nothing is pushed", async () => {
  const store = withPhoto({annotations: {[PHOTO]: {adult: "VERY_LIKELY"}}});
  assert.equal(await h.onMessageCreated(store, "t1", "m1", photoMsg()), "rejected:image");
  assert.deepEqual(store.s.deletedMessages, []);
  assert.deepEqual(store.s.rejectedPhotos, ["t1/m1"]);
  assert.deepEqual(store.s.deletedFiles, [PHOTO]);
  assert.deepEqual(store.s.checkedPhotos, []);
  assert.deepEqual(store.s.pushes, []);
  assert.equal(store.s.logs[0].action, "photo-rejected");
  assert.equal(store.s.logs[0].reason, "image");
  assert.deepEqual(store.s.adminNotes.map((n) => n.title), ["Chat photo removed"]);
  assert.deepEqual(store.s.adminNotes[0].data, {threadId: "t1"});
});

test("photo: a file the check cannot read is treated the same way (in a post it would stay up for a moderator)", async () => {
  const store = withPhoto({annotations: {[PHOTO]: {unreadable: true}}});
  assert.equal(await h.onMessageCreated(store, "t1", "m1", photoMsg()), "rejected:image:unreadable");
  assert.deepEqual(store.s.deletedMessages, []);
  assert.deepEqual(store.s.rejectedPhotos, ["t1/m1"]);
  assert.deepEqual(store.s.deletedFiles, [PHOTO]);
  assert.deepEqual(store.s.pushes, []);
});

test("photo: a borderline one is delivered and a moderator is told", async () => {
  const store = withPhoto({annotations: {[PHOTO]: {racy: "VERY_LIKELY"}}});
  assert.equal(await h.onMessageCreated(store, "t1", "m1", photoMsg()), "push:ok");
  assert.deepEqual(store.s.checkedPhotos, ["t1/m1"]);
  assert.equal(store.s.logs[0].reason, "image:review");
  assert.deepEqual(store.s.adminNotes.map((n) => n.title), ["Chat photo needs a look"]);
});

test("photo: in log-only mode an explicit one is reported but delivered; with checks off nothing is asked", async () => {
  const log = withPhoto({annotations: {[PHOTO]: {adult: "VERY_LIKELY"}}, settings: {imageModeration: "log"}});
  assert.equal(await h.onMessageCreated(log, "t1", "m1", photoMsg()), "push:ok");
  assert.deepEqual(log.s.deletedMessages, []);
  assert.deepEqual(log.s.checkedPhotos, ["t1/m1"]);
  assert.equal(log.s.logs[0].action, "flagged");
  assert.deepEqual(log.s.adminNotes.map((n) => n.title), ["Chat photo would be removed"]);

  const off = withPhoto({annotations: {[PHOTO]: {adult: "VERY_LIKELY"}}, settings: {imageModeration: "off"}});
  assert.equal(await h.onMessageCreated(off, "t1", "m1", photoMsg()), "push:ok");
  assert.deepEqual(off.s.safeSearchCalls, []);
  assert.deepEqual(off.s.checkedPhotos, ["t1/m1"]);
});

test("photo: when the check cannot be asked at all, the photo is delivered", async () => {
  const store = withPhoto({annotations: {[PHOTO]: null}});
  assert.equal(await h.onMessageCreated(store, "t1", "m1", photoMsg()), "push:ok");
  assert.deepEqual(store.s.checkedPhotos, ["t1/m1"]);
});

test("photo: a path that is not hers for this conversation removes the message, and no file is touched", async () => {
  for (const imagePath of ["chats/t1/ann/p1.jpg", "chats/t2/bea/p1.jpg", "posts/bea/F1/0_a.jpg", "chats/t1/bea/p1.png", 7, ""]) {
    const store = withPhoto();
    assert.equal(await h.onMessageCreated(store, "t1", "m1", photoMsg({imagePath})), "removed:foreign-image");
    assert.deepEqual(store.s.deletedMessages, ["t1/m1"]);
    assert.deepEqual(store.s.deletedFiles, []);
    assert.deepEqual(store.s.safeSearchCalls, []);
    assert.deepEqual(store.s.pushes, []);
  }
});

test("photo: switched off in config, a photo is removed; an ordinary message still goes through", async () => {
  const store = withPhoto({config: {chatPhotos: false}});
  assert.equal(await h.onMessageCreated(store, "t1", "m1", photoMsg()), "removed:photos-off");
  assert.deepEqual(store.s.deletedFiles, [PHOTO]);
  assert.equal(await h.onMessageCreated(store, "t1", "m2", msg()), "push:ok");
});

test("photo: the 31st photo in a day is removed; the number can be changed in settings", async () => {
  const store = withPhoto();
  for (let i = 0; i < 30; i++) {
    store.s.now += 2 * 60 * 1000; // spread out, so the per-minute message limit is not what stops them
    assert.equal(await h.onMessageCreated(store, "t1", `m${i}`, photoMsg()), "push:ok");
  }
  store.s.now += 2 * 60 * 1000;
  assert.equal(await h.onMessageCreated(store, "t1", "m30", photoMsg()), "removed:rate");
  assert.deepEqual(store.s.deletedMessages, ["t1/m30"]);
  assert.equal(store.s.logs.at(-1).reason, "rate:photoD");
  // text is not affected, and neither is the other person
  assert.equal(await h.onMessageCreated(store, "t1", "m31", msg()), "push:ok");

  const strict = withPhoto({settings: {limits: {photosPerDay: 1}}});
  assert.equal(await h.onMessageCreated(strict, "t1", "a", photoMsg()), "push:ok");
  assert.equal(await h.onMessageCreated(strict, "t1", "b", photoMsg()), "removed:rate");
});

test("photo: a message removed for its words or for flooding takes its photo with it", async () => {
  const words = withPhoto();
  assert.equal(await h.onMessageCreated(words, "t1", "m1", photoMsg({text: `you ${SLUR}`})), "removed:slur");
  assert.deepEqual(words.s.deletedFiles, [PHOTO]);
  assert.deepEqual(words.s.safeSearchCalls, []);

  const flood = withPhoto();
  for (let i = 0; i < 40; i++) await h.onMessageCreated(flood, "t1", `m${i}`, msg());
  assert.equal(await h.onMessageCreated(flood, "t1", "m40", photoMsg()), "removed:rate");
  assert.deepEqual(flood.s.deletedFiles, [PHOTO]);
});

// ---------------------------------------------------------------- the conversation with the founder

const FOUNDER = {founderUID: "fay", founderNickname: "first light", founderWelcome: ["hi, i'm the founder of here", "do you want to see a picture of my dog?"]};
const founderThread = (over = {}) => ({kind: "founder", participants: ["ann", "fay"], nickname: "amber tide", createdAt: NOW, lastRead: {}, ...over});

test("founder: her welcome is written into a new conversation, dated just before it began", async () => {
  const store = fakeStore({config: FOUNDER});
  assert.equal(await h.onThreadCreated(store, "founder_ann", founderThread()), "ok:welcome");
  assert.deepEqual(store.s.welcomes, [{threadId: "founder_ann", founderUID: "fay", lines: FOUNDER.founderWelcome, beforeMs: NOW}]);
  // it counts as a conversation opened by the other person, not by the founder
  assert.equal(store.s.counters.ann.threadH.n, 1);
  assert.equal(store.s.counters.fay, undefined);
});

test("founder: the conversation's own timestamp is used whatever form it arrives in", async () => {
  const store = fakeStore({config: FOUNDER});
  await h.onThreadCreated(store, "founder_ann", founderThread({createdAt: {toMillis: () => 123456}}));
  assert.equal(store.s.welcomes[0].beforeMs, 123456);
});

test("founder: without a welcome in config the conversation simply starts", async () => {
  const store = fakeStore({config: {founderUID: "fay"}});
  assert.equal(await h.onThreadCreated(store, "founder_ann", founderThread()), "ok");
  assert.deepEqual(store.s.welcomes, []);
});

test("founder: a conversation that only claims to be with her is ended", async () => {
  const cases = [
    [{config: FOUNDER}, "founder_ann", founderThread({participants: ["ann", "bea"]})], // not the founder
    [{config: FOUNDER}, "t9", founderThread()], // not the fixed id
    [{config: FOUNDER}, "founder_bea", founderThread()], // someone else's id
    [{}, "founder_ann", founderThread()], // no founder configured
  ];
  for (const [init, id, t] of cases) {
    const store = fakeStore(init);
    assert.equal(await h.onThreadCreated(store, id, t), "ended:not-founder");
    assert.deepEqual(store.s.frozen, [id]);
    assert.deepEqual(store.s.welcomes, []);
  }
});

test("founder: the hourly limit on new conversations applies, and then there is no welcome", async () => {
  const store = fakeStore({config: FOUNDER, settings: {limits: {threadsPerHour: 1}}, posts: {p1: {authorUID: "bea", expiresAtMs: NOW + HOUR}}});
  assert.equal(await h.onThreadCreated(store, "t1", {participants: ["ann", "bea"], postId: "p1"}), "ok");
  assert.equal(await h.onThreadCreated(store, "founder_ann", founderThread()), "ended:rate");
  assert.deepEqual(store.s.welcomes, []);
});

test("founder: the welcome itself is not counted, checked or pushed", async () => {
  const store = fakeStore({config: FOUNDER, threads: {founder_ann: founderThread()}, users: {ann: {fcmToken: "tok"}}});
  assert.equal(await h.onMessageCreated(store, "founder_ann", "welcome-0", {text: "hi", senderUID: "fay", auto: true}), "skipped");
  assert.deepEqual(store.s.pushes, []);
  assert.deepEqual(store.s.counters, {});
});

test("founder: her messages arrive under her name; messages to her under the conversation's own name", async () => {
  const store = fakeStore({
    config: FOUNDER, threads: {founder_ann: founderThread()},
    users: {ann: {fcmToken: "tok-ann"}, fay: {fcmToken: "tok-fay"}},
  });
  await h.onMessageCreated(store, "founder_ann", "m1", {text: "here she is", senderUID: "fay"});
  await h.onMessageCreated(store, "founder_ann", "m2", {text: "aww", senderUID: "ann"});
  assert.deepEqual(store.s.pushes.map((p) => [p.token, p.title]), [["tok-ann", "first light"], ["tok-fay", "amber tide"]]);
});

// ---------------------------------------------------------------- deleting conversation photos

const DAY = 24 * HOUR;
/** A conversation with photos whose 48 hours end `inMs` from NOW (negative: already ended). */
const photoThread = (inMs, over = {}) => ({participants: ["ann", "bea"], hasPhotos: true, expiresAtMs: NOW + inMs, ...over});

test("overForGood: ended by hand, or out of time with no way left to extend", () => {
  assert.equal(h.overForGood(photoThread(HOUR), NOW), false); // still running
  assert.equal(h.overForGood(photoThread(HOUR, {isManuallyFrozen: true}), NOW), true); // ended by hand
  assert.equal(h.overForGood(photoThread(-HOUR), NOW), false); // time's up, the question is still open
  assert.equal(h.overForGood(photoThread(-DAY + 1000), NOW), false);
  assert.equal(h.overForGood(photoThread(-DAY), NOW), true); // nobody extended it within 24 hours
  assert.equal(h.overForGood(photoThread(HOUR, {hasExtendedOnce: true}), NOW), false); // in its second 48 hours
  assert.equal(h.overForGood(photoThread(-1000, {hasExtendedOnce: true}), NOW), true); // those ran out too
  assert.equal(h.overForGood({participants: ["ann", "fay"], kind: "founder", expiresAtMs: Date.UTC(2100, 0, 1)}, NOW), false);
  assert.equal(h.overForGood({participants: ["ann", "bea"]}, NOW), false); // nothing to go by
});

test("overSinceMs: when the dates say a conversation became over", () => {
  assert.equal(h.overSinceMs(photoThread(-HOUR)), NOW - HOUR + DAY); // 24 hours to decide, nobody did
  assert.equal(h.overSinceMs(photoThread(-HOUR, {hasExtendedOnce: true})), NOW - HOUR); // its second 48 hours ran out
  assert.equal(h.overSinceMs({participants: ["ann", "bea"]}), undefined);
});

const WEEK = 7 * DAY;

test("retention: a conversation ended by hand gets its date on the next run and is deleted whole 7 days later", async () => {
  const store = fakeStore({
    now: NOW,
    threads: {done: photoThread(HOUR, {isManuallyFrozen: true}), live: photoThread(30 * DAY)},
    files: ["chats/done/ann/a.jpg", "chats/done/bea/b.jpg", "chats/live/ann/c.jpg", "posts/ann/F1/0_a.jpg"],
  });
  assert.equal(await h.onRetentionSweep(store, NOW), "retention:1:0:0");
  assert.equal(store.s.threads.done.deleteAfterMs, NOW + WEEK);
  assert.equal(store.s.threads.live.deleteAfterMs, undefined);
  // the photos stay exactly as long as the conversation does
  assert.equal(await h.onRetentionSweep(store, NOW + WEEK - 1), "retention:0:0:0");
  assert.equal(store.s.files.size, 4);
  assert.deepEqual(store.s.deletedThreads, []);
  // the date has come: photos and conversation go together
  assert.equal(await h.onRetentionSweep(store, NOW + WEEK), "retention:0:1:0");
  assert.deepEqual([...store.s.files].sort(), ["chats/live/ann/c.jpg", "posts/ann/F1/0_a.jpg"]);
  assert.deepEqual(store.s.deletedThreads, ["done"]);
  assert.equal("done" in store.s.threads, false);
  assert.deepEqual(store.s.logs, [{kind: "thread", action: "deleted", threadId: "done", files: 2}]);
  // nothing left to look at
  assert.equal(await h.onRetentionSweep(store, NOW + WEEK + HOUR), "retention:0:0:0");
});

test("retention: the 7 days count from when the conversation could no longer be continued", async () => {
  // time ran out an hour ago; the two of them still have 23 hours to say "another 48 hours"
  const store = fakeStore({now: NOW, threads: {waiting: photoThread(-HOUR), second: photoThread(-HOUR, {hasExtendedOnce: true})}});
  assert.equal(await h.onRetentionSweep(store, NOW), "retention:1:0:0");
  assert.equal(store.s.threads.waiting.deleteAfterMs, undefined); // still open
  assert.equal(store.s.threads.second.deleteAfterMs, NOW - HOUR + WEEK); // from the end of its second 48 hours
  // a day later the question is closed too; its days count from that moment, not from this run
  assert.equal(await h.onRetentionSweep(store, NOW + DAY), "retention:1:0:0");
  assert.equal(store.s.threads.waiting.deleteAfterMs, NOW - HOUR + DAY + WEEK);
});

test("retention: conversations without photos are deleted too, and the number of days is a setting", async () => {
  const store = fakeStore({
    now: NOW, settings: {keepEndedDays: 2},
    threads: {t1: {participants: ["ann", "bea"], isManuallyFrozen: true}},
  });
  assert.equal(await h.onRetentionSweep(store, NOW), "retention:1:0:0");
  assert.equal(store.s.threads.t1.deleteAfterMs, NOW + 2 * DAY);
  assert.equal(await h.onRetentionSweep(store, NOW + 2 * DAY), "retention:0:1:0");
  assert.deepEqual(store.s.deletedThreads, ["t1"]);
});

test("retention: 0 days means nothing is ever deleted", async () => {
  const store = fakeStore({
    now: NOW, settings: {keepEndedDays: 0},
    threads: {t1: photoThread(HOUR, {isManuallyFrozen: true, deleteAfterMs: NOW - 1})},
    files: ["chats/t1/ann/a.jpg"],
  });
  assert.equal(await h.onRetentionSweep(store, NOW), "retention:off");
  assert.equal(store.s.files.size, 1);
  assert.deepEqual(store.s.deletedThreads, []);
});

test("retention: the conversation with the founder has no end date, so only ending it starts the 7 days", async () => {
  const founder = {participants: ["ann", "fay"], kind: "founder", expiresAtMs: Date.UTC(2100, 0, 1)};
  const store = fakeStore({now: NOW, threads: {founder_ann: founder}});
  assert.equal(await h.onRetentionSweep(store, NOW + 400 * DAY), "retention:0:0:0");
  store.s.threads.founder_ann = {...founder, isManuallyFrozen: true};
  assert.equal(await h.onRetentionSweep(store, NOW + 400 * DAY), "retention:1:0:0");
});

test("retention: one conversation failing does not stop the others, and is tried again", async () => {
  const due = {isManuallyFrozen: true, deleteAfterMs: NOW - 1};
  const store = fakeStore({
    now: NOW, failPhotoDelete: ["a"], failSchedule: ["c"],
    threads: {a: photoThread(HOUR, due), b: photoThread(HOUR, due), c: photoThread(HOUR, {isManuallyFrozen: true})},
    files: ["chats/a/ann/1.jpg", "chats/b/ann/2.jpg"],
  });
  assert.equal(await h.onRetentionSweep(store, NOW), "retention:0:1:2");
  assert.deepEqual([...store.s.files], ["chats/a/ann/1.jpg"]);
  assert.deepEqual(store.s.deletedThreads, ["b"]);
  assert.equal("a" in store.s.threads, true); // its photos could not be deleted, so it stays whole
  store.s.failPhotoDelete.clear();
  store.s.failSchedule.clear();
  assert.equal(await h.onRetentionSweep(store, NOW + HOUR), "retention:1:1:0");
  assert.equal(store.s.files.size, 0);
  assert.equal(store.s.threads.c.deleteAfterMs, NOW + HOUR + WEEK);
});

test("report: a reported conversation's photos from the other person are kept for the moderators", async () => {
  const store = fakeStore({
    threads: {t1: thread({hasPhotos: true, isManuallyFrozen: true})},
    files: ["chats/t1/bea/b1.jpg", "chats/t1/bea/b2.jpg", "chats/t1/ann/a1.jpg"],
  });
  const report = {type: "chat", threadId: "t1", reporterUID: "ann", reportedUID: "bea", reason: "Sexual content"};
  assert.equal(await h.onReportCreated(store, "r1", report, NOW), "notified");
  assert.deepEqual(store.s.evidence.sort(), ["reportEvidence/r1/b1.jpg", "reportEvidence/r1/b2.jpg"]);
  assert.deepEqual(store.s.reportPatches.r1, {photosKept: 2});
  // the originals are still there for the sweep to delete
  assert.equal(store.s.files.has("chats/t1/bea/b1.jpg"), true);
});

test("report: nothing is kept for an outsider's report, a conversation without photos, or a post report", async () => {
  const files = ["chats/t1/bea/b1.jpg"];
  const outsider = fakeStore({threads: {t1: thread({hasPhotos: true})}, files});
  await h.onReportCreated(outsider, "r1", {type: "chat", threadId: "t1", reporterUID: "cat", reason: "x"}, NOW);
  assert.deepEqual(outsider.s.evidence, []);

  const none = fakeStore({threads: {t1: thread()}, files});
  await h.onReportCreated(none, "r1", {type: "chat", threadId: "t1", reporterUID: "ann", reason: "x"}, NOW);
  assert.deepEqual(none.s.evidence, []);

  const missing = fakeStore({files});
  await h.onReportCreated(missing, "r1", {type: "chat", threadId: "gone", reporterUID: "ann", reason: "x"}, NOW);
  await h.onReportCreated(missing, "r2", {type: "post", postId: "p1", threadId: "t1", reporterUID: "ann", reason: "x"}, NOW);
  assert.deepEqual(missing.s.evidence, []);
});

test("account deletion: her own photos in open conversations go at once; the rest follow with the conversation", async () => {
  const store = fakeStore({
    threads: {
      t1: {participants: ["ann", "bea"], hasPhotos: true},
      t2: {participants: ["ann", "cat"], hasPhotos: true, isManuallyFrozen: true},
    },
    files: ["chats/t1/ann/a.jpg", "chats/t1/bea/b.jpg", "chats/t2/ann/old.jpg", "posts/ann/F1/0_a.jpg"],
  });
  assert.equal(await h.onUserDocDeleted(store, "ann"), "cleaned:0:2:1");
  assert.deepEqual([...store.s.files].sort(), ["chats/t1/bea/b.jpg", "chats/t2/ann/old.jpg"]);
  assert.deepEqual(store.s.frozen, ["t1"]);
  // both conversations are over now; what is left of them goes 7 days later, whole
  await h.onRetentionSweep(store, NOW);
  assert.equal(store.s.files.size, 2);
  await h.onRetentionSweep(store, NOW + 7 * DAY);
  assert.equal(store.s.files.size, 0);
  assert.deepEqual(store.s.deletedThreads.sort(), ["t1", "t2"]);
});

// ---------------------------------------------------------------- "Something feels off"

const feelsOff = (reporterUID) => report(reporterUID, {reason: h.SOFT_REASON});
const people = (n) => Array.from({length: n}, (_, i) => `u${i}`);
const reportsBy = (uids, make) => Object.fromEntries(uids.map((u, i) => [`r${i}`, make(u)]));

test("report: the soft reason is the last entry of the app's list, word for word", () => {
  assert.equal(h.SOFT_REASON, "Something feels off");
});

test("report: three people who feel something is off do not hide a post; ten do", async () => {
  const three = fakeStore({posts: {p1: livePost()}, reports: reportsBy(people(3), feelsOff)});
  assert.equal(await h.onReportCreated(three, "r2", feelsOff("u2"), NOW), "notified");
  assert.deepEqual(three.s.removedPosts, []);
  // the moderators still hear about each one
  assert.equal(three.s.adminNotes.length, 1);

  const nine = fakeStore({posts: {p1: livePost()}, reports: reportsBy(people(9), feelsOff)});
  assert.equal(await h.onReportCreated(nine, "r8", feelsOff("u8"), NOW), "notified");

  const ten = fakeStore({posts: {p1: livePost()}, reports: reportsBy(people(10), feelsOff)});
  assert.equal(await h.onReportCreated(ten, "r9", feelsOff("u9"), NOW), "removed:reports");
  assert.deepEqual(ten.s.removedPosts, [{postId: "p1", reason: "reports"}]);
  assert.equal(ten.s.logs.at(-1).reason, "reports-any:10");
});

test("report: a feeling does not top up reports of a broken rule, but everything together counts toward ten", async () => {
  const mixed = {r0: report("bea"), r1: report("cat"), r2: feelsOff("dee")};
  const store = fakeStore({posts: {p1: livePost()}, reports: mixed});
  assert.equal(await h.onReportCreated(store, "r2", feelsOff("dee"), NOW), "notified");
  // a third person naming a rule does hide it
  store.s.reports.r3 = report("eve");
  assert.equal(await h.onReportCreated(store, "r3", report("eve"), NOW), "removed:reports");
  assert.equal(store.s.logs.at(-1).reason, "reports:3");

  // two rule reports + eight feelings = ten different people
  const many = {...reportsBy(people(8), feelsOff), a: report("bea"), b: report("cat")};
  const ten = fakeStore({posts: {p1: livePost()}, reports: many});
  assert.equal(await h.onReportCreated(ten, "b", report("cat"), NOW), "removed:reports");
  assert.equal(ten.s.logs.at(-1).reason, "reports-any:10");
});

test("report: the same person, the author and accounts without a phone number do not count toward ten either", async () => {
  const same = fakeStore({posts: {p1: livePost()}, reports: reportsBy(Array(12).fill("bea"), feelsOff)});
  assert.equal(await h.onReportCreated(same, "r11", feelsOff("bea"), NOW), "notified");

  const withAuthor = fakeStore({posts: {p1: livePost()}, reports: reportsBy([...people(9), "ann"], feelsOff)});
  assert.equal(await h.onReportCreated(withAuthor, "r9", feelsOff("ann"), NOW), "notified");

  const unverified = fakeStore({posts: {p1: livePost()}, reports: reportsBy(people(10), feelsOff), unverified: ["u0"]});
  assert.equal(await h.onReportCreated(unverified, "r9", feelsOff("u9"), NOW), "notified");
  assert.deepEqual(unverified.s.removedPosts, []);
});

test("report: the number for \"any reason\" can be changed or switched off, on its own", async () => {
  const reports = reportsBy(people(10), feelsOff);
  const off = fakeStore({posts: {p1: livePost()}, reports, settings: {autoHideSoftReports: 0}});
  assert.equal(await h.onReportCreated(off, "r9", feelsOff("u9"), NOW), "notified");

  const five = fakeStore({posts: {p1: livePost()}, reports: reportsBy(people(5), feelsOff), settings: {autoHideSoftReports: 5}});
  assert.equal(await h.onReportCreated(five, "r4", feelsOff("u4"), NOW), "removed:reports");

  // with the rule threshold off, ten of any kind still hide
  const onlySoft = fakeStore({posts: {p1: livePost()}, reports: reportsBy(people(10), report), settings: {autoHideReports: 0}});
  assert.equal(await h.onReportCreated(onlySoft, "r9", report("u9"), NOW), "removed:reports");
  assert.equal(onlySoft.s.logs.at(-1).reason, "reports-any:10");
});

test("report: with several reasons picked, one that names a rule makes it count as a rule report", async () => {
  const both = (uid) => report(uid, {reason: "Spam, ads or scam, Something feels off", reasons: ["Spam, ads or scam", h.SOFT_REASON]});
  const store = fakeStore({posts: {p1: livePost()}, reports: reportsBy(["bea", "cat", "dee"], both)});
  assert.equal(await h.onReportCreated(store, "r2", both("dee"), NOW), "removed:reports");
  assert.equal(store.s.logs.at(-1).reason, "reports:3");

  // picking only the feeling, written as a list, is still only the feeling
  const only = (uid) => report(uid, {reason: h.SOFT_REASON, reasons: [h.SOFT_REASON]});
  const soft = fakeStore({posts: {p1: livePost()}, reports: reportsBy(["bea", "cat", "dee"], only)});
  assert.equal(await h.onReportCreated(soft, "r2", only("dee"), NOW), "notified");
});

// ---------------------------------------------------------------- what Here tells the person who reported

const RECEIVED_TAIL = "Thank you for telling us. We look at every report within 24 hours.";

test("report reply: reporting a post is answered with one line, quoting its title", async () => {
  const store = fakeStore({posts: {p1: livePost()}, users: {bea: {}}});
  const r = report("bea", {title: "First snow"});
  assert.equal(await h.onReportCreated(store, "r1", r, NOW), "notified");
  assert.deepEqual(store.s.systemNotices, [{
    uid: "bea", noticeId: "report-r1-received", atMs: NOW,
    text: `We got your report about the post “First snow”. ${RECEIVED_TAIL}`,
  }]);
  // the same trigger delivered twice writes the same line, not a second one
  await h.onReportCreated(store, "r1", r, NOW);
  assert.equal(store.s.systemNotices.length, 1);
});

test("report reply: a reported conversation is named the way she sees it", async () => {
  const store = fakeStore({
    users: {bea: {}},
    threads: {t1: {participants: ["bea", "ann"], nickname: "soft rain"}},
  });
  await h.onReportCreated(store, "r1", {type: "chat", threadId: "t1", reporterUID: "bea", reason: "x"}, NOW);
  assert.equal(store.s.systemNotices[0].text, `We got your report about your conversation with soft rain. ${RECEIVED_TAIL}`);
  // the conversation is already gone: still answered, without a name
  await h.onReportCreated(store, "r2", {type: "chat", threadId: "gone", reporterUID: "bea", reason: "x"}, NOW);
  assert.equal(store.s.systemNotices[1].text, `We got your report about a conversation. ${RECEIVED_TAIL}`);
});

test("report reply: long or untidy titles are shortened, a missing one is left out", () => {
  const long = h.receivedNotice({type: "post", title: `  ${"snow ".repeat(30)}`}, null);
  assert.match(long, /^We got your report about the post “(snow ){11}snow…”\. /);
  assert.equal(h.receivedNotice({type: "post"}, null), `We got your report about a post. ${RECEIVED_TAIL}`);
  // cut between characters, never inside an emoji
  const emoji = h.receivedNotice({type: "post", title: "🌙".repeat(80)}, null);
  assert.ok(emoji.includes(`“${"🌙".repeat(59)}…”`));
});

test("report reply: nothing for a report that was set aside, or for an account that is gone", async () => {
  // more reports in an hour than the limit: ignored, and not answered
  const flood = fakeStore({users: {bea: {}}, settings: {limits: {reportsPerHour: 1}}});
  await h.onReportCreated(flood, "r1", report("bea"), NOW);
  assert.equal(await h.onReportCreated(flood, "r2", report("bea"), NOW), "ignored:rate");
  assert.deepEqual(flood.s.systemNotices.map((n) => n.noticeId), ["report-r1-received"]);
  // no user doc = the account was deleted: no conversation is created for it
  const gone = fakeStore();
  assert.equal(await h.onReportCreated(gone, "r1", report("bea"), NOW), "notified");
  assert.deepEqual(gone.s.systemNotices, []);
});

test("report reply: a failed write does not change what happens to the report", async () => {
  const store = fakeStore({posts: {p1: livePost()}, users: {bea: {}}, failNotice: ["bea"]});
  assert.equal(await h.onReportCreated(store, "r1", report("bea"), NOW), "notified");
  assert.equal(store.s.adminNotes.length, 1);
  assert.deepEqual(store.s.systemNotices, []);
});

test("report reply: closing a post report as removed tells her, once", async () => {
  const r = report("bea", {title: "First snow", outcome: "Removed "});
  const store = fakeStore({users: {bea: {}}, reports: {r1: r}});
  assert.equal(await h.onReportUpdated(store, "r1", r, NOW), "told:removed");
  assert.deepEqual(store.s.systemNotices, [{
    uid: "bea", noticeId: "report-r1-outcome", atMs: NOW,
    text: "We looked into your report about “First snow” and removed the post. Thank you for looking out for everyone here.",
  }]);
  assert.deepEqual(store.s.reportPatches.r1, {outcomeNotified: "removed"});
  assert.deepEqual(store.s.logs.at(-1), {kind: "report", action: "answered", reason: "removed", uid: "bea", reportId: "r1"});
  // the write-back triggers the function again: it stops there
  assert.equal(await h.onReportUpdated(store, "r1", store.s.reports.r1, NOW), "skipped");
  assert.equal(store.s.systemNotices.length, 1);
});

test("report reply: only approved wording is ever sent", async () => {
  const store = fakeStore({users: {bea: {}}});
  // outcomes whose sentence the founder has not approved yet: closed silently
  for (const outcome of ["banned", "none", "no_violation", "whatever"]) {
    assert.equal(await h.onReportUpdated(store, "r1", report("bea", {outcome}), NOW), "skipped:no-wording");
  }
  assert.equal(await h.onReportUpdated(store, "r2", {type: "chat", threadId: "t1", reporterUID: "bea", outcome: "removed"}, NOW), "skipped:no-wording");
  assert.deepEqual(store.s.systemNotices, []);
  assert.deepEqual(store.s.reportPatches, {});
  assert.equal(h.outcomeNotice({type: "post"}, "removed"), "We looked into your report and removed the post. Thank you for looking out for everyone here.");
});

test("report reply: other changes to a report do nothing", async () => {
  const store = fakeStore({users: {bea: {}}});
  assert.equal(await h.onReportUpdated(store, "r1", report("bea", {photosKept: 2}), NOW), "skipped");
  assert.equal(await h.onReportUpdated(store, "r1", report("bea", {outcome: ""}), NOW), "skipped");
  assert.equal(await h.onReportUpdated(store, "r1", report("bea", {outcome: 3}), NOW), "skipped");
  assert.equal(await h.onReportUpdated(store, "r1", report("bea", {outcome: "removed", ignored: "rate"}), NOW), "skipped");
  assert.equal(await h.onReportUpdated(store, "r1", undefined, NOW), "skipped");
  assert.equal(await h.onReportUpdated(store, "r1", {outcome: "removed"}, NOW), "skipped");
  assert.deepEqual(store.s.systemNotices, []);
});

test("report reply: if she cannot be told, the report is not marked as answered", async () => {
  const down = fakeStore({users: {bea: {}}, failNotice: ["bea"]});
  assert.equal(await h.onReportUpdated(down, "r1", report("bea", {outcome: "removed"}), NOW), "skipped:not-told");
  assert.deepEqual(down.s.reportPatches, {});
  const gone = fakeStore();
  assert.equal(await h.onReportUpdated(gone, "r1", report("bea", {outcome: "removed"}), NOW), "skipped:not-told");
});

test("system conversation: it is nobody's opened conversation, and it goes with the account", async () => {
  const store = fakeStore({
    users: {bea: {}},
    threads: {
      system_bea: {participants: ["bea", "here"], kind: "system"},
      t1: {participants: ["bea", "ann"]},
    },
  });
  // created by the server: not counted against her, never ended for "too many"
  assert.equal(await h.onThreadCreated(store, "system_bea", store.s.threads.system_bea), "skipped");
  assert.deepEqual(store.s.counters, {});
  await h.onReportCreated(store, "r1", report("bea"), NOW);
  assert.equal(store.s.systemNotices.length, 1);
  // deleting the account: the ordinary conversation is ended, Here's is deleted
  assert.equal(await h.onUserDocDeleted(store, "bea"), "cleaned:0:0:1");
  assert.deepEqual(store.s.frozen, ["t1"]);
  assert.deepEqual(store.s.deletedSystem, ["bea"]);
  assert.deepEqual(store.s.systemNotices, []);
});

test("system conversation: banning someone ends her conversations, not Here's", async () => {
  const store = fakeStore({
    phones: {"+14155550100": "bea"},
    threads: {system_bea: {participants: ["bea", "here"], kind: "system"}, t1: {participants: ["bea", "ann"]}},
  });
  await h.onBanCreated(store, "+14155550100");
  assert.deepEqual(store.s.frozen, ["t1"]);
});
