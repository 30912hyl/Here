import FirebaseFirestore
import FirebaseMessaging
import Foundation
import UIKit
import UserNotifications

/// Owns everything push: permission, FCM token persistence, foreground
/// presentation, and routing notification taps to the right chat thread.
@MainActor
final class PushManager: NSObject, ObservableObject {
    static let shared = PushManager()

    /// Thread the user is currently viewing — banners for it are suppressed.
    var activeThreadId: String?

    /// Set when the user taps a message notification; ContentView routes to it.
    @Published var tappedThreadId: String?

    private var uid: String?
    private var pendingToken: String?

    /// Call right after FirebaseApp.configure().
    func configure() {
        UNUserNotificationCenter.current().delegate = self
        Messaging.messaging().delegate = self
    }

    /// Prompts for notification permission and registers with APNs.
    func requestPermissionAndRegister() {
        Task {
            let granted = (try? await UNUserNotificationCenter.current()
                .requestAuthorization(options: [.alert, .badge, .sound])) ?? false
            if granted {
                UIApplication.shared.registerForRemoteNotifications()
            }
        }
    }

    /// Once auth is ready, any token received earlier can be stored under the user.
    func userSignedIn(uid: String) {
        self.uid = uid
        if let token = pendingToken {
            saveToken(token)
        }
    }

    func apnsTokenReceived(_ deviceToken: Data) {
        Messaging.messaging().apnsToken = deviceToken
    }

    private func saveToken(_ token: String) {
        guard let uid, !uid.isEmpty else {
            // Token can arrive before anonymous sign-in completes
            pendingToken = token
            return
        }
        pendingToken = nil
        Firestore.firestore().collection("users").document(uid).setData([
            "fcmToken": token,
            "tokenUpdatedAt": FieldValue.serverTimestamp()
        ], merge: true)
    }
}

// MARK: - MessagingDelegate

extension PushManager: MessagingDelegate {
    nonisolated func messaging(_ messaging: Messaging, didReceiveRegistrationToken fcmToken: String?) {
        guard let fcmToken else { return }
        Task { @MainActor in
            self.saveToken(fcmToken)
        }
    }
}

// MARK: - UNUserNotificationCenterDelegate

extension PushManager: UNUserNotificationCenterDelegate {
    // Foreground: show the banner + buzz unless the user is already in that thread
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        let threadId = notification.request.content.userInfo["threadId"] as? String
        Task { @MainActor in
            if let threadId, threadId == self.activeThreadId {
                completionHandler([])
            } else {
                completionHandler([.banner, .sound, .badge])
            }
        }
    }

    // Tapping a notification opens the conversation it belongs to
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let threadId = response.notification.request.content.userInfo["threadId"] as? String
        Task { @MainActor in
            if let threadId {
                self.tappedThreadId = threadId
            }
            completionHandler()
        }
    }
}
