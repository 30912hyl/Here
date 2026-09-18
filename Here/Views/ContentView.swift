import SwiftUI

struct ContentView: View {
    @EnvironmentObject var authService: AuthService
    
    @State private var selectedTab: MainTab = .feed
    @State private var lastNonCreateTab: MainTab = .feed
    @State private var showCreateSheet = false
    @State private var heartBeating = false
    @State private var navigateToThreadId: String? = nil
    @State private var isChatOpen = false
    @ObservedObject private var push = PushManager.shared
    @Environment(\.scenePhase) private var scenePhase

    @StateObject private var app = AppState(authService: AuthService())

    var body: some View {
        Group {
            if authService.isSignedIn {
                mainTabView
            } else {
                ProgressView("Connecting...")
            }
        }
        .onAppear {
            print("ContentView appeared, isSignedIn: \(authService.isSignedIn)")
            if authService.isSignedIn {
                app.authService = authService
                app.startListening()
            }
            KeyboardDismisser.install()
            KeyboardWarmer.warm()
            routePendingNotificationTap()
        }
        .onChange(of: authService.isSignedIn) {
            print("isSignedIn changed to: \(authService.isSignedIn)")
            if authService.isSignedIn {
                app.authService = authService
                app.startListening()
            }
        }
        .onDisappear {
            app.stopListening()
        }
        .onChange(of: push.tappedThreadId) {
            routePendingNotificationTap()
        }
        .onChange(of: scenePhase) {
            // "Open to connect" means while I'm in the app — drop out on
            // background rather than sit in the count from a pocket.
            if scenePhase != .active {
                app.voice.appDidLeaveForeground()
            }
        }
    }

    /// Jump into the conversation whose notification was tapped. Called from
    /// onChange for taps while running, and from onAppear because a tap that
    /// cold-launches the app can set tappedThreadId before this view exists —
    /// onChange alone would never see it.
    private func routePendingNotificationTap() {
        guard let threadId = push.tappedThreadId else { return }
        push.tappedThreadId = nil
        navigateToThreadId = threadId
        selectedTab = .inbox
    }

    private var mainTabView: some View {
        ZStack(alignment: .bottom) {
            // 备用底色:与 feed 底部一致的白,避免任何缝隙露出突兀的颜色
            Color.white.ignoresSafeArea()

            // 自绘标签栏,不用 TabView——iOS 26 上系统的 Liquid Glass 标签栏
            // 用 .toolbar(.hidden) 藏不干净,会在自定义 bar 后面漏出来。
            Group {
                switch selectedTab {
                case .voice:
                    VoiceView(voice: app.voice)
                case .feed, .create:
                    FeedView(
                        // Private ("just for me") posts exist in Firestore — never show them to others
                        posts: app.posts.filter {
                            (!$0.isPrivate || $0.authorUID == app.uid)
                                && !app.reportedPostIds.contains($0.id ?? "")
                        },
                        uid: app.uid,
                        onStartChat: { post in
                            // Opens a local draft — nothing exists in Firestore
                            // (or on the other phone) until a message is sent
                            if let threadId = app.startChat(from: post) {
                                navigateToThreadId = threadId
                                selectedTab = .inbox
                            }
                        },
                        onToggleLike: { post, alreadyLiked in
                            Task { await app.toggleLike(post: post, alreadyLiked: alreadyLiked) }
                        },
                        onReportPost: { post, reason, details in
                            Task { await app.reportPost(post, reason: reason, details: details) }
                        }
                    )
                case .inbox:
                    InboxView(app: app, navigateToThreadId: $navigateToThreadId, isChatOpen: $isChatOpen)
                case .profile:
                    ProfileView()
                }
            }

            // Hidden while a chat thread is open so it doesn't cover the message input
            if !isChatOpen {
            HStack(spacing: 0) {
                CustomTabItem(
                    iconDefault: "waveform",
                    iconSelected: "waveform",
                    label: "Voice",
                    tab: .voice,
                    selected: $selectedTab
                )
                CustomTabItem(
                    iconDefault: "book.closed",
                    iconSelected: "book",
                    label: "Posts",
                    tab: .feed,
                    selected: $selectedTab
                )

                Button {
                    startHeartbeat()
                    showCreateSheet = true
                } label: {
                    // 隐形占位复制邻居的图标+标签结构,圆钮以 overlay 叠上去:
                    // 居中于整项高度,且不撑高胶囊
                    VStack(spacing: 5) {
                        Color.clear.frame(height: 20)
                        Text("Posts")
                            .font(.system(size: 10, weight: .regular))
                            .tracking(0.5)
                            .hidden()
                    }
                    .frame(maxWidth: .infinity)
                    .overlay {
                        // 创建是"动作"不是"页面":圆环承担"按钮感",心本身保持和邻居同样的细线,
                        // 所以它在各页面都能融进去。纯白底——米色底在白玻璃上会显脏
                        // 两个对齐目标互相矛盾:心要对齐邻居的图标行(需上提 8.5pt),
                        // 圆要在胶囊里居中(需不提)。0 显低、6 显高,取 3 两头各让一半;
                        // 心 20pt 与邻居图标同尺寸
                        // 实心金心:细线描边会被抗锯齿稀释成卡其灰,实心才读得出"金"。
                        // 白圆下垫一层淡金投影,让它从近白的玻璃上浮起来、读得出"白"
                        ZStack {
                            Circle().fill(Color.white)
                                .overlay(Circle().stroke(Color(hex: "#D9AE52"), lineWidth: 1))
                                .frame(width: 40, height: 40)
                                .shadow(color: Color(hex: "#C9A050").opacity(0.28), radius: 3, y: 1)
                            Image(systemName: "heart.fill")
                                .font(.system(size: 19, weight: .regular))
                                .foregroundColor(Color(hex: "#D9AE52"))
                        }
                        .offset(y: -3)
                        .scaleEffect(heartBeating ? 1.25 : 1.0)
                    }
                    .contentShape(Rectangle())
                }

                CustomTabItem(
                    iconDefault: "envelope",
                    iconSelected: "envelope.open",
                    label: "Chats",
                    tab: .inbox,
                    selected: $selectedTab,
                    badge: app.unreadThreadCount
                )
                CustomTabItem(
                    iconDefault: "person.icloud",
                    iconSelected: "figure.mixed.cardio",
                    label: "Profile",
                    tab: .profile,
                    selected: $selectedTab
                )
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .glassTabBar()
            .padding(.horizontal, 14)
            .padding(.bottom, 6)
            .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .fullScreenCover(isPresented: $showCreateSheet) {
            CreatePostView(onSubmit: { title, bodyText, images, tags, isPrivate in
                await app.addPost(title: title, bodyText: bodyText, images: images, tags: tags, isPrivate: isPrivate)
            })
        }
    }

    func startHeartbeat() {
        let beats: [Double] = [0, 0.15, 0.3, 0.45]
        for (i, delay) in beats.enumerated() {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                withAnimation(.spring(response: 0.15, dampingFraction: 0.35)) {
                    heartBeating = i % 2 == 0
                }
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.55) {
            withAnimation(.spring(response: 0.2, dampingFraction: 0.6)) {
                heartBeating = false
            }
        }
    }

    var goldGradient: LinearGradient {
        LinearGradient(
            colors: [Color(hex: "#D9AE52")],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
}

// MARK: - Tab Item
struct CustomTabItem: View {
    let iconDefault: String
    let iconSelected: String
    let label: String
    let tab: MainTab
    @Binding var selected: MainTab
    var badge: Int = 0

    var isSelected: Bool { selected == tab }

    var goldGradient: LinearGradient {
        LinearGradient(
            colors: [Color(hex: "#D9AE52")],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    var dimGoldGradient: LinearGradient {
        LinearGradient(
            colors: [Color(hex: "#D4C5A0")],
            startPoint: .top,
            endPoint: .bottom
        )
    }

    var body: some View {
        Button { selected = tab } label: {
            VStack(spacing: 5) {
                Image(systemName: isSelected ? iconSelected : iconDefault)
                    .font(.system(size: 20, weight: .light))
                    .foregroundStyle(isSelected ? goldGradient : dimGoldGradient)
                    .overlay(alignment: .topTrailing) {
                        if badge > 0 {
                            Text(badge > 99 ? "99+" : "\(badge)")
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundColor(.white)
                                .padding(.horizontal, 5)
                                .padding(.vertical, 2)
                                .background(Capsule().fill(goldGradient))
                                .offset(x: 12, y: -8)
                        }
                    }

                Text(label)
                    .font(.system(size: 10, weight: .regular))
                    .tracking(0.5)
                    .foregroundStyle(isSelected ? goldGradient : dimGoldGradient)
            }
            .frame(maxWidth: .infinity)
        }
        .animation(.easeInOut(duration: 0.2), value: isSelected)
    }
}

// MARK: - Glass Tab Bar
extension View {
    /// Liquid Glass on iOS 26+, frosted capsule fallback on earlier versions.
    @ViewBuilder
    func glassTabBar() -> some View {
        // glassEffect only exists in the iOS 26 SDK — older toolchains (Xcode 16)
        // can't compile the call even behind #available, so gate on compiler too.
        #if compiler(>=6.2)
        if #available(iOS 26.0, *) {
            self.glassEffect(.regular, in: Capsule())
        } else {
            self
                .background(.ultraThinMaterial, in: Capsule())
                .overlay(Capsule().stroke(.white.opacity(0.4), lineWidth: 0.5))
        }
        #else
        self
            .background(.ultraThinMaterial, in: Capsule())
            .overlay(Capsule().stroke(.white.opacity(0.4), lineWidth: 0.5))
        #endif
    }
}

// MARK: - Keyboard Dismisser
// Window-level tap so any tap outside a text field collapses the keyboard,
// including inside fullScreenCover sheets like CreatePostView.
private final class KeyboardDismisser: NSObject, UIGestureRecognizerDelegate {
    static let shared = KeyboardDismisser()

    private static var isInstalled = false

    static func install() {
        guard !isInstalled else { return }
        guard let window = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .flatMap({ $0.windows })
            .first(where: { $0.isKeyWindow }) else { return }
        let tap = UITapGestureRecognizer(target: shared, action: #selector(dismiss))
        tap.cancelsTouchesInView = false
        tap.delegate = shared
        window.addGestureRecognizer(tap)
        isInstalled = true
    }

    @objc private func dismiss() {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }

    // Only fire when a text input is already focused AND the tap lands outside it.
    // Receiving the focusing tap itself races the keyboard opening, which made
    // text fields need several taps before the keyboard appeared.
    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        guard let responderView = UIResponder.currentFirst as? UIView else { return false }
        let location = touch.location(in: responderView)
        return !responderView.bounds.insetBy(dx: -8, dy: -8).contains(location)
    }
}

// MARK: - Keyboard Warmer
// iOS initializes the keyboard process lazily on the first focus of a session,
// which makes the first real text-field tap feel slow and the first keystrokes
// lag. Focusing and immediately resigning an offscreen field at launch pays
// that cost up front, before the user ever taps a field.
private enum KeyboardWarmer {
    static func warm() {
        guard let window = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .flatMap({ $0.windows })
            .first(where: { $0.isKeyWindow }) else { return }
        let field = UITextField(frame: CGRect(x: -100, y: -100, width: 10, height: 10))
        window.addSubview(field)
        field.becomeFirstResponder()
        field.resignFirstResponder()
        field.removeFromSuperview()
    }
}

extension UIResponder {
    private static weak var _currentFirst: UIResponder?

    /// The current first responder, found via the responder-chain action trick.
    static var currentFirst: UIResponder? {
        _currentFirst = nil
        UIApplication.shared.sendAction(#selector(captureFirst), to: nil, from: nil, for: nil)
        return _currentFirst
    }

    @objc private func captureFirst() {
        UIResponder._currentFirst = self
    }
}

// MARK: - Hex Color
extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let r = Double((int >> 16) & 0xFF) / 255
        let g = Double((int >> 8) & 0xFF) / 255
        let b = Double(int & 0xFF) / 255
        self.init(red: r, green: g, blue: b)
    }
}

#Preview {
    ContentView()
        .environmentObject(AuthService())
}
