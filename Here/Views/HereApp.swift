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
        return true
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
                }
        }
    }
}
