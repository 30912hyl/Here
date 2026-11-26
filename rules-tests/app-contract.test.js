"use strict";

/**
 * The app's side of the contract with ../firestore.rules.
 *
 * firestore.test.js states what a person may and may not do. This file goes
 * the other way round: it walks through every read and write the iOS app
 * actually performs (Here/State/AppState.swift and Here/Services/*.swift),
 * with the same fields, the same queries and in the same order, and checks
 * that the rules let each one through. A request the rules refuse here is a
 * feature that silently stops working once these rules are live: the app
 * only prints the error.
 *
 * When a call site in the app changes, change it here too.
 *   cd rules-tests && npm ci && npm test
 */

const {test, before, after, beforeEach} = require("node:test");
const fs = require("node:fs");
const path = require("node:path");
const {initializeTestEnvironment, assertSucceeds, assertFails} = require("@firebase/rules-unit-testing");
/** @type {any} */
const firebaseModule = require("firebase/compat/app");
require("firebase/compat/firestore");

const firebase = firebaseModule.default || firebaseModule;
const {arrayUnion, arrayRemove, increment, serverTimestamp} = firebase.firestore.FieldValue;
const deleteField = firebase.firestore.FieldValue.delete;

const HOUR = 3600 * 1000;
const BUCKET = "here-a6817.firebasestorage.app";

/** @type {import("@firebase/rules-unit-testing").RulesTestEnvironment} */
let env;

before(async () => {
  env = await initializeTestEnvironment({
    // its own project id, so this file and firestore.test.js cannot clear each other's data
    projectId: "demo-here-contract",
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

/** A phone-verified account: what someone is after "Verify your phone". */
const verified = (uid, phone = "+14155550100") => env.authenticatedContext(uid, {phone_number: phone}).firestore();
/** The anonymous account every install gets on first launch. */
const anonymous = (uid) => env.authenticatedContext(uid).firestore();
const inHours = (h) => new Date(Date.now() + h * HOUR);

/** Firestore.Encoder().encode(Post(...)) — Here/Models/Post.swift. */
function post(authorUID, over = {}) {
  const createdAt = new Date();
  return {
    title: "Can't sleep",
    bodyText: "Anyone else up late?",
    imageURLs: [],
    authorUID,
    createdAt,
    expiresAt: new Date(createdAt.getTime() + 48 * HOUR),
    likeCount: 0,
    tags: ["😴"],
    isPrivate: false,
    likedBy: [],
    ...over,
  };
}

/** setData(from: ChatThread(...)) — Here/Models/ChatThread.swift. */
function thread(opener, author, over = {}) {
  const createdAt = new Date();
  return {
    postId: "p1",
    postTitle: "Can't sleep",
    participants: [opener, author],
    createdAt,
    expiresAt: new Date(createdAt.getTime() + 48 * HOUR),
    isManuallyFrozen: false,
    hasExtendedOnce: false,
    continueChoices: {[opener]: "undecided", [author]: "undecided"},
    nickname: "quiet moon",
    lastRead: {},
    ...over,
  };
}

/** addDocument(from: ChatMessage(...)). */
const message = (senderUID, text = "hey, your post really resonated with me") => ({text, senderUID, createdAt: new Date()});

async function seed(docs) {
  await env.withSecurityRulesDisabled(async (ctx) => {
    const db = ctx.firestore();
    for (const [p, data] of Object.entries(docs)) await db.doc(p).set(data);
  });
}

function photoUrl(uid, n = 0) {
  const object = encodeURIComponent(`posts/${uid}/5F2C0C1E-AAAA-BBBB-CCCC-0123456789AB/${n}_9D1B.jpg`);
  return `https://firebasestorage.googleapis.com:443/v0/b/${BUCKET}/o/${object}?alt=media&token=3b1f-token`;
}

/** ReportSheet.reasons — Here/Views/ReportSheet.swift. */
const ALL_REASONS = [
  "May not be a woman", "Seems under 18", "Harassment, threats or hate", "Sexual or violent content",
  "Spam, ads or scam", "Someone's private info or photos", "Self-harm or safety concern", "Something feels off",
];

// ---------------------------------------------------------------- launch: the listeners AppState starts

test("launch: the feed listener (AppState.listenToFeed)", async () => {
  await seed({"posts/p1": post("ann")});
  const q = (db) => db.collection("posts").where("isPrivate", "==", false).where("expiresAt", ">", new Date()).get();
  await assertSucceeds(q(anonymous("guest")));
  await assertSucceeds(q(verified("bea")));
});

test("launch: my posts (AppState.listenToMyPosts) — also for an account that has never posted", async () => {
  await seed({"posts/p1": post("ann"), "posts/p2": post("ann", {isPrivate: true})});
  await assertSucceeds(verified("ann").collection("posts").where("authorUID", "==", "ann").get());
  await assertSucceeds(anonymous("guest").collection("posts").where("authorUID", "==", "guest").get());
});

test("launch: my conversations (AppState.listenToThreads) — newest first", async () => {
  await seed({"threads/t1": thread("bea", "ann")});
  const q = (db, uid) => db.collection("threads").where("participants", "array-contains", uid).orderBy("createdAt", "desc").get();
  await assertSucceeds(q(verified("bea"), "bea"));
  await assertSucceeds(q(verified("ann"), "ann"));
  // every install runs this, signed in with a phone or not
  await assertSucceeds(q(anonymous("guest"), "guest"));
});

test("launch: the last message of each conversation, and the whole history once it is opened (listenToMessages)", async () => {
  await seed({"threads/t1": thread("bea", "ann"), "threads/t1/messages/m1": message("bea")});
  const msgs = verified("ann").collection("threads/t1/messages");
  await assertSucceeds(msgs.orderBy("createdAt").limitToLast(1).get());
  await assertSucceeds(msgs.orderBy("createdAt").get());
});

test("launch: my own user document, even before it exists (listenToUser)", async () => {
  await assertSucceeds(anonymous("guest").doc("users/guest").get());
  await assertSucceeds(verified("bea").doc("users/bea").get());
});

test("launch: the unread count is mirrored for the push badge (syncBadge)", async () => {
  // runs for every account, with or without a phone number, document or no document
  await assertSucceeds(anonymous("guest").doc("users/guest").set({unreadTotal: 0}, {merge: true}));
  await assertSucceeds(verified("bea").doc("users/bea").set({unreadTotal: 2}, {merge: true}));
  await seed({"users/ann": {fcmToken: "tok", blocked: ["x"], termsVersion: "2026-10b"}});
  await assertSucceeds(verified("ann").doc("users/ann").set({unreadTotal: 1}, {merge: true}));
});

test("launch: the push token is saved (PushManager.saveToken) and dropped on sign-out (AuthService.signOut)", async () => {
  const token = {fcmToken: "f".repeat(160), tokenUpdatedAt: serverTimestamp()};
  // the token can arrive while the account is still anonymous
  await assertSucceeds(anonymous("guest").doc("users/guest").set(token, {merge: true}));
  await assertSucceeds(verified("bea").doc("users/bea").set(token, {merge: true}));
  await assertSucceeds(verified("bea").doc("users/bea").update({fcmToken: deleteField()}));
});

// ---------------------------------------------------------------- signing in

test("verify phone: woman / 18+ / terms are recorded (AuthService.recordTermsAcceptance)", async () => {
  const accepted = {womanAttested: true, termsVersion: "2026-10b", termsAcceptedAt: serverTimestamp()};
  await assertSucceeds(verified("bea").doc("users/bea").set(accepted, {merge: true}));
  await seed({"users/ann": {unreadTotal: 0, fcmToken: "tok"}});
  await assertSucceeds(verified("ann").doc("users/ann").set(accepted, {merge: true}));
});

// ---------------------------------------------------------------- posting

test("post: every shape the composer can produce (AppState.addPost)", async () => {
  const posts = verified("ann").collection("posts");
  await assertSucceeds(posts.doc().set(post("ann")));
  // a title and nothing else
  await assertSucceeds(posts.doc().set(post("ann", {bodyText: ""})));
  // just for me
  await assertSucceeds(posts.doc().set(post("ann", {isPrivate: true})));
  // several tags, a tag she typed herself, lower-cased by the app
  await assertSucceeds(posts.doc().set(post("ann", {tags: ["😴", "🌙", "🍚🥄"]})));
  // photos
  await assertSucceeds(posts.doc().set(post("ann", {imageURLs: [photoUrl("ann", 0), photoUrl("ann", 1)]})));
  // a long one
  await assertSucceeds(posts.doc().set(post("ann", {title: "t".repeat(300), bodyText: "b".repeat(5000)})));
});

test("post: here on, here off (AppState.toggleLike)", async () => {
  await seed({"posts/p1": post("ann")});
  const like = (db, me) => db.doc("posts/p1").update({likeCount: increment(1), likedBy: arrayUnion(me)});
  const unlike = (db, me) => db.doc("posts/p1").update({likeCount: increment(-1), likedBy: arrayRemove(me)});
  await assertSucceeds(like(verified("bea"), "bea"));
  await assertSucceeds(like(anonymous("guest"), "guest"));
  await assertSucceeds(unlike(verified("bea"), "bea"));
  await assertSucceeds(unlike(anonymous("guest"), "guest"));
  // the author can tap here on her own post
  await assertSucceeds(like(verified("ann"), "ann"));
});

// ---------------------------------------------------------------- a conversation, start to finish

test("chat: the first message creates the conversation, the \"Started from\" notice and the message, in that order (AppState.sendMessage)", async () => {
  for (const title of ["Can't sleep", "she said \"it's fine\" 🙃", "line one\nline two", "t".repeat(300)]) {
    await env.clearFirestore();
    await seed({"posts/p1": post("ann", {title})});
    const bea = verified("bea");
    await assertSucceeds(bea.doc("threads/t1").set(thread("bea", "ann", {postTitle: title})));
    await assertSucceeds(bea.collection("threads/t1/messages").add(message("system", `Started from: "${title}"`)));
    await assertSucceeds(bea.collection("threads/t1/messages").add(message("bea")));
    // and she answers
    await assertSucceeds(verified("ann", "+14155550111").collection("threads/t1/messages").add(message("ann", "hi")));
  }
});

test("chat: opening a conversation stamps it read — while it runs, at time's up, and after it ended (AppState.markThreadRead)", async () => {
  await seed({
    "threads/running": thread("bea", "ann"),
    "threads/timesup": thread("bea", "ann", {expiresAt: inHours(-1)}),
    "threads/lapsed": thread("bea", "ann", {expiresAt: inHours(-30)}),
    "threads/ended": thread("bea", "ann", {isManuallyFrozen: true}),
  });
  for (const id of ["running", "timesup", "lapsed", "ended"]) {
    await assertSucceeds(verified("ann").doc(`threads/${id}`).update({"lastRead.ann": new Date()}));
  }
});

test("chat: time's up — No, Yes, Yes, extended, the notice, and talking again (setContinueChoice / checkAndExtendThread)", async () => {
  await seed({"threads/t1": thread("bea", "ann", {expiresAt: inHours(-2)}), "threads/t2": thread("bea", "ann", {expiresAt: inHours(-2)})});
  const bea = verified("bea");
  const ann = verified("ann", "+14155550111");
  await assertSucceeds(bea.doc("threads/t2").update({"continueChoices.bea": "no"}));

  await assertSucceeds(bea.doc("threads/t1").update({"continueChoices.bea": "yes"}));
  // after her own yes the app re-reads the conversation
  await assertSucceeds(bea.doc("threads/t1").get());
  await assertSucceeds(ann.doc("threads/t1").update({"continueChoices.ann": "yes"}));
  await assertSucceeds(ann.doc("threads/t1").get());
  await assertSucceeds(ann.doc("threads/t1").update({
    expiresAt: inHours(48),
    hasExtendedOnce: true,
    continueChoices: {bea: "undecided", ann: "undecided"},
  }));
  await assertSucceeds(ann.collection("threads/t1/messages").add(message("system", "Conversation continued for 48 hours.")));
  await assertSucceeds(bea.collection("threads/t1/messages").add(message("bea", "so glad")));
});

test("chat: End Conversation (manualFreezeThread)", async () => {
  await seed({"threads/t1": thread("bea", "ann"), "threads/t2": thread("bea", "ann", {expiresAt: inHours(-1)})});
  await assertSucceeds(verified("ann").doc("threads/t1").update({isManuallyFrozen: true}));
  // ending one whose time is already up (the shield is still there)
  await assertSucceeds(verified("ann").doc("threads/t2").update({isManuallyFrozen: true}));
});

test("chat: Report & End — end it, read her messages back, file the report (AppState.reportChat)", async () => {
  await seed({"threads/t1": thread("bea", "ann"), "threads/t1/messages/m1": message("bea", "rude thing")});
  const ann = verified("ann");
  await assertSucceeds(ann.doc("threads/t1").update({isManuallyFrozen: true}));
  await assertSucceeds(ann.collection("threads/t1/messages").orderBy("createdAt", "desc").limit(300).get());
  const transcript = Array.from({length: 30}, (_, i) => ({text: `message ${i}`, at: new Date()}));
  await assertSucceeds(ann.collection("reports").add({
    type: "chat",
    threadId: "t1",
    postId: "p1",
    postTitle: "Can't sleep",
    reportedUID: "bea",
    reporterUID: "ann",
    // she can tick several: `reasons` is the list, `reason` the same as one line (AppState.reportChat)
    reason: "Harassment, threats or hate, Something feels off",
    reasons: ["Harassment, threats or hate", "Something feels off"],
    details: "",
    messages: transcript,
    createdAt: serverTimestamp(),
  }));
  // an old conversation that has no post id on it: the app sends ""
  await assertSucceeds(ann.collection("reports").add({
    type: "chat", threadId: "t1", postId: "", postTitle: "Can't sleep", reportedUID: "bea", reporterUID: "ann",
    reason: "Something feels off", reasons: ["Something feels off"], details: "d".repeat(500), messages: [], createdAt: serverTimestamp(),
  }));
});

test("chat: Block & End, and unblocking from Profile (blockUser / unblockUser)", async () => {
  await seed({"threads/t1": thread("bea", "ann")});
  const ann = verified("ann");
  await assertSucceeds(ann.doc("threads/t1").update({isManuallyFrozen: true}));
  // no user document yet
  await assertSucceeds(ann.doc("users/ann").set({blocked: arrayUnion("bea")}, {merge: true}));
  await assertSucceeds(ann.doc("users/ann").set({blocked: arrayUnion("cat")}, {merge: true}));
  await assertSucceeds(ann.doc("users/ann").set({blocked: arrayRemove("bea")}, {merge: true}));
});

// ---------------------------------------------------------------- the ⋯ menu on a post

test("post menu: Report Post (AppState.reportPost) and Block her", async () => {
  await seed({"posts/p1": post("ann", {imageURLs: [photoUrl("ann")]})});
  const report = (uid) => ({
    type: "post",
    postId: "p1",
    reportedUID: "ann",
    reporterUID: uid,
    // all eight ticked: the longest a report can get (AppState.reportPost)
    reason: ALL_REASONS.join(", "),
    reasons: ALL_REASONS,
    details: "",
    title: "Can't sleep",
    bodyText: "Anyone else up late?",
    imageURLs: [photoUrl("ann")],
    createdAt: serverTimestamp(),
  });
  await assertSucceeds(verified("bea").collection("reports").add(report("bea")));
  await assertSucceeds(verified("bea").doc("users/bea").set({blocked: arrayUnion("ann")}, {merge: true}));
});

// ---------------------------------------------------------------- voice

test("voice: open to connect on and off, and the count of who is open (VoicePresenceService)", async () => {
  const bea = verified("bea");
  await assertSucceeds(bea.doc("voicePresence/bea").set({available: true, lastSeen: serverTimestamp()}, {merge: true}));
  await assertSucceeds(bea.collection("voicePresence").where("available", "==", true).get());
  await assertSucceeds(bea.doc("voicePresence/bea").set({available: false, lastSeen: serverTimestamp()}, {merge: true}));
});

// ---------------------------------------------------------------- leaving

test("delete account: posts, conversations, voice presence, then the user document (AppState.deleteMyContent)", async () => {
  await seed({
    "posts/p1": post("ann"),
    "posts/p2": post("ann", {isPrivate: true}),
    "posts/old": post("ann", {createdAt: inHours(-100), expiresAt: inHours(-52)}),
    "threads/running": thread("bea", "ann"),
    "threads/timesup": thread("bea", "ann", {expiresAt: inHours(-1)}),
    "threads/lapsed": thread("bea", "ann", {expiresAt: inHours(-30)}),
    "users/ann": {fcmToken: "tok", unreadTotal: 0, blocked: [], womanAttested: true, termsVersion: "2026-10b"},
    "voicePresence/ann": {available: false},
  });
  const ann = verified("ann");
  await assertSucceeds(ann.collection("posts").where("authorUID", "==", "ann").get());
  for (const id of ["p1", "p2", "old"]) await assertSucceeds(ann.doc(`posts/${id}`).delete());
  // every conversation that was not ended by hand, whatever its clock says
  for (const id of ["running", "timesup", "lapsed"]) {
    await assertSucceeds(ann.doc(`threads/${id}`).update({isManuallyFrozen: true}));
  }
  await assertSucceeds(ann.doc("voicePresence/ann").delete());
  await assertSucceeds(ann.doc("users/ann").delete());
});

test("delete account: for someone who never used Voice and never got a user document", async () => {
  const cat = verified("cat");
  await assertSucceeds(cat.collection("posts").where("authorUID", "==", "cat").get());
  await assertSucceeds(cat.doc("voicePresence/cat").delete());
  await assertSucceeds(cat.doc("users/cat").delete());
});

// ---------------------------------------------------------------- what the app must not rely on

test("known and intended: the feed's fallback query (no index) is refused by these rules", async () => {
  // AppState.listenToFeedWithoutIndex. The rules answer only "public posts"
  // queries, so the index has to exist before the rules are deployed.
  await seed({"posts/p1": post("ann")});
  await assertFails(anonymous("guest").collection("posts").where("expiresAt", ">", new Date()).get());
});

// ---------------------------------------------------------------- the conversation with the founder, and photos
//
// The app's side of these two is written against exactly these calls
// (AppState.listenToConfig / startFounderChat / sendMessage / sendPhoto /
// reportChat). The files themselves go to Storage: see storage.test.js.

/** Date(timeIntervalSince1970: 4_102_444_800): ChatThread.never in the app. */
const NEVER = new Date(4102444800 * 1000);

/** ChatThread(id: "founder_<uid>", postId: nil, postTitle: "", participants: [uid, founder], kind: "founder", expiresAt: .never). */
function founderThread(uid, founder) {
  const t = thread(uid, founder, {postTitle: "", kind: "founder", expiresAt: NEVER, nickname: "amber tide"});
  delete t.postId; // an optional that is nil is not written at all
  return t;
}

test("launch: the app's public config (AppState.listenToConfig) — also before it exists, also for an anonymous install", async () => {
  await assertSucceeds(anonymous("guest").doc("config/app").get());
  await seed({"config/app": {founderUID: "fay", founderNickname: "first light", founderWelcome: ["hi"], chatPhotos: true}});
  await assertSucceeds(anonymous("guest").doc("config/app").get());
  await assertSucceeds(verified("ann").doc("config/app").get());
});

test("founder: her first reply creates the conversation, then the message; the founder answers; both stamp it read", async () => {
  await seed({"config/app": {founderUID: "fay", founderNickname: "first light", founderWelcome: ["hi"]}});
  const ann = verified("ann");
  const fay = verified("fay", "+14155550111");
  await assertSucceeds(ann.doc("threads/founder_ann").set(founderThread("ann", "fay")));
  // no "Started from" notice here: there is no post
  await assertSucceeds(ann.collection("threads/founder_ann/messages").add(message("ann", "yes please!!")));
  await assertSucceeds(fay.collection("threads/founder_ann/messages").add(message("fay", "here she is")));
  await assertSucceeds(ann.doc("threads/founder_ann").update({"lastRead.ann": new Date()}));
  await assertSucceeds(fay.doc("threads/founder_ann").update({"lastRead.fay": new Date()}));
  // it shows up in both people's conversation lists, with the same query as every other conversation
  for (const [db, uid] of [[ann, "ann"], [fay, "fay"]]) {
    const snap = await assertSucceeds(db.collection("threads").where("participants", "array-contains", uid).orderBy("createdAt", "desc").get());
    if (snap.size !== 1) throw new Error(`expected the founder conversation in ${uid}'s list`);
  }
  // the welcome the server writes into it is readable like any message
  await seed({"threads/founder_ann/messages/welcome-0": {text: "hi", senderUID: "fay", createdAt: new Date(Date.now() - 5000), auto: true}});
  await assertSucceeds(ann.collection("threads/founder_ann/messages").orderBy("createdAt").get());
});

test("photo: after the upload, the message names the file; with or without words (AppState.sendPhoto)", async () => {
  await seed({"threads/t1": thread("bea", "ann")});
  const bea = verified("bea");
  const path = "chats/t1/bea/5F2C0C1E-AAAA-BBBB-CCCC-0123456789AB.jpg"; // UUID().uuidString + ".jpg"
  await assertSucceeds(bea.collection("threads/t1/messages").add({...message("bea", ""), imagePath: path}));
  await assertSucceeds(bea.collection("threads/t1/messages").add({...message("bea", "look at her"), imagePath: path}));
  // what the server adds to it afterwards reads back fine
  await seed({"threads/t1/messages/m9": {...message("bea", ""), imagePath: path, imageOK: true}});
  await assertSucceeds(verified("ann", "+14155550111").collection("threads/t1/messages").orderBy("createdAt").get());
});

test("photo: in a brand-new conversation the conversation is created first, then the photo message", async () => {
  await seed({"posts/p1": post("ann")});
  const bea = verified("bea");
  await assertSucceeds(bea.doc("threads/t1").set(thread("bea", "ann")));
  await assertSucceeds(bea.collection("threads/t1/messages").add(message("system", "Started from: \"Can't sleep\"")));
  await assertSucceeds(bea.collection("threads/t1/messages").add({...message("bea", ""), imagePath: "chats/t1/bea/0A.jpg"}));
});

test("photo: Report & End names her photos in the report (AppState.reportChat)", async () => {
  await seed({"threads/t1": thread("bea", "ann")});
  const ann = verified("ann");
  await assertSucceeds(ann.doc("threads/t1").update({isManuallyFrozen: true}));
  await assertSucceeds(ann.collection("reports").add({
    type: "chat", threadId: "t1", postId: "p1", postTitle: "Can't sleep", reportedUID: "bea", reporterUID: "ann",
    reason: "Sexual or violent content", reasons: ["Sexual or violent content"], details: "",
    messages: [{text: "", at: new Date(), imagePath: "chats/t1/bea/0A.jpg"}, {text: "hey", at: new Date()}],
    createdAt: serverTimestamp(),
  }));
});
