//
//  HereApp.swift
//  Here
//
//  Created by yuchen on 1/27/26.
//
import SwiftUI
import FirebaseCore

class AppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        FirebaseApp.configure()
        PushManager.shared.configure()
        return true
    }

    func application(
        _ application: UIApplication,
        didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
    ) {
        PushManager.shared.apnsTokenReceived(deviceToken)
    }

    func application(
        _ application: UIApplication,
        didFailToRegisterForRemoteNotificationsWithError error: Error
    ) {
        // Expected on the simulator; harmless there
        print("APNs registration failed: \(error.localizedDescription)")
    }
}

@main
struct HereApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var delegate
    @StateObject private var authService = AuthService()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(authService)
                // The design is light-only (hardcoded white cards / gold text);
                // dark mode made default-colored text invisible
                .preferredColorScheme(.light)
                .task {
                    await authService.signInAnonymously()
                    if let uid = authService.uid {
                        PushManager.shared.userSignedIn(uid: uid)
                    }
                    PushManager.shared.requestPermissionAndRegister()
                }
        }
    }
}
