//
//  HereApp.swift
//  Here
//
//  Created by yuchen on 1/27/26.
//
import SwiftUI
import FirebaseAuth
import FirebaseCore

class AppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        BrandFont.register()
        // Nothing the app draws is pure black: navigation titles take the ink too
        // (SwiftUI's own default text colour is set on the root view below).
        UINavigationBar.appearance().titleTextAttributes = [.foregroundColor: Theme.inkUIColor]
        UINavigationBar.appearance().largeTitleTextAttributes = [.foregroundColor: Theme.inkUIColor]
        FirebaseApp.configure()
        #if targetEnvironment(simulator)
        // 只在模拟器里：用 Firebase 后台登记的“测试号码”登录时，跳过“我不是机器人”那一步。
        // 模拟器收不到苹果的静默推送，不加这一行会弹一个网页验证，而且这台 Mac 的包名
        // （在 Configs/Local.xcconfig 里，不进 git）和 GoogleService-Info.plist 里登记的不是同一个，网页那一步可能过不去。
        // 开了以后，模拟器里只有测试号码能登录（真号码会报错）；真机上没有这一行，照常验证。
        // 依据：Firebase 文档 “Test with fictional phone numbers”。老板 2026-11-26 00:08 要我用两个测试号自己测。
        Auth.auth().settings?.isAppVerificationDisabledForTesting = true
        #endif
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

    /// 手机号验证要用到。Firebase 在发验证码之前，会先给 app 自己发一条“假的静默推送”，
    /// 看 app 会不会把收到的推送交给它：交不到就直接报错，一条验证码都不发。
    /// 真机上它还靠一条真的静默推送来确认“这是一台真的手机、装的是我们的 app”。
    /// 没有这个方法，手机号验证在任何一台手机上都过不了——
    /// 2026-11-26 用测试号第一次真测时发现（控制台 I-AUT000015，界面上只有 “Something went wrong”）。
    /// 不属于 Firebase 的推送这里什么都不做；通知的显示和点按在 PushManager 里。
    func application(
        _ application: UIApplication,
        didReceiveRemoteNotification userInfo: [AnyHashable: Any],
        fetchCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void
    ) {
        _ = Auth.auth().canHandleNotification(userInfo)
        completionHandler(.noData)
    }
}

@main
struct HereApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var delegate
    @StateObject private var authService = AuthService()
    /// Answer to "Are you a woman?" on this phone (see WomenGateView).
    @AppStorage("womenGateAnswer") private var womenGateAnswer = ""
    /// The name shows on its own for a moment each time the app opens.
    @State private var showBrand = true

    var body: some Scene {
        WindowGroup {
            ZStack {
            Group {
                // Nothing else starts — no sign-in, no feed download, no push
                // prompt — until the person has said yes.
                if womenGateAnswer == WomenGateView.Answer.confirmed.rawValue {
                    ContentView()
                        .environmentObject(authService)
                        // Phone sign-in's reCAPTCHA fallback returns through the
                        // app's URL scheme; hand that URL to Firebase Auth.
                        .onOpenURL { url in
                            _ = Auth.auth().canHandle(url)
                        }
                        .task {
                            await authService.signInAnonymously()
                            if let uid = authService.uid {
                                PushManager.shared.userSignedIn(uid: uid)
                            }
                            PushManager.shared.requestPermissionAndRegister()
                        }
                } else {
                    WomenGateView(answer: $womenGateAnswer)
                }
            }

            // People who already said yes see the name for a moment, then the feed.
            // (A first-time visitor gets the same screen from WomenGateView, before
            // the question.) The light behind it is the feed's own light, so the
            // hand-over is only the logo fading.
            if showBrand && womenGateAnswer == WomenGateView.Answer.confirmed.rawValue {
                BrandScreen()
                    .transition(.opacity)
                    .zIndex(1)
            }
            }
            .task {
                try? await Task.sleep(nanoseconds: 1_500_000_000)
                withAnimation(.easeInOut(duration: 0.6)) {
                    showBrand = false
                }
            }
            // Default colour of any text or symbol that doesn't set its own:
            // the ink, never black.
            .foregroundStyle(Theme.ink)
            // The design is light-only (hardcoded white cards / gold text);
            // dark mode made default-colored text invisible
            .preferredColorScheme(.light)
        }
    }
}
