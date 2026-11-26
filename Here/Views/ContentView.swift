import SwiftUI

struct ContentView: View {
    @EnvironmentObject var authService: AuthService
    
    @State private var selectedTab: MainTab = .feed
    /// 底部栏：Posts · ♥ · Chats，三个，心在正中。
    /// 定了（老板 2026-11-25 21:42：“上线比什么都要紧，那就改成三个的吧，只能先这样了”）。
    /// - 第一版不带 Voice：现在的 Voice 只有开关和在线人数，通话没做；而且随机配人通话正是苹果 1.2 点名的那一类。
    ///   `VoiceView`、`MainTab.voice` 都留着没删，只是底栏上没有入口。她以后一定要加 Voice
    ///   （“最好最好的就还是有 voice 的时候”）：做成不随机的；那时候把 Voice 和 Profile 两格放回底栏，就又是五个。
    /// - Profile 不在底栏上了：从 Chats 页右上角的小图标打开，是一张可以往下拉走的页。
    ///   （她：不能放在帖子页右上角——“跟其他 tags 就完全混在一起了”；“最多是能把它放在 chats 的右上角”。）
    /// - 试过、她没要的（不要再提）：四个平铺（“很不对称”）；五个、Voice 的位置换成 Mine（我发过的帖子）
    ///   ——“我真的再凑不出来一页不一样的东西”。
    /// 底栏的宽度：274pt，居中。
    /// 定了（老板 2026-11-25 22:11 选的 A）。起因是她 21:50 说的：“最底部的 bar 怎么那么长……我们只有三个部分，更要缩小了吧。”
    /// 依据：和苹果自己三格的底栏一样宽——iOS 26 的“文件”App（Recents / Shared / Browse），
    /// 2026-11-25 在模拟器里量的：宽 274pt（440pt 宽的屏幕的 62%）、高 61pt、三格中心相隔 86.5pt。有几格就多宽，不撑满。
    /// 试过、她没要的：几乎撑满（左右各留 22pt，原来五格时的宽度）；330pt。
    /// 以后放回五格时，这个数要跟着改（那时再量一次苹果五格的底栏）。
    private static let tabBarWidth: CGFloat = 274
    /// 从 Chats 页右上角的小图标打开 Profile
    @State private var showProfileSheet = false
    @State private var lastNonCreateTab: MainTab = .feed
    @State private var showCreateSheet = false
    @State private var showPhoneSignIn = false
    /// What to do once the phone is verified (e.g. open the composer)
    @State private var afterPhoneVerified: (() -> Void)?
    @State private var heartBeating = false
    @State private var navigateToThreadId: String? = nil
    @State private var isChatOpen = false
    @ObservedObject private var push = PushManager.shared
    @Environment(\.scenePhase) private var scenePhase
    #if DEBUG
    /// 临时:真机上比较背景方案的小面板(长按底栏的 Posts 打开)。见 DesignReview.swift。
    @State private var showDesignReview = false
    /// 临时:Feed 里放几条只在本机显示的示例帖子、Chats 里放几段示例对话,用来看排版
    /// (帖子 48 小时过期,Feed 经常是空的;她手机上也不一定有真的对话)。
    @AppStorage(DesignSamples.storageKey) private var useSamplePosts = false
    #endif

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
        .onChange(of: authService.uid) {
            // Sign-out lands on a fresh anonymous uid, so listeners bound to the
            // old uid (threads, user doc) must be torn down and rebuilt
            app.stopListening()
            if authService.isSignedIn, let uid = authService.uid {
                app.authService = authService
                app.startListening()
                PushManager.shared.userSignedIn(uid: uid)
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

    private var needsTermsConfirmation: Bool {
        authService.isPhoneVerified
            && app.userDocLoaded
            && app.acceptedTermsVersion != AuthService.termsVersion
            && !app.isDeletingAccount
    }

    /// True while the feed shows the local sample posts (debug builds only).
    /// Nothing done to a sample post leaves this phone.
    private var showingSamples: Bool {
        #if DEBUG
        return useSamplePosts
        #else
        return false
        #endif
    }

    /// 示例开着的时候,Chats 里放几段只在本机的示例对话(测试版才有)。平时是 nil。
    private var inboxPreview: InboxPreview? {
        #if DEBUG
        if useSamplePosts { return DesignSamples.inbox }
        #endif
        return nil
    }

    /// 示例开着的时候,个人页显示"绑了手机、发过帖、拉黑过人"的样子(测试版才有)。平时是 nil。
    private var profilePreview: ProfilePreview? {
        #if DEBUG
        if useSamplePosts { return DesignSamples.profile }
        #endif
        return nil
    }

    private var feedPosts: [Post] {
        #if DEBUG
        if useSamplePosts { return DesignSamples.posts }
        #endif
        // Private ("just for me") posts exist in Firestore — never show them to others
        // Posts live 48h. Nothing deletes them server-side, so expiry is
        // enforced here (and the author still sees them under My Posts → Archived)
        return app.posts.filter {
            $0.expiresAt > Date()
                && (!$0.isPrivate || $0.authorUID == app.uid)
                && !app.reportedPostIds.contains($0.id ?? "")
                && !app.blockedUIDs.contains($0.authorUID)
        }
    }

    /// Runs `action` if the phone is verified; otherwise asks for verification
    /// first and runs it afterwards. Reading never goes through here.
    private func requirePhone(then action: @escaping () -> Void) {
        if authService.isPhoneVerified {
            action()
        } else {
            afterPhoneVerified = action
            showPhoneSignIn = true
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
            // 备用底色:所有页面底下是同一张纸,避免任何缝隙露出突兀的颜色
            Theme.paper.ignoresSafeArea()

            // 自绘标签栏,不用 TabView——iOS 26 上系统的 Liquid Glass 标签栏
            // 用 .toolbar(.hidden) 藏不干净,会在自定义 bar 后面漏出来。
            Group {
                switch selectedTab {
                case .voice:
                    VoiceView(voice: app.voice, requirePhone: requirePhone)
                case .feed, .create:
                    FeedView(
                        posts: feedPosts,
                        uid: app.uid,
                        onStartChat: { post in
                            guard !showingSamples else { return }
                            requirePhone {
                                // Opens a local draft — nothing exists in Firestore
                                // (or on the other phone) until a message is sent
                                if let threadId = app.startChat(from: post) {
                                    navigateToThreadId = threadId
                                    selectedTab = .inbox
                                }
                            }
                        },
                        onToggleLike: { post, alreadyLiked in
                            guard !showingSamples else { return }
                            Task { await app.toggleLike(post: post, alreadyLiked: alreadyLiked) }
                        },
                        onReportPost: { post, reasons, details in
                            guard !showingSamples else { return }
                            Task { await app.reportPost(post, reasons: reasons, details: details) }
                        },
                        onBlockUser: { post in
                            guard !showingSamples else { return }
                            Task { await app.blockUser(post.authorUID) }
                        }
                    )
                case .inbox:
                    InboxView(app: app, navigateToThreadId: $navigateToThreadId, isChatOpen: $isChatOpen,
                              preview: inboxPreview, onOpenProfile: { showProfileSheet = true })
                case .profile:
                    ProfileView(app: app, preview: profilePreview)
                }
            }

            // Hidden while a chat thread is open so it doesn't cover the message input
            if !isChatOpen {
            HStack(spacing: 0) {
                // （Voice 这一格第一版没有。放回来时：图标 "waveform"，名字 "Voice"，tab: .voice，排在 Posts 前面。）
                CustomTabItem(
                    iconDefault: "book.closed",
                    iconSelected: "book",
                    label: "Posts",
                    tab: .feed,
                    selected: $selectedTab
                )
                #if DEBUG
                .simultaneousGesture(
                    LongPressGesture(minimumDuration: 0.6).onEnded { _ in
                        selectedTab = .feed
                        withAnimation(.easeInOut(duration: 0.2)) { showDesignReview = true }
                    }
                )
                #endif

                Button {
                    startHeartbeat()
                    requirePhone { showCreateSheet = true }
                } label: {
                    // 隐形占位复制邻居的图标+标签结构,心以 overlay 叠上去:
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
                        // 定稿(2026-11-22 02:36):一颗实心的心,深棕色(Theme.ink,和选中的图标同色),22pt。
                        // 没有圈,没有底,没有金色。她的话:"其实我最喜欢的是 7,最有存在感。"
                        // 它是底栏上唯一一个实心的东西,旁边四个都是细线,所以最显眼——发帖是最主要的动作。
                        // 位置:上提 3pt(往旁边的图标行靠一点,又不离开胶囊的正中太多)。她看过、定下来的就是这个位置。
                        // 走到这一步之前,没要的(不要再试):
                        // - 圈里一颗心,九个版本:金底、白底、金圈、棕圈配金心、棕和金之间的颜色、浅棕、
                        //   深棕圈配各种金心、深棕圈配深棕空心的心。问题在画法,不在颜色。
                        // - 换画法以后:只有一颗细线的心、淡圆底 + 心(这两个她说"蛮好但有点奇怪")、
                        //   淡圆底 + 加号、深棕实心圆 + 浅色的心、心 + 小字、更细更小的心、小一圈的淡底 + 心。
                        // 全部经过在 claude/here-design-process.md。
                        Image(systemName: "heart.fill")
                            .font(.system(size: 22, weight: .regular))
                            .foregroundColor(Theme.ink)
                            .offset(y: -3)
                            .scaleEffect(heartBeating ? 1.25 : 1.0)
                    }
                    .padding(.vertical, 8)
                    .contentShape(Rectangle())
                }
                // 给读屏(VoiceOver)用的名字:原来这颗心没有名字,读出来只是"按钮"
                .accessibilityLabel("New post")

                CustomTabItem(
                    iconDefault: "envelope",
                    iconSelected: "envelope.open",
                    label: "Chats",
                    tab: .inbox,
                    selected: $selectedTab,
                    // 没读的 + 到时间了等我回答的
                    badge: inboxPreview?.badge ?? (app.unreadThreadCount + app.pendingDecisionCount)
                )
                // （Profile 这一格第一版没有：它在 Chats 页的右上角。放回来时：图标 "person.icloud" /
                //   选中 "figure.mixed.cardio"，名字 "Profile"，tab: .profile，排在最后。）
            }
            // 上下那 8pt 的留白挪进了每一格里面(见 CustomTabItem 和发帖按钮):样子一点没变,
            // 但每一格从底栏的上边到下边都点得到。原来只有图标和字那 37pt 高的一块能点,
            // 上下各有 8pt 点了没反应(苹果要求可点的地方至少 44pt)。
            .padding(.horizontal, 10)
            // 宽度是定死的（见上面 tabBarWidth），居中
            .frame(maxWidth: Self.tabBarWidth)
            .glassTabBar()
            // 位置对齐 iOS 26 系统悬浮底栏(实测 Apple"文件"App):底边离屏幕底 21pt,
            // 压进 Home 指示条那片区域,而不是停在安全区之上(那样会高出近一倍)。
            // 左右这 22pt 现在只是保险:屏幕比底栏窄得多的时候不让它贴边(底栏本身 274pt、居中)。
            .padding(.horizontal, 22)
            .padding(.bottom, 21)
            .frame(maxHeight: .infinity, alignment: .bottom)
            .ignoresSafeArea(edges: .bottom)
            .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        #if DEBUG
        .overlay(alignment: .top) {
            if showDesignReview && selectedTab == .feed {
                DesignReviewPanel(isPresented: $showDesignReview, app: app)
                    .padding(.horizontal, 14)
                    .padding(.top, 4)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        #endif
        // Profile 从 Chats 页右上角打开，是一张可以往下拉走的页
        .sheet(isPresented: $showProfileSheet) {
            ProfileView(app: app, preview: profilePreview)
                .presentationDragIndicator(.visible)
        }
        // 在那一页里退出登录或删号以后，它自己收起来（不然会留着一张已经没有账号的 Profile）
        .onChange(of: authService.isPhoneVerified) { _, verified in
            if !verified { showProfileSheet = false }
        }
        // Verified accounts that accepted older terms (or none) confirm once
        // more — required before they keep posting and chatting.
        .sheet(isPresented: Binding(
            get: { needsTermsConfirmation && !showPhoneSignIn && !authService.isVerifyingPhone },
            set: { _ in }
        )) {
            TermsUpdateSheet()
                .environmentObject(authService)
        }
        .sheet(isPresented: $showPhoneSignIn) {
            PhoneSignInSheet(onVerified: {
                afterPhoneVerified?()
                afterPhoneVerified = nil
            })
            .environmentObject(authService)
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

    var body: some View {
        Button { selected = tab } label: {
            VStack(spacing: 5) {
                // 小图标和小字不用金色:当前页是棕色,其余是浅一档的棕色
                Image(systemName: isSelected ? iconSelected : iconDefault)
                    .font(.system(size: 20, weight: .light))
                    .foregroundColor(isSelected ? Theme.ink : Theme.tabOff)
                    // 数字只在没选中这一格时显示,挂在合着的信封的右上角(和最早那一版同一个位置)。
                    // 点进 Chats,信封打开,数字就收起来:这时候列表上已经看得到是哪一段有新的了。
                    // 这是她 2026-11-23 23:50 定的做法。
                    // 试过、她没要的(不要再试):选中时也留着数字,把它挪进来压在信封上
                    // ——"完全不灵动了,它整个就盖在这个信封上,完全不是之前的那种感觉了。我不喜欢。"
                    // (最早的毛病是:选中时信封换成打开的,它更高,数字被顶到底栏外面去了。)
                    .overlay(alignment: .topTrailing) {
                        if badge > 0 && !isSelected {
                            // 往上 5pt：数字的上边离底栏的上边 3pt。
                            // 定了（老板 2026-11-25 22:45 选的 A）。原来是往上 8pt，上边正好贴着底栏的上边
                            // （她 22:16：“chats 上面的 3 就是会 touch bar 的顶部，能不能下移”）。另一档（往上 3pt）她没要。
                            badgeLabel
                                .offset(x: 12, y: -5)
                                .transition(.scale(scale: 0.5).combined(with: .opacity))
                        }
                    }

                Text(label)
                    .font(Theme.ui(10, isSelected ? .bold : .medium))
                    .tracking(0.5)
                    .foregroundColor(isSelected ? Theme.ink : Theme.tabOff)
            }
            .frame(maxWidth: .infinity)
            // 这一格从底栏的上边到下边、从左到右都点得到(不只是图标和字)
            .padding(.vertical, 8)
            .contentShape(Rectangle())
        }
        .animation(.easeInOut(duration: 0.2), value: isSelected)
        // 读屏会说"已选中"
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    /// 底栏上的数字。字 11pt:苹果给 iOS 定的最小字号(最早是 10pt)。
    /// 高 16pt,一位数时是正圆——和最早那一版一样大。
    private var badgeLabel: some View {
        Text(badge > 99 ? "99+" : "\(badge)")
            .font(Theme.ui(11, .bold))
            .foregroundColor(Theme.ink)
            .padding(.horizontal, 4.5)
            .frame(minWidth: 16)
            .frame(height: 16)
            .background(Capsule().fill(Theme.matteGold))
            .overlay(Capsule().stroke(Theme.outline, lineWidth: 1))
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
