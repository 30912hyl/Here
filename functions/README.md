# Here — server side

Everything in this folder runs on Firebase, not on the phone. The app already
checks most of this itself; the server repeats the checks so that a modified
app cannot skip them, and does the things only a server can do.

## What runs, and when

| Function | Runs when | What it does |
|---|---|---|
| `onPostCreated` | a post is written | Limits posts per person (6 an hour, 20 a day). Checks every photo URL points at the author's own folder in our bucket. For public posts: removes posts containing slurs, and runs each photo through Cloud Vision SafeSearch (explicit or graphic photos are deleted and the post removed; borderline ones, and files it cannot read, are reported to moderators and stay up). |
| `onMessageCreated` | a private message is written | Limits messages per sender (40 a minute). Deletes harassment, sexual requests and slurs. If the message carries a photo: checks the file is the sender's own for that conversation, limits photos per sender (30 a day), and runs it through Cloud Vision SafeSearch (see "Photos in conversations" below). Then sends the push notification and updates the badge. |
| `onThreadCreated` | a conversation is opened | Limits new conversations per person (20 an hour). For the conversation with the founder: writes her welcome into it as its first messages. |
| `onRetentionSweep` | every hour | Deletes a conversation whole (messages, photos, the conversation itself) `keepEndedDays` days after it is over for good. Writes the date on it first (`deleteAfter`), so the app can say how many days are left. |
| `onTimeUpSweep` | every 5 minutes | Finds conversations whose 48 hours have just run out and tells both people, once, that it is time to decide ("talk for another 48 hours?"). Not for conversations that were ended, that already had their one extension, or where one has blocked the other; not to someone who has already answered. Marks the conversation with `timeUpPushAt`. |
| `onReportCreated` | a report is filed | Tells the moderators. After 3 different people with a verified phone number report the same post for breaking a rule, it leaves the feed until someone reviews it. "Something feels off" is the reason for when no rule fits: those reports reach the moderators like any other but only hide a post once 10 different people have reported it for any reason. (Accounts without a number cost nothing to create, so they do not count.) For a reported conversation: copies the photos the other person sent to `reportEvidence/{reportId}/` in Storage, where only the console can see them. |
| `onBanCreated` | a number is added to `bannedPhones` | Takes that person's posts out of the feed, ends her conversations, stops her pushes. |
| `onUserDocDeleted` | a document in `users` is deleted | Safety net for "Delete Account": deletes any post or photo the phone did not manage to delete, ends her conversations and deletes the photos she sent in them. |

"Removed" never means deleted: the post's expiry is moved to now, so it leaves
every feed at once and stays visible to moderators (and in its author's
archive). Every automatic action is recorded in the `modLog` collection.

To put a removed post back: open it in the Firebase console, copy
`removed.expiresAtWas` into `expiresAt`, and delete the `removed` field.
(A photo that was deleted for being explicit cannot be brought back.)

Careful: deleting someone's document in `users` by hand deletes her posts and
photos too. That is what the app does when an account is deleted.

"Just for me" posts are shown to nobody else and are not moderated.

The answer to "talk for another 48 hours?" is open for 24 hours after a
conversation runs out. The app counts those hours down; `firestore.rules`
(`isTheOneExtension`) is what actually refuses an extension after that.

The words of the "time's up" notification are in one place,
`TIME_UP_PUSH` in `lib/handlers.js`. They are a placeholder made of words the
app already shows, and have not been approved yet. The same goes for
`PHOTO_PUSH_BODY` ("sent a photo"), what a notification says for a photo
without words.

## Photos in conversations

Anyone can send a photo in a conversation. The file goes to Storage at
`chats/{conversation}/{senderUid}/{name}.jpg`, and the message stores that
path in `imagePath`. `storage.rules` lets only the two people in the
conversation read anything under `chats/{conversation}/`.

- **Checked before it is shown.** `onMessageCreated` checks each photo. When
  it passes, the message is marked `imageOK: true`; the other person's phone
  shows a photo only once that mark is there. An explicit photo is deleted and never shown;
  its message stays, marked `imageRemoved`, and both phones show the same
  line where the photo would be. So is a file the check cannot read (for a
  post such a file stays up for a moderator; in a private conversation
  nobody else would ever look at it). Borderline photos are
  delivered and a moderator is told. `imageModeration` (below) applies here
  too: `log` records and reports but removes nothing, `off` skips the check.
- **Limit.** 30 photos per person per day (`limits.photosPerDay`).
- **Switch.** `config/app.chatPhotos: false` turns photos off for everyone at
  once: the rules then refuse both the upload and the message.
- **Kept exactly as long as the conversation.** Photos are never deleted
  ahead of their conversation. A conversation that is over for good — ended
  by either person, or out of time with no way left to extend it (the 24
  hours to answer "another 48 hours?" have passed, or the second 48 hours ran
  out) — is deleted whole `keepEndedDays` days later (7 unless
  `settings/moderation` says otherwise; `0` keeps everything): its messages,
  its photos and the conversation itself, for both people. `onRetentionSweep`
  first writes the date on the conversation (`deleteAfter`): for a
  conversation that ran out, the days count from the moment it could no
  longer be continued; for one ended by hand, from the first run that sees it
  (at most an hour later).
- **Reports.** A report on a conversation copies the other person's photos to
  `reportEvidence/{reportId}/`. Nothing deletes that folder automatically:
  how long to keep it is still to be decided, and until then it is deleted
  by hand in the console once a report is closed.
- **Account deletion and bans** end the person's conversations, so their
  photos go the same way; the deleted person's own photos go at once.

## The conversation with the founder

One conversation does not start from a post: the one each person can have
with the founder. Who the founder is comes from `config/app.founderUID`, so
no other account can pass itself off as her.

- The person opens it herself with her first reply; the founder cannot start
  one. It always has the id `founder_{her uid}`, so there is one per person.
- It has `kind: "founder"`, no `postId`, and no 48 hours: `expiresAt` is one
  fixed far-away date (1 January 2100) unless `config/app.founderThreadHours`
  says how long it should last.
- `onThreadCreated` writes `config/app.founderWelcome` into it, one message
  per entry, marked `auto: true` and dated just before the conversation
  began. Those messages count against nobody and notify nobody.
- On the other person's phone her notifications carry
  `config/app.founderNickname`; on the founder's own phone each conversation
  keeps its random name, like every other conversation.
- Blocking, reporting, the message limits and the photo rules apply to it
  like to any conversation.

Known limit: the founder's phone loads every one of her conversations, like
anyone's does. That is fine for a first few hundred; beyond that the app's
conversation list needs paging before her account can keep up.

## Settings

Two documents in Firestore, both edited in the Firebase console only.

`config/app` is what every phone needs to know. The app can read it; nothing
private belongs in it. Every field is optional.

| Field | Meaning | Default |
|---|---|---|
| `founderUID` | the founder's account (her uid). Without it there is no conversation with the founder | none |
| `founderNickname` | the name people see on that conversation and on her notifications | none |
| `founderWelcome` | what she says first: a list, one message per entry (at most 10, 2000 characters each) | none |
| `founderThreadHours` | how long that conversation lasts; `0` = it never runs out | `0` |
| `chatPhotos` | `false` switches photos in conversations off for everyone | on |

`settings/moderation` is private: no phone can read it. Every field is
optional.

| Field | Meaning | Default |
|---|---|---|
| `adminUIDs` | accounts that get a push for every report and automatic removal | none |
| `notifyEmails` | addresses that get an email instead (needs the Trigger Email extension) | none |
| `autoHideReports` | reports from different people, each naming a broken rule, that hide a post; `0` turns it off. "Something feels off" reports do not count here | `3` |
| `keepEndedDays` | days a conversation is kept after it is over for good, before it is deleted with its messages and photos; `0` never deletes | `7` |
| `autoHideSoftReports` | different people reporting a post for any reason at all, "Something feels off" included, that hide it; `0` turns it off | `10` |
| `imageModeration` | photo checks: `enforce`, `log` (record and report, remove nothing) or `off` | `enforce` |
| `limits` | `postsPerHour`, `postsPerDay`, `threadsPerHour`, `messagesPerMinute`, `photosPerDay`, `reportsPerHour` | 6, 20, 20, 40, 30, 20 |
| `requireApproval` | emergency switch read by `firestore.rules`: only numbers in `approvedPhones` can write | `false` |

A report can name several reasons at once. The app writes them as a list,
`reasons`, and again as one line of text, `reason`, which is what the
moderators' notification shows. A report counts as "Something feels off"
only when that is the only reason ticked.

To ban someone: add a document to `bannedPhones` whose ID is the phone number
(for example `+14155550123`). The security rules block that number at once;
`onBanCreated` cleans up what is already posted.

## Layout

- `index.js` — connects Firestore events to the handlers.
- `lib/handlers.js` — the decisions. No Firebase calls, fully unit-tested.
- `lib/store.js` — the only file that talks to Firebase.
- `lib/textFilter.js` — server copy of `Here/Services/ContentFilter.swift`. Keep the two lists in step.
- `lib/images.js`, `lib/rateLimit.js`, `lib/settings.js` — small pure helpers.
- `test/` — `npm test` (no Firebase needed).

Security rules live at the repository root. Both `firestore.rules` and
`storage.rules` have tests in `rules-tests/`. They need the Firestore and
Storage emulators together (`cd rules-tests && npm ci && npm test`), because
the rules for conversation photos look the conversation up in Firestore.

Three rules exist for the photo check's sake: a post's photo URLs must point
into the author's own folder of this project's bucket; a photo message's path
must point into the sender's own folder of that conversation; and a stored
photo can be created but never overwritten (otherwise it could be swapped
after it was checked).

## Deploying

**Order matters.** The rules only answer the feed query that asks for public
posts, and that query needs the `posts(isPrivate, expiresAt)` index from
`firestore.indexes.json`. Deploy the indexes first, wait until they are
READY, and only then deploy `firestore.rules`. With the rules live and the
index missing or still building, the app's feed is empty.

The workflow currently in `.github/workflows/firebase-deploy.yml` does NOT do
this: it deploys the rules without the indexes and runs no tests. An updated
`firebase-deploy.yml` and a new `backend-tests.yml` (tests, then indexes,
then rules once the indexes are ready, then functions, then the site) were
written together with this code but are not in the repository yet. Until
they are, do not let this code reach `main` unless the index already exists.

**Storage rules need one permission granted once.** `storage.rules` reads
conversations from Firestore ("cross-service rules"). For that, the project's
Storage service account
(`service-<project number>@gcp-sa-firebasestorage.iam.gserviceaccount.com`)
needs the role `roles/firebaserules.firestoreServiceAgent`. Running
`firebase deploy --only storage` by hand in a terminal asks "Grant the new
role?" and does it. A deploy from GitHub Actions does not ask and does not
grant it (the Firebase CLI skips that step when nobody can answer), so
either deploy the storage rules by hand once, or grant the role in the Google
Cloud console (IAM). Without it, nobody can view or send a photo in a
conversation; everything else keeps working.

Functions are only deployed when the repository variable `DEPLOY_FUNCTIONS`
is `true`, and need:

- the Blaze plan;
- the Cloud Functions, Cloud Build, Artifact Registry and Eventarc APIs;
- the Cloud Scheduler API, for `onTimeUpSweep` and `onRetentionSweep` (the first
  deploy turns it on);
- the Cloud Vision API for photo checks (without it photos are left alone,
  and a photo in a conversation is delivered unchecked).

Before the first photo is sent in a conversation, the functions have to be
live: it is `onMessageCreated` that marks a photo as checked, and the app
does not show the other person a photo without that mark.

The first time functions are deployed, set `imageModeration` to `log`, post
one photo from a phone, and check `modLog` and the function logs: the photo
should be recognised as the author's own and checked without complaint. Then
switch to `enforce`.

Deploying these rules makes old test builds of the app show an empty feed:
they ask for every post, and the rules now only answer the feed query that
asks for public posts.

## Answering a report (Here's own messages)

Everyone who reports something gets a line from Here in her Chats, in a
conversation of her own (`threads/system_<uid>`, kind `system`): only Here
speaks in it, it never ends, and no phone can create it or write in it.

- **When the report arrives** (`onReportCreated`): "We got your report about
  the post “…”. Thank you for telling us. We look at every report within 24
  hours." A report that was set aside for coming in bulk is not answered.
- **When you have looked at it** (`onReportUpdated`): open the report in the
  Firebase console (Firestore → `reports` → the report) and add the field
  `outcome` (string). She is told once; `outcomeNotified` is written back.

| `outcome` | what she is told |
| --- | --- |
| `removed` on a reported **post** | "We looked into your report about “…” and removed the post. Thank you for looking out for everyone here." |
| anything else (`banned`, `none`, a reported conversation) | nothing yet: those sentences are not approved (see `outcomeNotice` in `lib/handlers.js`) |

These lines are marked `auto`, like the founder's welcome: no push, no badge.
Deleting an account deletes this conversation with it.

The app has to know `kind == "system"` before these functions go live:
an older build shows it as an ordinary conversation, with a countdown.
