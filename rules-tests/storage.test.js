"use strict";

/**
 * Tests for ../storage.rules. They need the Storage and Firestore emulators
 * together, because the rules for conversation photos read the conversation
 * from Firestore:
 *   cd rules-tests && npm ci && npm test
 *
 * Each test states one thing a person can or cannot do with a file.
 */

const {test, before, after, beforeEach} = require("node:test");
const fs = require("node:fs");
const path = require("node:path");
const {initializeTestEnvironment, assertSucceeds, assertFails} = require("@firebase/rules-unit-testing");
require("firebase/compat/firestore");
require("firebase/compat/storage");

const HOUR = 3600 * 1000;
const rulesFile = (name) => fs.readFileSync(path.join(__dirname, "..", name), "utf8");

/** @type {import("@firebase/rules-unit-testing").RulesTestEnvironment} */
let env;

before(async () => {
  env = await initializeTestEnvironment({
    // The Storage emulator looks conversations up in the Firestore data of
    // the project the emulators were started for (--project demo-here in
    // package.json), so this file has to use that one. firestore.test.js
    // uses it too; the test files run one at a time (--test-concurrency=1)
    // so they cannot clear each other's data.
    projectId: "demo-here",
    firestore: {rules: rulesFile("firestore.rules")},
    storage: {rules: rulesFile("storage.rules")},
  });
});
after(async () => {
  await env.cleanup();
});
beforeEach(async () => {
  await env.clearFirestore();
});

// ---------------------------------------------------------------- helpers

const verified = (uid, phone = "+14155550100") => env.authenticatedContext(uid, {phone_number: phone}).storage();
const anonymous = (uid) => env.authenticatedContext(uid).storage();
const signedOut = () => env.unauthenticatedContext().storage();

const inHours = (h) => new Date(Date.now() + h * HOUR);
const JPEG = {contentType: "image/jpeg"};
/** A few bytes standing in for a photo; the rules look at type and size, not at the picture. */
const bytes = (n = 64) => new Uint8Array(n).fill(7);

/** `storage.ref(path).put(...)` as a promise the assert helpers accept. */
const upload = (storage, p, data = bytes(), meta = JPEG) => storage.ref(p).put(data, meta).then(() => true);
const download = (storage, p) => storage.ref(p).getMetadata();

const thread = (a, b, over = {}) => ({
  participants: [a, b], createdAt: new Date(), expiresAt: inHours(48), isManuallyFrozen: false, ...over,
});

/**
 * A name nothing has used before. Files are never cleared between tests
 * (the emulator's reset does not remove them), and a file that already
 * exists cannot be uploaded again, so every test works in a conversation
 * or folder of its own.
 */
let counter = 0;
const fresh = (prefix = "t") => `${prefix}${Date.now().toString(36)}${++counter}`;

async function seed({docs = {}, files = []} = {}) {
  await env.withSecurityRulesDisabled(async (ctx) => {
    for (const [p, data] of Object.entries(docs)) await ctx.firestore().doc(p).set(data);
    for (const p of files) await ctx.storage().ref(p).put(bytes(), JPEG);
  });
}

// ---------------------------------------------------------------- post photos

test("post photo: the owner uploads a JPEG into her own folder; anyone signed in can view it", async () => {
  const f = fresh("F");
  await assertSucceeds(upload(verified("ann"), `posts/ann/${f}/0_a.jpg`));
  await assertSucceeds(download(anonymous("guest"), `posts/ann/${f}/0_a.jpg`));
  await assertFails(download(signedOut(), `posts/ann/${f}/0_a.jpg`));
});

test("post photo: not into someone else's folder, not without a phone number, not another format, not replaced", async () => {
  const f = fresh("F");
  await assertFails(upload(verified("ann"), `posts/bea/${f}/0_a.jpg`));
  await assertFails(upload(anonymous("ann"), `posts/ann/${f}/0_a.jpg`));
  await assertFails(upload(verified("ann"), `posts/ann/${f}/0_a.png`, bytes(), {contentType: "image/png"}));
  await assertSucceeds(upload(verified("ann"), `posts/ann/${f}/0_a.jpg`));
  await assertFails(upload(verified("ann"), `posts/ann/${f}/0_a.jpg`));
});

// ---------------------------------------------------------------- conversation photos

test("chat photo: a participant uploads into her own folder of the conversation", async () => {
  const t = fresh();
  await seed({docs: {[`threads/${t}`]: thread("ann", "bea")}});
  await assertSucceeds(upload(verified("ann"), `chats/${t}/ann/p1.jpg`));
  await assertSucceeds(upload(verified("bea"), `chats/${t}/bea/p-2_b.jpg`));
});

test("chat photo: only the two people in the conversation can view it", async () => {
  const t = fresh();
  await seed({docs: {[`threads/${t}`]: thread("ann", "bea")}, files: [`chats/${t}/ann/p1.jpg`]});
  await assertSucceeds(download(verified("ann"), `chats/${t}/ann/p1.jpg`));
  await assertSucceeds(download(verified("bea"), `chats/${t}/ann/p1.jpg`));
  await assertFails(download(verified("cat"), `chats/${t}/ann/p1.jpg`));
  await assertFails(download(anonymous("guest"), `chats/${t}/ann/p1.jpg`));
  await assertFails(download(signedOut(), `chats/${t}/ann/p1.jpg`));
});

test("chat photo: still viewable by the two after the conversation ended (until the server deletes it)", async () => {
  const t = fresh();
  await seed({docs: {[`threads/${t}`]: thread("ann", "bea", {isManuallyFrozen: true})}, files: [`chats/${t}/ann/p1.jpg`]});
  await assertSucceeds(download(verified("bea"), `chats/${t}/ann/p1.jpg`));
});

test("chat photo: an outsider cannot upload into a conversation, and nobody into the other person's folder", async () => {
  const t = fresh();
  await seed({docs: {[`threads/${t}`]: thread("ann", "bea")}});
  await assertFails(upload(verified("cat"), `chats/${t}/cat/p1.jpg`));
  await assertFails(upload(verified("ann"), `chats/${t}/bea/p1.jpg`));
  await assertFails(upload(verified("ann"), `chats/${fresh("nope")}/ann/p1.jpg`)); // no such conversation
});

test("chat photo: not into a conversation that was ended or ran out", async () => {
  const ended = fresh();
  const over = fresh();
  await seed({docs: {
    [`threads/${ended}`]: thread("ann", "bea", {isManuallyFrozen: true}),
    [`threads/${over}`]: thread("ann", "bea", {expiresAt: inHours(-1)}),
  }});
  await assertFails(upload(verified("ann"), `chats/${ended}/ann/p1.jpg`));
  await assertFails(upload(verified("ann"), `chats/${over}/ann/p1.jpg`));
});

test("chat photo: JPEG only, under 10 MB, a plain file name, and a verified phone number", async () => {
  const t = fresh();
  await seed({docs: {[`threads/${t}`]: thread("ann", "bea")}});
  await assertFails(upload(verified("ann"), `chats/${t}/ann/p1.png`, bytes(), {contentType: "image/png"}));
  await assertFails(upload(verified("ann"), `chats/${t}/ann/p1.jpg`, bytes(), {contentType: "text/html"}));
  await assertFails(upload(verified("ann"), `chats/${t}/ann/p1.gif`, bytes(), JPEG));
  await assertFails(upload(verified("ann"), `chats/${t}/ann/sub/p1.jpg`));
  await assertFails(upload(verified("ann"), `chats/${t}/ann/big.jpg`, bytes(10 * 1024 * 1024)));
  await assertFails(upload(anonymous("ann"), `chats/${t}/ann/p1.jpg`));
  // and after all those refusals the ordinary one still goes through
  await assertSucceeds(upload(verified("ann"), `chats/${t}/ann/p1.jpg`));
});

test("chat photo: created once, never replaced; the sender can take hers back, the other person cannot", async () => {
  const t = fresh();
  await seed({docs: {[`threads/${t}`]: thread("ann", "bea")}});
  await assertSucceeds(upload(verified("ann"), `chats/${t}/ann/p1.jpg`));
  await assertFails(upload(verified("ann"), `chats/${t}/ann/p1.jpg`));
  await assertFails(verified("bea").ref(`chats/${t}/ann/p1.jpg`).delete());
  await assertSucceeds(verified("ann").ref(`chats/${t}/ann/p1.jpg`).delete());
});

test("chat photo: the switch in config turns uploads off; a config that does not mention photos leaves them on", async () => {
  const t = fresh();
  await seed({docs: {[`threads/${t}`]: thread("ann", "bea"), "config/app": {chatPhotos: false}}});
  await assertFails(upload(verified("ann"), `chats/${t}/ann/p1.jpg`));
  await seed({docs: {"config/app": {founderUID: "fay"}}});
  await assertSucceeds(upload(verified("ann"), `chats/${t}/ann/p1.jpg`));
});

test("chat photo: the conversation with the founder works the same way", async () => {
  const t = fresh("founder_");
  await seed({docs: {[`threads/${t}`]: thread("ann", "fay", {kind: "founder", expiresAt: new Date(Date.UTC(2100, 0, 1))})}});
  await assertSucceeds(upload(verified("fay"), `chats/${t}/fay/dog.jpg`));
  await assertSucceeds(download(verified("ann"), `chats/${t}/fay/dog.jpg`));
  await assertFails(download(verified("bea"), `chats/${t}/fay/dog.jpg`));
});

// ---------------------------------------------------------------- everything else

test("nothing else in the bucket can be read or written from a phone", async () => {
  const r = fresh("r");
  await seed({files: [`reportEvidence/${r}/p1.jpg`, `other/${r}.jpg`]});
  await assertFails(download(verified("ann"), `reportEvidence/${r}/p1.jpg`));
  await assertFails(upload(verified("ann"), `reportEvidence/${r}/p2.jpg`));
  await assertFails(download(verified("ann"), `other/${r}.jpg`));
  await assertFails(upload(verified("ann"), `chats/${r}/p1.jpg`)); // not deep enough to match
});
