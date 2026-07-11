import SwiftUI

struct ContentView: View {
    @EnvironmentObject var authService: AuthService
    
    @State private var selectedTab: MainTab = .feed
    @State private var lastNonCreateTab: MainTab = .feed
    @State private var showCreateSheet = false
    @State private var heartBeating = false
    @State private var navigateToThreadId: String? = nil

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
                    VoiceView()
                case .feed, .create:
                    FeedView(
                        // Private ("just for me") posts exist in Firestore — never show them to others
                        posts: app.posts.filter { !$0.isPrivate || $0.authorUID == app.uid },
                        uid: app.uid,
                        onStartChat: { post in
                            Task {
                                if let threadId = await app.createThreadFromPost(post) {
                                    navigateToThreadId = threadId
                                    selectedTab = .inbox
                                }
                            }
                        },
                        onToggleLike: { post, alreadyLiked in
                            Task { await app.toggleLike(post: post, alreadyLiked: alreadyLiked) }
                        }
                    )
                case .inbox:
                    InboxView(app: app, navigateToThreadId: $navigateToThreadId)
                case .profile:
                    ProfileView()
                }
            }

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
                    ZStack {
                        // 乳白内里 + 流动金边
                        Image(systemName: "heart.fill")
                            .font(.system(size: 44, weight: .thin))
                            .foregroundStyle(GoldShimmer.milk)
                        Image(systemName: "heart")
                            .font(.system(size: 44, weight: .regular))
                            .foregroundStyle(
                                AngularGradient(
                                    gradient: Gradient(colors: GoldShimmer.softColors),
                                    center: .center,
                                    angle: .degrees(210)
                                )
                            )
                    }
                    .shadow(color: Color(hex: "#D0AC5F").opacity(0.15), radius: 5, y: 2)
                    .scaleEffect(heartBeating ? 1.25 : 1.0)
                    
                }
                .frame(maxWidth: .infinity)

                CustomTabItem(
                    iconDefault: "envelope",
                    iconSelected: "envelope.open",
                    label: "Chats",
                    tab: .inbox,
                    selected: $selectedTab
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
            colors: [Color(hex: "#DDBE74")],
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

    var isSelected: Bool { selected == tab }

    var goldGradient: LinearGradient {
        LinearGradient(
            colors: [Color(hex: "#DDBE74")],
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
private final class KeyboardDismisser: NSObject {
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
        window.addGestureRecognizer(tap)
        isInstalled = true
    }

    @objc private func dismiss() {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
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
