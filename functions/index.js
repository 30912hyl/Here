const {onDocumentCreated} = require("firebase-functions/v2/firestore");
const admin = require("firebase-admin");

admin.initializeApp();

/**
 * Sends a push notification to the other participant whenever a new chat
 * message is written. Also bumps their server-side unread counter so the
 * app-icon badge number on the push is roughly right even while the app
 * is closed (the client rewrites the exact total whenever it's opened or
 * a thread is read).
 */
exports.notifyNewMessage = onDocumentCreated(
    "threads/{threadId}/messages/{messageId}",
    async (event) => {
      const message = event.data && event.data.data();
      if (!message || message.senderUID === "system") return;

      const {threadId} = event.params;
      const db = admin.firestore();

      const threadSnap = await db.doc(`threads/${threadId}`).get();
      if (!threadSnap.exists) return;
      const thread = threadSnap.data();

      const recipient = (thread.participants || [])
          .find((p) => p !== message.senderUID);
      if (!recipient) return;

      const userRef = db.doc(`users/${recipient}`);
      const userSnap = await userRef.get();
      const user = userSnap.exists ? userSnap.data() : {};

      // Badge counts unread CONVERSATIONS (like iMessage), so only bump it
      // when this thread flips from read to unread — i.e. the new message is
      // the only unread one from the other participant.
      //
      // Known race: two near-simultaneous messages can each see themselves as
      // the first unread one and double-bump the badge. Accepted — the client
      // rewrites the exact count whenever the recipient opens the app, so any
      // drift is short-lived and cosmetic (badge number on the lock screen).
      const lastRead = (thread.lastRead || {})[recipient];
      let recentQuery = db.collection(`threads/${threadId}/messages`)
          .orderBy("createdAt", "desc")
          .limit(10);
      if (lastRead) {
        recentQuery = recentQuery.where("createdAt", ">", lastRead);
      }
      const recent = await recentQuery.get();
      const unreadFromOther = recent.docs
          .filter((d) => d.data().senderUID === message.senderUID).length;
      const threadWasAlreadyUnread = unreadFromOther > 1;

      let unreadTotal = user.unreadTotal || 0;
      if (!threadWasAlreadyUnread) {
        unreadTotal += 1;
        await userRef.set({unreadTotal}, {merge: true});
      }

      if (!user.fcmToken) return;

      try {
        await admin.messaging().send({
          token: user.fcmToken,
          notification: {
            title: thread.nickname || "New message",
            body: message.text || "sent you a message",
          },
          apns: {
            payload: {
              aps: {
                badge: unreadTotal,
                sound: "default",
              },
            },
          },
          data: {threadId},
        });
      } catch (err) {
        // Token expired/uninstalled — drop it so we stop retrying
        if (err.code === "messaging/registration-token-not-registered") {
          await userRef.set({fcmToken: admin.firestore.FieldValue.delete()},
              {merge: true});
        } else {
          console.error("push send failed", err);
        }
      }
    });
