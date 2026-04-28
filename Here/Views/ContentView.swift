import SwiftUI

struct ContentView: View {
    @EnvironmentObject var authService: AuthService

    @State private var selectedTab: MainTab = .feed
    @State private var showCreateSheet = false
    @State private var heartBeating = false
    @State private var navigateToThreadId: String? = nil
    @State private var showTabBar = true

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
            Color.black.ignoresSafeArea()

            TabView(selection: $selectedTab) {
                VoiceView()
                    .tag(MainTab.voice)

                FeedView(
                    posts: app.posts,
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
                .tag(MainTab.feed)

                Color.clear.tag(MainTab.create)

                InboxView(app: app, navigateToThreadId: $navigateToThreadId)
                    .tag(MainTab.inbox)

                ProfileView()
                    .tag(MainTab.profile)
            }
        .toolbar(.hidden, for: .tabBar)
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)) { _ in
            withAnimation(.easeInOut(duration: 0.25)) { showTabBar = false }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { _ in
            withAnimation(.easeInOut(duration: 0.25)) { showTabBar = true }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
          if showTabBar {
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
                    Image(systemName: "heart.fill")
                        .font(.system(size: 44, weight: .thin))
                        .foregroundStyle(goldGradient)
                        .shadow(color: Color(hex: "#C9A84C").opacity(0.4), radius: 6, y: 2)
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
            .padding(.horizontal, 12)
            .padding(.top, 8)
            .background(.ultraThinMaterial)
          }
        }
        .sheet(isPresented: $showCreateSheet) {
            CreatePostView(onSubmit: { title, bodyText, images in
                await app.addPost(title: title, bodyText: bodyText, images: images)
            })
            .presentationCornerRadius(28)
        }
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
            colors: [Color(hex: "#C9A84C"), Color(hex: "#E8CC7A"), Color(hex: "#B8922E")],
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
            colors: [Color(hex: "#C9A84C"), Color(hex: "#E8CC7A"), Color(hex: "#B8922E")],
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

// MARK: - Keyboard Dismisser
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
