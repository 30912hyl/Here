"use strict";

/**
 * Tests for ../firestore.rules. They need the Firestore emulator:
 *   cd rules-tests && npm ci && npm test
 * (Meant to run in GitHub Actions before anything is deployed.)
 *
 * Each test states one thing a person can or cannot do. Documents that have
 * to exist beforehand are written with rules switched off.
 */

const {test, before, after, beforeEach} = require("node:test");
const fs = require("node:fs");
const path = require("node:path");
const {
  initializeTestEnvironment,
  assertSucceeds,
  assertFails,
} = require("@firebase/rules-unit-testing");
/** @type {any} */
const firebaseModule = require("firebase/compat/app");
require("firebase/compat/firestore");

const firebase = firebaseModule.default || firebaseModule;
const {arrayUnion, arrayRemove, increment, serverTimestamp} = firebase.firestore.FieldValue;

const PROJECT = "demo-here";
const HOUR = 3600 * 1000;
const BUCKET = "here-a6817.firebasestorage.app";

/** @type {import("@firebase/rules-unit-testing").RulesTestEnvironment} */
let env;

before(async () => {
  env = await initializeTestEnvironment({
    projectId: PROJECT,
    firestore: {rules: fs.readFileSync(path.join(__dirname, "..", "firestore.rules"), "utf8")},
  });
});
after(async () => {
  await env.cleanup();
});
beforeEach(async () => {
  await env.clearFirestore();
});

// ---------------------------------------------------------------- helpers

/** A phone-verified account. */
const verified = (uid, phone = "+14155550100") => env.authenticatedContext(uid, {phone_number: phone}).firestore();
/** The anonymous account everyone gets on first launch (no phone). */
const anonymous = (uid) => env.authenticatedContext(uid).firestore();
const signedOut = () => env.unauthenticatedContext().firestore();

const inHours = (h) => new Date(Date.now() + h * HOUR);

/** A download URL shaped like the ones the iOS SDK returns. */
function photoUrl(uid, {port = true, bucket = BUCKET} = {}) {
  const host = `firebasestorage.googleapis.com${port ? ":443" : ""}`;
  const object = encodeURIComponent(`posts/${uid}/5F2C0C1E-AAAA-BBBB-CCCC-0123456789AB/0_9D1B.jpg`);
  return `https://${host}/v0/b/${bucket}/o/${object}?alt=media&token=3b1f-token`;
}

/** A post exactly as the app writes it (Here/Models/Post.swift). */
function post(authorUID, over = {}) {
  return {
    title: "Can't sleep",
    bodyText: "Anyone else up late?",
    imageURLs: [],
    authorUID,
    createdAt: new Date(),
    expiresAt: inHours(48),
    likeCount: 0,
    tags: ["😴"],
    isPrivate: false,
    likedBy: [],
    ...over,
  };
}

/** A conversation exactly as the app writes it (Here/Models/ChatThread.swift). */
function thread(opener, author, over = {}) {
  return {
    postId: "p1",
    postTitle: "Can't sleep",
    participants: [opener, author],
    createdAt: new Date(),
    expiresAt: inHours(48),
    isManuallyFrozen: false,
    hasExtendedOnce: false,
    continueChoices: {[opener]: "undecided", [author]: "undecided"},
    nickname: "quiet moon",
    lastRead: {},
    ...over,
  };
}

const message = (senderUID, text = "hey, your post really resonated with me") => ({text, senderUID, createdAt: new Date()});

/** Writes documents with rules off. `docs` maps a path to its data. */
async function seed(docs) {
  await env.withSecurityRulesDisabled(async (ctx) => {
    const db = ctx.firestore();
    for (const [p, data] of Object.entries(docs)) await db.doc(p).set(data);
  });
}

// ---------------------------------------------------------------- posts: reading

test("feed: anyone signed in can run the feed query (public, not expired)", async () => {
  await seed({"posts/p1": post("ann"), "posts/p2": post("ann", {isPrivate: true})});
  const q = anonymous("guest").collection("posts").where("isPrivate", "==", false).where("expiresAt", ">", new Date());
  const snap = await assertSucceeds(q.get());
  if (snap.size !== 1) throw new Error(`expected 1 public post, got ${snap.size}`);
});

test("feed: a query that could return private posts is refused", async () => {
  await seed({"posts/p1": post("ann")});
  await assertFails(anonymous("guest").collection("posts").where("expiresAt", ">", new Date()).get());
  await assertFails(verified("bea").collection("posts").get());
});

test("feed: signed-out requests read nothing", async () => {
  await seed({"posts/p1": post("ann")});
  await assertFails(signedOut().collection("posts").where("isPrivate", "==", false).get());
});

test("private post: only its author can read it", async () => {
  await seed({"posts/priv": post("ann", {isPrivate: true})});
  await assertSucceeds(verified("ann").doc("posts/priv").get());
  await assertFails(verified("bea").doc("posts/priv").get());
  await assertFails(anonymous("guest").doc("posts/priv").get());
});

test("my posts: the author's own query returns public and private ones", async () => {
  await seed({"posts/a": post("ann"), "posts/b": post("ann", {isPrivate: true}), "posts/c": post("bea")});
  const snap = await assertSucceeds(verified("ann").collection("posts").where("authorUID", "==", "ann").get());
  if (snap.size !== 2) throw new Error(`expected 2 own posts, got ${snap.size}`);
  // ...but nobody can run it for someone else
  await assertFails(verified("bea").collection("posts").where("authorUID", "==", "ann").get());
});

test("public post: readable one at a time too", async () => {
  await seed({"posts/p1": post("ann")});
  await assertSucceeds(anonymous("guest").doc("posts/p1").get());
});

// ---------------------------------------------------------------- posts: writing

test("post: a verified account can post text", async () => {
  await assertSucceeds(verified("ann").doc("posts/p1").set(post("ann")));
});

test("post: an anonymous account cannot post", async () => {
  await assertFails(anonymous("ann").doc("posts/p1").set(post("ann")));
});

test("post: nobody can post as someone else", async () => {
  await assertFails(verified("bea").doc("posts/p1").set(post("ann")));
});

test("post: photos in the author's own Storage folder are accepted", async () => {
  await assertSucceeds(verified("ann").doc("posts/p1").set(post("ann", {imageURLs: [photoUrl("ann")]})));
  await assertSucceeds(verified("ann").doc("posts/p2").set(post("ann", {imageURLs: [photoUrl("ann", {port: false}), photoUrl("ann")]})));
});

test("post: ten photos are accepted, eleven are not", async () => {
  const ten = Array.from({length: 10}, () => photoUrl("ann"));
  await assertSucceeds(verified("ann").doc("posts/p1").set(post("ann", {imageURLs: ten})));
  await assertFails(verified("ann").doc("posts/p2").set(post("ann", {imageURLs: [...ten, photoUrl("ann")]})));
});

test("post: an image on any other host is refused", async () => {
  for (const url of [
    "https://evil.example.com/tracker.jpg",
    "http://firebasestorage.googleapis.com/v0/b/x/o/posts%2Fann%2Fa.jpg",
    `https://firebasestorage.googleapis.com.evil.example/v0/b/${BUCKET}/o/posts%2Fann%2Fa.jpg`,
  ]) {
    await assertFails(verified("ann").doc("posts/p1").set(post("ann", {imageURLs: [url]})));
  }
});

test("post: a photo stored in any other project's bucket is refused", async () => {
  for (const bucket of [
    "attacker-project.appspot.com",
    `${BUCKET}.evil`,
    `x${BUCKET}`,
    "here-a6817xfirebasestorage.app",
  ]) {
    await assertFails(verified("ann").doc("posts/p1").set(post("ann", {imageURLs: [photoUrl("ann", {bucket})]})));
  }
});

test("post: the older name of our own bucket is accepted too", async () => {
  const url = photoUrl("ann", {bucket: "here-a6817.appspot.com"});
  await assertSucceeds(verified("ann").doc("posts/p1").set(post("ann", {imageURLs: [url]})));
});

test("post: a photo from someone else's folder is refused, wherever it sits in the list", async () => {
  await assertFails(verified("ann").doc("posts/p1").set(post("ann", {imageURLs: [photoUrl("bea")]})));
  await assertFails(verified("ann").doc("posts/p2").set(post("ann", {imageURLs: [photoUrl("ann"), photoUrl("ann"), photoUrl("bea")]})));
});

test("post: a banned number cannot post", async () => {
  await seed({"bannedPhones/+14155550199": {reason: "test"}});
  await assertFails(verified("mal", "+14155550199").doc("posts/p1").set(post("mal")));
});

test("post: cannot start with likes, or live longer than 48 hours", async () => {
  await assertFails(verified("ann").doc("posts/p1").set(post("ann", {likeCount: 5})));
  await assertFails(verified("ann").doc("posts/p2").set(post("ann", {expiresAt: inHours(24 * 30)})));
});

test("like: anyone signed in can add or remove her own like, and nothing else", async () => {
  await seed({"posts/p1": post("ann")});
  const bea = anonymous("bea").doc("posts/p1");
  await assertSucceeds(bea.update({likedBy: arrayUnion("bea"), likeCount: increment(1)}));
  await assertFails(bea.update({likedBy: arrayUnion("cat"), likeCount: increment(1)}));
  await assertFails(bea.update({likeCount: increment(10)}));
  await assertFails(bea.update({title: "edited"}));
  await assertSucceeds(bea.update({likedBy: arrayRemove("bea"), likeCount: increment(-1)}));
});

test("post: only its author can delete it", async () => {
  await seed({"posts/p1": post("ann")});
  await assertFails(verified("bea").doc("posts/p1").delete());
  await assertSucceeds(verified("ann").doc("posts/p1").delete());
});

// ---------------------------------------------------------------- conversations

test("conversation: can be opened from another person's live public post", async () => {
  await seed({"posts/p1": post("ann")});
  await assertSucceeds(verified("bea").doc("threads/t1").set(thread("bea", "ann")));
});

test("conversation: must name a post", async () => {
  await seed({"posts/p1": post("ann")});
  const noPost = thread("bea", "ann");
  delete noPost.postId;
  await assertFails(verified("bea").doc("threads/t1").set(noPost));
  await assertFails(verified("bea").doc("threads/t2").set(thread("bea", "ann", {postId: "does-not-exist"})));
});

test("conversation: the other participant must be that post's author", async () => {
  await seed({"posts/p1": post("ann")});
  await assertFails(verified("bea").doc("threads/t1").set(thread("bea", "cat")));
});

test("conversation: not from a private post, and not from an expired one", async () => {
  await seed({"posts/p1": post("ann", {isPrivate: true}), "posts/p2": post("ann", {expiresAt: inHours(-1)})});
  await assertFails(verified("bea").doc("threads/t1").set(thread("bea", "ann")));
  await assertFails(verified("bea").doc("threads/t2").set(thread("bea", "ann", {postId: "p2"})));
});

test("conversation: not with yourself, and not on someone else's behalf", async () => {
  await seed({"posts/p1": post("ann")});
  await assertFails(verified("ann").doc("threads/t1").set(thread("ann", "ann")));
  await assertFails(verified("cat").doc("threads/t2").set(thread("bea", "ann")));
});

test("conversation: cannot be opened with someone who blocked you", async () => {
  await seed({"posts/p1": post("ann"), "users/ann": {blocked: ["bea"]}});
  await assertFails(verified("bea").doc("threads/t1").set(thread("bea", "ann")));
  // someone she has not blocked still can
  await assertSucceeds(verified("cat").doc("threads/t2").set(thread("cat", "ann")));
});

test("conversation: an author with no user document can still be written to", async () => {
  await seed({"posts/p1": post("ann")});
  await assertSucceeds(verified("bea").doc("threads/t1").set(thread("bea", "ann")));
});

test("conversation: an anonymous account cannot open one", async () => {
  await seed({"posts/p1": post("ann")});
  await assertFails(anonymous("bea").doc("threads/t1").set(thread("bea", "ann")));
});

test("conversation: only the two participants can read it", async () => {
  await seed({"threads/t1": thread("bea", "ann")});
  await assertSucceeds(verified("ann").doc("threads/t1").get());
  await assertSucceeds(verified("bea").doc("threads/t1").get());
  await assertFails(verified("cat").doc("threads/t1").get());
  await assertSucceeds(verified("ann").collection("threads").where("participants", "array-contains", "ann").get());
});

test("conversation: a participant can end it but not reopen it or move its expiry", async () => {
  await seed({"threads/t1": thread("bea", "ann")});
  const ann = verified("ann").doc("threads/t1");
  await assertFails(ann.update({expiresAt: inHours(24 * 30)}));
  await assertSucceeds(ann.update({isManuallyFrozen: true}));
  await assertFails(ann.update({isManuallyFrozen: false}));
});

// ---------------------------------------------------------------- "talk for another 48 hours?"

const bothYes = {bea: "yes", ann: "yes"};
/** What the app writes when the second yes arrives (AppState.checkAndExtendThread). */
const extension = (hours = 48) => ({
  expiresAt: inHours(hours),
  hasExtendedOnce: true,
  continueChoices: {bea: "undecided", ann: "undecided"},
});

test("continue: each person answers for herself only", async () => {
  await seed({"threads/t1": thread("bea", "ann", {expiresAt: inHours(-1)})});
  const bea = verified("bea").doc("threads/t1");
  await assertFails(bea.update({"continueChoices.ann": "yes"}));
  await assertSucceeds(bea.update({"continueChoices.bea": "yes"}));
  await assertSucceeds(verified("ann").doc("threads/t1").update({"continueChoices.ann": "no"}));
  // one yes and one no is not an extension
  await assertFails(bea.update(extension()));
});

test("continue: two yeses within 24 hours of the end extend it for 48 hours, once", async () => {
  await seed({"threads/t1": thread("bea", "ann", {expiresAt: inHours(-23), continueChoices: bothYes})});
  const ann = verified("ann").doc("threads/t1");
  // outsiders cannot do it for them
  await assertFails(verified("cat").doc("threads/t1").update(extension()));
  await assertSucceeds(ann.update(extension()));
  // the conversation is open again: the notice and ordinary messages go through
  const msgs = verified("ann").collection("threads/t1/messages");
  await assertSucceeds(msgs.add(message("system", "Conversation continued for 48 hours.")));
  await assertSucceeds(verified("bea").collection("threads/t1/messages").add(message("bea")));
  // and it cannot be extended a second time
  await env.withSecurityRulesDisabled((ctx) =>
    ctx.firestore().doc("threads/t1").update({expiresAt: inHours(-1), continueChoices: bothYes}));
  await assertFails(ann.update(extension()));
});

test("continue: more than 24 hours after the end the question is closed", async () => {
  await seed({
    "threads/late": thread("bea", "ann", {expiresAt: inHours(-25), continueChoices: bothYes}),
    "threads/week": thread("bea", "ann", {expiresAt: inHours(-24 * 7), continueChoices: bothYes}),
    // a few minutes either side of the line (five minutes are allowed for clock drift)
    "threads/just-in": thread("bea", "ann", {expiresAt: inHours(-24 + 2 / 60), continueChoices: bothYes}),
    "threads/just-out": thread("bea", "ann", {expiresAt: inHours(-24 - 10 / 60), continueChoices: bothYes}),
  });
  const ann = verified("ann");
  await assertFails(ann.doc("threads/late").update(extension()));
  await assertFails(ann.doc("threads/week").update(extension()));
  await assertSucceeds(ann.doc("threads/just-in").update(extension()));
  await assertFails(ann.doc("threads/just-out").update(extension()));
});

test("continue: not without two yeses, not for longer than 48 hours, not after it was ended", async () => {
  await seed({
    "threads/one-yes": thread("bea", "ann", {expiresAt: inHours(-1), continueChoices: {bea: "yes", ann: "undecided"}}),
    "threads/both": thread("bea", "ann", {expiresAt: inHours(-1), continueChoices: bothYes}),
    "threads/ended": thread("bea", "ann", {expiresAt: inHours(-1), continueChoices: bothYes, isManuallyFrozen: true}),
  });
  const bea = verified("bea");
  await assertFails(bea.doc("threads/one-yes").update(extension()));
  await assertFails(bea.doc("threads/both").update(extension(24 * 30)));
  await assertFails(bea.doc("threads/ended").update(extension()));
  // the expiry cannot be moved without marking the one extension as used
  await assertFails(bea.doc("threads/both").update({expiresAt: inHours(48)}));
  await assertSucceeds(bea.doc("threads/both").update(extension()));
});

test("continue: the server's \"told that time is up\" mark is not the app's to write, and is not in the way", async () => {
  // functions/ onTimeUpSweep stamps timeUpPushAt on the conversation
  await seed({
    "threads/t1": thread("bea", "ann", {expiresAt: inHours(-1)}),
    "threads/t2": thread("bea", "ann", {expiresAt: inHours(-1), timeUpPushAt: new Date()}),
  });
  await assertFails(verified("bea").doc("threads/t1").update({timeUpPushAt: new Date()}));
  await assertFails(verified("bea").doc("threads/t2").update({timeUpPushAt: firebase.firestore.FieldValue.delete()}));
  await assertSucceeds(verified("bea").doc("threads/t2").update({"continueChoices.bea": "yes"}));
  await assertSucceeds(verified("ann").doc("threads/t2").update({"continueChoices.ann": "yes"}));
  await assertSucceeds(verified("ann").doc("threads/t2").update(extension()));
});

// ---------------------------------------------------------------- messages

test("message: a participant can send one", async () => {
  await seed({"threads/t1": thread("bea", "ann")});
  await assertSucceeds(verified("bea").collection("threads/t1/messages").add(message("bea")));
  await assertSucceeds(verified("ann").collection("threads/t1/messages").add(message("ann", "thank you")));
});

test("message: outsiders cannot send or read", async () => {
  await seed({"threads/t1": thread("bea", "ann"), "threads/t1/messages/m1": message("bea")});
  await assertFails(verified("cat").collection("threads/t1/messages").add(message("cat")));
  await assertFails(verified("cat").collection("threads/t1/messages").get());
  await assertSucceeds(verified("ann").collection("threads/t1/messages").get());
});

test("message: cannot be sent in someone else's name", async () => {
  await seed({"threads/t1": thread("bea", "ann")});
  await assertFails(verified("bea").collection("threads/t1/messages").add(message("ann")));
});

test("message: nothing can be sent to someone who blocked the sender", async () => {
  await seed({"threads/t1": thread("bea", "ann"), "users/ann": {blocked: ["bea"]}});
  await assertFails(verified("bea").collection("threads/t1/messages").add(message("bea")));
  // the person who blocked is not stopped by her own list
  await assertSucceeds(verified("ann").collection("threads/t1/messages").add(message("ann")));
});

test("message: not into an ended or expired conversation", async () => {
  await seed({
    "threads/ended": thread("bea", "ann", {isManuallyFrozen: true}),
    "threads/expired": thread("bea", "ann", {expiresAt: inHours(-1)}),
  });
  await assertFails(verified("bea").collection("threads/ended/messages").add(message("bea")));
  await assertFails(verified("bea").collection("threads/expired/messages").add(message("bea")));
});

test("message: the two system notices are allowed, invented ones are not", async () => {
  await seed({"threads/t1": thread("bea", "ann")});
  const msgs = verified("bea").collection("threads/t1/messages");
  await assertSucceeds(msgs.add(message("system", "Started from: \"Can't sleep\"")));
  await assertSucceeds(msgs.add(message("system", "Conversation continued for 48 hours.")));
  await assertFails(msgs.add(message("system", "Your account will be suspended.")));
});

test("message: an anonymous account cannot send", async () => {
  await seed({"threads/t1": thread("bea", "ann")});
  await assertFails(anonymous("bea").collection("threads/t1/messages").add(message("bea")));
});

// ---------------------------------------------------------------- everything else

test("user document: readable and writable by its owner only", async () => {
  await assertSucceeds(anonymous("ann").doc("users/ann").set({fcmToken: "tok", unreadTotal: 0}, {merge: true}));
  await assertSucceeds(anonymous("ann").doc("users/ann").get());
  await assertFails(verified("bea").doc("users/ann").get());
  await assertFails(verified("bea").doc("users/ann").set({fcmToken: "stolen"}, {merge: true}));
});

test("reports: can be filed as yourself, never read", async () => {
  const report = {type: "post", postId: "p1", reportedUID: "ann", reporterUID: "bea", reason: "Hate speech", details: "", createdAt: serverTimestamp()};
  await assertSucceeds(anonymous("bea").collection("reports").add(report));
  await assertFails(anonymous("bea").collection("reports").add({...report, reporterUID: "cat"}));
  await assertFails(verified("bea").collection("reports").get());
});

test("moderation data is closed to every app user", async () => {
  await seed({
    "bannedPhones/+14155550199": {}, "settings/moderation": {requireApproval: false},
    "modLog/x": {}, "rateLimits/ann": {}, "mail/x": {},
  });
  const ann = verified("ann");
  for (const p of ["bannedPhones/+14155550199", "settings/moderation", "modLog/x", "rateLimits/ann", "mail/x"]) {
    await assertFails(ann.doc(p).get());
    await assertFails(ann.doc(p).set({x: 1}));
  }
});

test("emergency switch: with approval required, only approved numbers can write", async () => {
  await seed({"settings/moderation": {requireApproval: true}, "approvedPhones/+14155550101": {}});
  await assertFails(verified("ann", "+14155550100").doc("posts/p1").set(post("ann")));
  await assertSucceeds(verified("bea", "+14155550101").doc("posts/p2").set(post("bea")));
});

test("voice presence: verified accounts set their own, anyone signed in can count", async () => {
  await assertSucceeds(verified("ann").doc("voicePresence/ann").set({available: true, lastSeen: serverTimestamp()}));
  await assertFails(verified("ann").doc("voicePresence/bea").set({available: true, lastSeen: serverTimestamp()}));
  await assertFails(anonymous("guest").doc("voicePresence/guest").set({available: true, lastSeen: serverTimestamp()}));
  await assertSucceeds(anonymous("guest").collection("voicePresence").where("available", "==", true).get());
});

// ---------------------------------------------------------------- config

test("config: every signed-in phone can read it, nobody can write it", async () => {
  await seed({"config/app": {founderUID: "fay", founderNickname: "first light", chatPhotos: true}});
  await assertSucceeds(anonymous("guest").doc("config/app").get());
  await assertSucceeds(verified("ann").doc("config/app").get());
  await assertFails(signedOut().doc("config/app").get());
  await assertFails(verified("ann").doc("config/app").set({founderUID: "ann"}));
  await assertFails(verified("fay").doc("config/app").update({chatPhotos: false}));
  await assertFails(verified("ann").doc("config/other").set({x: 1}));
});

// ---------------------------------------------------------------- the conversation with the founder

const NEVER = new Date(Date.UTC(2100, 0, 1));

/** The conversation with the founder exactly as the app writes it: no post, kind "founder", no end. */
function founderThread(uid, founder = "fay", over = {}) {
  const t = thread(uid, founder, {kind: "founder", postTitle: "welcome to here", expiresAt: NEVER, ...over});
  if (!("postId" in over)) delete t.postId;
  return t;
}

test("founder: anyone verified can open her one conversation with the founder, without a post", async () => {
  await seed({"config/app": {founderUID: "fay"}});
  await assertSucceeds(verified("ann").doc("threads/founder_ann").set(founderThread("ann")));
  await assertSucceeds(verified("ann").collection("threads/founder_ann/messages").add(message("ann", "hi! yes please")));
  await assertSucceeds(verified("fay", "+14155550111").collection("threads/founder_ann/messages").add(message("fay", "here she is")));
  await assertSucceeds(verified("fay", "+14155550111").doc("threads/founder_ann").get());
  await assertFails(verified("bea").doc("threads/founder_ann").get());
});

test("founder: only under her own fixed id, so there is one per person", async () => {
  await seed({"config/app": {founderUID: "fay"}});
  await assertFails(verified("ann").doc("threads/anything").set(founderThread("ann")));
  await assertFails(verified("ann").doc("threads/founder_bea").set(founderThread("ann")));
});

test("founder: the other person has to be the founder named in config", async () => {
  await seed({"config/app": {founderUID: "fay"}});
  await assertFails(verified("ann").doc("threads/founder_ann").set(founderThread("ann", "bea")));
  // ...and without a config, or with an empty one, there is no such conversation
  await env.clearFirestore();
  await assertFails(verified("ann").doc("threads/founder_ann").set(founderThread("ann")));
  await seed({"config/app": {chatPhotos: true}});
  await assertFails(verified("ann").doc("threads/founder_ann").set(founderThread("ann")));
});

test("founder: the founder cannot start one with anybody", async () => {
  await seed({"config/app": {founderUID: "fay"}});
  await assertFails(verified("fay").doc("threads/founder_ann").set(founderThread("fay", "ann")));
  await assertFails(verified("fay").doc("threads/founder_fay").set(founderThread("fay", "ann")));
});

test("founder: it has no post, and it never runs out unless config says how long it lasts", async () => {
  await seed({"config/app": {founderUID: "fay"}});
  await assertFails(verified("ann").doc("threads/founder_ann").set(founderThread("ann", "fay", {postId: "p1"})));
  await assertFails(verified("ann").doc("threads/founder_ann").set(founderThread("ann", "fay", {expiresAt: inHours(48)})));
  await assertFails(verified("ann").doc("threads/founder_ann").set(founderThread("ann", "fay", {expiresAt: new Date(Date.UTC(2200, 0, 1))})));
  // with a length set in config it is an ordinary deadline again
  await seed({"config/app": {founderUID: "fay", founderThreadHours: 48}});
  await assertFails(verified("ann").doc("threads/founder_ann").set(founderThread("ann")));
  await assertFails(verified("ann").doc("threads/founder_ann").set(founderThread("ann", "fay", {expiresAt: inHours(72)})));
  await assertSucceeds(verified("ann").doc("threads/founder_ann").set(founderThread("ann", "fay", {expiresAt: inHours(48)})));
});

test("founder: an anonymous account, a banned number or someone the founder blocked cannot open it", async () => {
  await seed({"config/app": {founderUID: "fay"}, "bannedPhones/+14155550199": {}, "users/fay": {blocked: ["cat"]}});
  await assertFails(anonymous("guest").doc("threads/founder_guest").set(founderThread("guest")));
  await assertFails(verified("bad", "+14155550199").doc("threads/founder_bad").set(founderThread("bad")));
  await assertFails(verified("cat").doc("threads/founder_cat").set(founderThread("cat")));
});

test("founder: \"kind\" cannot be used for anything else, and cannot be changed later", async () => {
  await seed({"config/app": {founderUID: "fay"}, "posts/p1": post("bea")});
  await assertFails(verified("ann").doc("threads/t1").set(thread("ann", "bea", {kind: "special"})));
  await assertFails(verified("ann").doc("threads/t1").set(thread("ann", "bea", {kind: "founder"})));
  await assertSucceeds(verified("ann").doc("threads/t1").set(thread("ann", "bea")));
  await assertFails(verified("ann").doc("threads/t1").update({kind: "founder"}));
});

test("founder: it cannot be turned into a 48-hour conversation by two yeses", async () => {
  await seed({
    "config/app": {founderUID: "fay"},
    "threads/founder_ann": founderThread("ann", "fay", {continueChoices: {ann: "yes", fay: "yes"}}),
  });
  await assertFails(verified("ann").doc("threads/founder_ann").update({
    expiresAt: inHours(48), hasExtendedOnce: true, continueChoices: {ann: "undecided", fay: "undecided"},
  }));
});

test("conversation: nothing the server writes can be set by whoever creates it", async () => {
  await seed({"posts/p1": post("bea")});
  for (const extra of [{hasPhotos: true}, {deleteAfter: inHours(900)}, {timeUpPushAt: new Date()}]) {
    await assertFails(verified("ann").doc("threads/t1").set(thread("ann", "bea", extra)));
  }
});

// ---------------------------------------------------------------- photo messages

const photoMessage = (senderUID, imagePath, text = "") => ({text, senderUID, createdAt: new Date(), imagePath});

test("photo message: a participant can send a photo she uploaded for this conversation", async () => {
  await seed({"threads/t1": thread("ann", "bea")});
  await assertSucceeds(verified("ann").collection("threads/t1/messages").add(photoMessage("ann", "chats/t1/ann/8F2C0C1E-01.jpg")));
  await assertSucceeds(verified("bea").collection("threads/t1/messages").add(photoMessage("bea", "chats/t1/bea/a_b-9.jpg", "look")));
});

test("photo message: the file must be her own, in this conversation's folder, a .jpg, and nothing else", async () => {
  await seed({"threads/t1": thread("ann", "bea"), "threads/t2": thread("ann", "cat")});
  const send = (path) => verified("ann").collection("threads/t1/messages").add(photoMessage("ann", path));
  await assertFails(send("chats/t1/bea/x.jpg")); // the other person's folder
  await assertFails(send("chats/t2/ann/x.jpg")); // another conversation of hers
  await assertFails(send("posts/ann/F1/x.jpg")); // a post photo
  await assertFails(send("chats/t1/ann/x.png"));
  await assertFails(send("chats/t1/ann/sub/x.jpg"));
  await assertFails(send("chats/t1/ann/../bea/x.jpg"));
  await assertFails(send("https://example.com/x.jpg"));
  await assertFails(send(""));
  await assertFails(verified("ann").collection("threads/t1/messages").add({...message("ann"), imagePath: 7}));
  await assertFails(verified("ann").collection("threads/t1/messages").add({...message("ann"), imagePath: ["chats/t1/ann/x.jpg"]}));
});

test("photo message: a conversation id cannot be used as a pattern to reach another folder", async () => {
  await seed({"threads/t.": thread("ann", "bea"), "threads/t1": thread("ann", "bea")});
  await assertFails(verified("ann").collection("threads/t./messages").add(photoMessage("ann", "chats/t1/ann/x.jpg")));
});

test("photo message: system notices cannot carry a photo", async () => {
  await seed({"threads/t1": thread("ann", "bea")});
  await assertFails(verified("ann").collection("threads/t1/messages").add(
      {text: "Conversation continued for 48 hours.", senderUID: "system", createdAt: new Date(), imagePath: "chats/t1/ann/x.jpg"}));
});

test("photo message: the switch in config turns photos off for everyone, and only photos", async () => {
  await seed({"threads/t1": thread("ann", "bea"), "config/app": {chatPhotos: false}});
  await assertFails(verified("ann").collection("threads/t1/messages").add(photoMessage("ann", "chats/t1/ann/x.jpg")));
  await assertSucceeds(verified("ann").collection("threads/t1/messages").add(message("ann")));
  // a config that does not mention photos leaves them on
  await seed({"config/app": {founderUID: "fay"}});
  await assertSucceeds(verified("ann").collection("threads/t1/messages").add(photoMessage("ann", "chats/t1/ann/x.jpg")));
});

test("message: the marks the server puts on a message cannot be written from a phone", async () => {
  await seed({"threads/t1": thread("ann", "bea")});
  const add = (extra) => verified("ann").collection("threads/t1/messages").add({...photoMessage("ann", "chats/t1/ann/x.jpg"), ...extra});
  await assertFails(add({imageOK: true}));
  await assertFails(add({imageRemoved: true}));
  await assertFails(add({auto: true}));
  await assertFails(verified("ann").collection("threads/t1/messages").add({...message("ann"), anything: 1}));
});

test("message: once sent it cannot be edited or deleted from a phone", async () => {
  await seed({"threads/t1": thread("ann", "bea"), "threads/t1/messages/m1": photoMessage("ann", "chats/t1/ann/x.jpg")});
  await assertFails(verified("ann").doc("threads/t1/messages/m1").update({imageOK: true}));
  await assertFails(verified("ann").doc("threads/t1/messages/m1").update({imageRemoved: true}));
  await assertFails(verified("ann").doc("threads/t1/messages/m1").update({text: "edited"}));
  await assertFails(verified("ann").doc("threads/t1/messages/m1").delete());
});

// ---------------------------------------------------------------- reports with several reasons

const ALL_REASONS = [
  "May not be a woman", "Seems under 18", "Harassment, threats or hate", "Sexual or violent content",
  "Spam, ads or scam", "Someone's private info or photos", "Self-harm or safety concern", "Something feels off",
];
const reportWith = (reasons, over = {}) => ({
  type: "post", postId: "p1", reportedUID: "ann", reporterUID: "bea",
  reason: reasons.join(", "), reasons, details: "", createdAt: serverTimestamp(), ...over,
});

test("report: one reason, several, or all eight at once", async () => {
  const bea = verified("bea");
  await assertSucceeds(bea.collection("reports").add(reportWith(["Something feels off"])));
  await assertSucceeds(bea.collection("reports").add(reportWith(["May not be a woman", "Spam, ads or scam"])));
  await assertSucceeds(bea.collection("reports").add(reportWith(ALL_REASONS)));
  // a report with only the one-line text (how the app wrote it before) is still accepted
  const {reasons: _none, ...textOnly} = reportWith(["Hate speech"]);
  await assertSucceeds(bea.collection("reports").add(textOnly));
});

test("report: the list of reasons has to be a short list of short texts", async () => {
  const bea = verified("bea");
  await assertFails(bea.collection("reports").add(reportWith([], {reason: "x"})));
  await assertFails(bea.collection("reports").add(reportWith([...ALL_REASONS, "a ninth"], {reason: "x"})));
  await assertFails(bea.collection("reports").add(reportWith(["x".repeat(101)], {reason: "x"})));
  await assertFails(bea.collection("reports").add(reportWith(["ok", 7], {reason: "x"})));
  await assertFails(bea.collection("reports").add({...reportWith(["ok"]), reasons: "ok"}));
  await assertFails(bea.collection("reports").add(reportWith(["ok"], {reason: "x".repeat(401)})));
});

// ---------------------------------------------------------------- Here's own conversation (kind "system")

/** A person's "system" conversation exactly as the server writes it (functions: store.addSystemNotice). */
function systemThread(uid, over = {}) {
  const t = thread(uid, "here", {kind: "system", postTitle: "", nickname: "Here", continueChoices: {}, expiresAt: NEVER, ...over});
  delete t.postId;
  return t;
}
const notice = (text = "We got your report about a post.") => ({text, senderUID: "here", createdAt: new Date(), auto: true});

test("system: she can read Here's lines to her and mark them read; nobody else can", async () => {
  await seed({"threads/system_ann": systemThread("ann"), "threads/system_ann/messages/report-r1-received": notice()});
  await assertSucceeds(verified("ann").doc("threads/system_ann").get());
  await assertSucceeds(verified("ann").collection("threads/system_ann/messages").get());
  await assertSucceeds(verified("ann").doc("threads/system_ann").update({"lastRead.ann": new Date()}));
  await assertFails(verified("bea").doc("threads/system_ann").get());
  await assertFails(verified("bea").collection("threads/system_ann/messages").get());
  await assertFails(verified("bea").doc("threads/system_ann").update({"lastRead.bea": new Date()}));
});

test("system: nobody can write in it, not even the lines the app itself may write elsewhere", async () => {
  await seed({"threads/system_ann": systemThread("ann")});
  const messages = verified("ann").collection("threads/system_ann/messages");
  await assertFails(messages.add(message("ann", "hello?")));
  await assertFails(messages.add({text: 'Started from: "x"', senderUID: "system", createdAt: new Date()}));
  await assertFails(messages.add(notice("We banned her.")));
  await assertFails(messages.doc("report-r1-received").set(notice("We banned her.")));
});

test("system: it cannot be ended, continued or changed from a phone", async () => {
  await seed({"threads/system_ann": systemThread("ann"), "threads/system_ann/messages/n1": notice()});
  const doc = verified("ann").doc("threads/system_ann");
  await assertFails(doc.update({isManuallyFrozen: true}));
  await assertFails(doc.update({"continueChoices.ann": "yes"}));
  await assertFails(doc.update({nickname: "Admin"}));
  await assertFails(doc.update({kind: "founder"}));
  await assertFails(doc.delete());
  await assertFails(verified("ann").doc("threads/system_ann/messages/n1").delete());
  await assertFails(verified("ann").doc("threads/system_ann/messages/n1").update({text: "edited"}));
});

test("system: a phone cannot create one, under that id or with that kind", async () => {
  await seed({"posts/p1": post("ann"), "config/app": {founderUID: "fay"}});
  await assertFails(verified("bea").doc("threads/system_bea").set(systemThread("bea")));
  await assertFails(verified("bea").doc("threads/t9").set(systemThread("bea")));
  // an ordinary conversation, or the founder's, cannot take such an id either
  await assertFails(verified("bea").doc("threads/system_bea").set(thread("bea", "ann")));
  await assertFails(verified("bea").doc("threads/system_ann").set(thread("bea", "ann")));
  await assertFails(verified("bea").doc("threads/system_bea").set(founderThread("bea")));
  // the very same conversation under an ordinary id is fine
  await assertSucceeds(verified("bea").doc("threads/t1").set(thread("bea", "ann")));
});
