// InboxView.swift
import SwiftUI

// MARK: - Chats 列表
//
// 大思路是她原来的设计(11-19:Chats 列表"保留自己的设计思路,更清晰;欢迎微调"):
// 每一行左边一道竖线,右边三行字——昵称、从哪条帖子开始的、最后一句话——最右边是状态。
// 她原来的那道香槟色竖线、那颗珍珠一样的未读小金珠,原样留着。
//
// 微调了什么(2026-11-23),和为什么:
// 1. 字。原来是 10–13pt 的细体,颜色很淡(最淡的对比度 1.46:1;要求 4.5:1)。
//    现在和别的页面同一套圆体,最小 11pt,最淡的字是 Theme.ink3。
// 2. 每一行右上角都有一行小字说这段对话的时间:"12h left" / "time's up" / "ended"。
//    Here 的对话都有期限:哪一段快到了、哪一段在等你决定,在列表上就该看得到。
// 3. 到时间以后那 24 小时(ChatThread.decisionWindow):第三行不写最后一句话,
//    写 "Continue? 23h left to decide"(还没回答)或 "Waiting for her to decide · 23h left"(回答了 Yes)。
//    原来这两种和"已结束"混在一起,都写 ended。
// 4. 顺序:最近有动静的在最上面,和别的聊天 app 一样;结束的沉到最下面。见 entries(at:)。定了(她 11-23 23:50)。
//    试过、她没要的:"等你回答的排最上面,然后进行中的…"("有那么一点乱…有点反直觉");
//    "要我看的先排最上面"("排序一定是要按照标准做法来排的…不能有一个特别奇怪的排序,…还以为你这是一个 bug")。
// 5. 没读的那一行,最后一句话深一档、粗一档:不只靠那颗小金珠。
//    小金珠在中间那一行的右边,也就是这一行的正中(第一版在第三行右边,她说"太靠下了…
//    不太清楚它到底是在哪一个对话框")。
// 6. 背景和聊天页、发帖页同一张纸(纸 + 顶上一片白光),不是一块平的颜色(她嫌过单调)。
// 7. 最后一行不会被底栏挡住;按下去有反馈;右边没有系统那个灰色的小箭头。

/// 只给检查面板用:传了就显示这些示例对话,不读也不写后端。正式流程里永远是 nil。
struct InboxPreview {
    struct Item {
        let thread: ChatThread
        let lastMessage: String
        let unread: Int
        let lastActivity: Date
        /// 点进去看到的示例对话
        let chat: ChatPreview
    }

    let me: String
    let items: [Item]
    /// 和 founder 的那一段对话(草稿,见 FounderRow)。nil = 不显示。
    var founder: Item? = nil
    /// 系统消息那一段(草稿,见 FounderRow):举报之后"收到了""处理了"都发在这里。nil = 不显示。
    var system: Item? = nil

    /// 底栏 Chats 上该显示的数字:没读的 + 等我回答的
    var badge: Int {
        let now = Date()
        return items.filter { item in
            if !item.thread.isFrozen(now: now) { return item.unread > 0 }
            return item.thread.isAwaitingDecision(now: now)
                && item.thread.myContinueChoice(uid: me) == .undecided
        }.count + ((system?.unread ?? 0) > 0 ? 1 : 0)
    }
}

struct InboxView: View {
    @ObservedObject var app: AppState
    @Binding var navigateToThreadId: String?
    // Tells ContentView to hide the floating tab bar while a chat is open,
    // otherwise it covers the message input bar.
    @Binding var isChatOpen: Bool
    var preview: InboxPreview? = nil
    /// 这一页右上角打开 Profile 的小图标（底栏只有三个，Profile 从这里进）。nil = 不显示。
    /// 她 2026-11-25 20:33：“最多是能把它放在 chats 的右上角……chats 单独右上角有一页，然后画一个小图标。”
    var onOpenProfile: (() -> Void)? = nil
    /// 画法定了（老板 2026-11-25 21:50 选的 1：“1 看起来更像一个按钮吧”）：白色的圆按钮，
    /// 系统的那一种，和对话页右上角的盾牌一样。
    /// 试过、她没要的（不要再提）：不带圆、只有一个细线图标；不带圆、logo 里的一个小人（金色，单独看像字母 i）。

    @State private var navigationPath = NavigationPath()
    private var uid: String { preview?.me ?? app.uid }

    private var threads: [ChatThread] {
        if let preview { return preview.items.map(\.thread) }
        return app.visibleThreads
    }

    private func previewItem(_ thread: ChatThread) -> InboxPreview.Item? {
        preview?.items.first { $0.thread.id == thread.id }
    }

    private func lastMessage(of thread: ChatThread) -> String {
        if preview != nil { return previewItem(thread)?.lastMessage ?? "" }
        return app.messages[thread.id ?? ""]?.last?.text ?? "No messages yet"
    }

    private func unread(in thread: ChatThread) -> Int {
        if preview != nil { return previewItem(thread)?.unread ?? 0 }
        return app.unreadCount(in: thread)
    }

    private func lastActivity(of thread: ChatThread) -> Date {
        if preview != nil { return previewItem(thread)?.lastActivity ?? thread.createdAt }
        return app.lastActivity(of: thread)
    }

    /// 一行要画的东西:哪段对话,它现在在哪一步
    private struct Entry: Identifiable {
        let thread: ChatThread
        let phase: ThreadRow.Phase
        /// 最近一次有动静是什么时候(排序用)
        let latest: Date
        /// 和 founder 的那一段(草稿):画法不一样,而且永远不会结束
        var isFounder = false
        /// 系统消息那一段(草稿):和 founder 那一行同一个画法
        var isSystem = false
        var id: String { thread.id ?? thread.nickname }
    }

    /// 一段对话现在在哪一步(和聊天页里是同一个判断)
    private func phase(of thread: ChatThread, at now: Date) -> ThreadRow.Phase {
        if !thread.isFrozen(now: now) { return .active }
        guard thread.isAwaitingDecision(now: now) else { return .ended }
        switch thread.myContinueChoice(uid: uid) {
        case .undecided: return .decide
        case .yes: return .waiting
        case .no: return .ended
        }
    }

    /// 这段对话最近一次有动静的时刻:最后一条消息;时间自己走完的,走完的那一刻也算
    /// (从那一刻起它在等人回答,和来了一条新消息一样是"有事")。
    private func latestEvent(of thread: ChatThread, at now: Date) -> Date {
        let activity = lastActivity(of: thread)
        return thread.expiresAt <= now ? max(activity, thread.expiresAt) : activity
    }

    /// 顺序:最近有动静的在最上面;结束的沉到最下面(它们不会再有动静了)。
    /// 定了(她 2026-11-23 23:50:"排序一定是要按照标准做法来排的")。
    /// 依据:常用的聊天 app 都这么排,她打开这一页时带着的就是这个习惯(Jakob 定律)。
    private func entries(at now: Date) -> [Entry] {
        var all = threads
            .map { Entry(thread: $0, phase: phase(of: $0, at: now), latest: latestEvent(of: $0, at: now)) }
        // 和 founder 的那一段:不置顶,和别的还在的对话一起按先后排;它没有期限,所以永远不会沉到"结束的"那一组
        // (她 2026-11-25 16:43:"我占着第一行会不会很烦啊……永远不会沉到 ended 那里,但是还是按先后顺序
        // 跟其他 active 的对话一起排队")。
        if let founder = preview?.founder {
            all.append(Entry(thread: founder.thread, phase: .active, latest: founder.lastActivity, isFounder: true))
        }
        // 系统消息那一段:和 founder 那一段同一个规矩——不置顶、按先后排、不会结束
        if let system = preview?.system {
            all.append(Entry(thread: system.thread, phase: .active, latest: system.lastActivity, isSystem: true))
        }
        all.sort { $0.latest > $1.latest }
        return all.filter { $0.phase != .ended } + all.filter { $0.phase == .ended }
    }

    private func tryNavigate() {
        guard let threadId = navigateToThreadId,
              app.threads.contains(where: { $0.id == threadId })
                || app.draftThread?.id == threadId else { return }
        navigationPath = NavigationPath()
        navigationPath.append(threadId)
        navigateToThreadId = nil
    }

    var body: some View {
        NavigationStack(path: $navigationPath) {
            // No title on this page: the tab bar already says "Chats", and a large
            // word above the list only added weight. (It was once the system's large
            // title — bold and pure black.)
            ZStack {
                // 和聊天页、发帖页同一张纸
                PaperBackground()

                if threads.isEmpty {
                    emptyState
                } else {
                    // 每分钟看一次钟:右上角的 "12h left" 会走,到时间的那一行会自己换样子、换位置
                    TimelineView(.periodic(from: .now, by: 60)) { context in
                        ScrollView {
                            VStack(spacing: 0) {
                                LazyVStack(spacing: 0) {
                                    ForEach(entries(at: context.date)) { entry in
                                        NavigationLink(value: entry.thread.id ?? "") {
                                            if entry.isFounder {
                                                // 和 founder 的对话。草稿:现在只在示例里出现,后端还没接。
                                                FounderRow(nickname: entry.thread.nickname,
                                                           lastMessage: preview?.founder?.lastMessage ?? "")
                                            } else if entry.isSystem {
                                                // 系统消息。草稿:只在示例里出现,后端还没接。
                                                // 她 2026-11-25 19:22:"系统就完全可以 copy 这个样子"(指 founder 那一行)。
                                                FounderRow(nickname: entry.thread.nickname,
                                                           lastMessage: preview?.system?.lastMessage ?? "",
                                                           label: "system",
                                                           unread: preview?.system?.unread ?? 0)
                                            } else {
                                                ThreadRow(
                                                    thread: entry.thread,
                                                    phase: entry.phase,
                                                    lastMessage: lastMessage(of: entry.thread),
                                                    unread: unread(in: entry.thread),
                                                    now: context.date
                                                )
                                            }
                                        }
                                        .buttonStyle(PressFade())
                                    }
                                }
                                .padding(.leading, 24)
                                .padding(.trailing, 22)
                            }
                        }
                        // 第一行离状态栏留一点空;最后一行能滚到底栏上面
                        .contentMargins(.top, 12, for: .scrollContent)
                        .contentMargins(.bottom, 76, for: .scrollContent)
                    }
                }
            }
            // The system title bar is hidden on the list; the title stays because it
            // names the back button inside a conversation.
            .navigationTitle("Chats")
            .navigationBarTitleDisplayMode(.inline)
            // 把顶上那一条露出来，只放右边一个图标——和对话页右上角的盾牌是同一种系统按钮；中间不写 "Chats"。
            // （没有图标时，顶上那一条还是藏着的。）
            .toolbar(onOpenProfile == nil ? .hidden : .visible, for: .navigationBar)
            .toolbar {
                if let onOpenProfile {
                    ToolbarItem(placement: .principal) {
                        Color.clear.frame(width: 1, height: 1).accessibilityHidden(true)
                    }
                    ToolbarItem(placement: .topBarTrailing) {
                        Button(action: onOpenProfile) {
                            Image(systemName: "person.icloud")
                        }
                        .accessibilityLabel("Profile")
                    }
                }
            }
            .navigationDestination(for: String.self) { threadId in
                destination(for: threadId)
            }
        }
        .onChange(of: navigateToThreadId) { tryNavigate() }
        // Threads arrive async — retry the pending navigation once the new thread lands
        .onChange(of: app.threads) { tryNavigate() }
        .onAppear { tryNavigate() }
        .onChange(of: navigationPath.count) {
            withAnimation(.easeInOut(duration: 0.25)) {
                isChatOpen = navigationPath.count > 0
            }
        }
        .onDisappear { isChatOpen = false }
    }

    @ViewBuilder
    private func destination(for threadId: String) -> some View {
        if let founder = preview?.founder, founder.thread.id == threadId {
            ChatDetailView(thread: founder.thread, app: app, preview: founder.chat)
                .toolbar(.visible, for: .navigationBar)
        } else if let system = preview?.system, system.thread.id == threadId {
            ChatDetailView(thread: system.thread, app: app, preview: system.chat)
                .toolbar(.visible, for: .navigationBar)
        } else if let item = preview?.items.first(where: { $0.thread.id == threadId }) {
            ChatDetailView(thread: item.thread, app: app, preview: item.chat)
                .toolbar(.visible, for: .navigationBar)
        } else if let thread = app.threads.first(where: { $0.id == threadId })
                    ?? (app.draftThread?.id == threadId ? app.draftThread : nil) {
            ChatDetailView(thread: thread, app: app)
                .toolbar(.visible, for: .navigationBar)
        }
    }

    /// Nothing here yet: one quiet mark in the middle, like the empty feed
    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "envelope")
                .font(.system(size: 34, weight: .thin))
                .foregroundColor(Theme.tabOff)
            Text("No conversations yet.")
                .font(Theme.ui(17))
                .foregroundColor(Theme.ink)
            Text("Tap “Chat privately” on a post to start one.")
                .font(Theme.ui(13))
                .foregroundColor(Theme.ink2)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.horizontal, 40)
    }
}

// MARK: - 一行
struct ThreadRow: View {
    /// 这段对话现在在哪一步
    enum Phase {
        case active     // 进行中
        case decide     // 到时间了,等我回答要不要继续(24 小时内)
        case waiting    // 我回答了 Yes,等她
        case ended      // 结束了
    }

    let thread: ChatThread
    let phase: Phase
    let lastMessage: String
    let unread: Int
    let now: Date

    private var isEnded: Bool { phase == .ended }
    private var hasUnread: Bool { phase == .active && unread > 0 }

    /// 结束的那几行的字:比还在的浅一档。定了(她 2026-11-24 00:15:"那就这么定了")。
    /// 原来是 ink3(4.48:1),和还在的那几行的小字(5.41:1)几乎分不出来——她的话:"一眼看过去,好像看不太出来
    /// 很多区别"。现在是 3.14:1:比 3:1(苹果和 WCAG 给"看得见"定的下限)高一点,还读得出来。
    /// 结束的对话还是要能点进去看的,不要再往浅调。
    /// 结束的和还在的靠三样分开:字浅一档、右上角写 ended、永远排在最下面。
    /// 试过、她没要的(不要再提):
    /// - 竖条加粗到 3pt,还在的用 logo 的金、结束的用浅棕("B 和 C 我又觉得有点 too much");
    /// - 竖条不加粗,只换成那两种颜色("我好像确实是更喜欢 A…没有那么喜欢 D")。
    private var endedText: Color { Color(hex: "#9E8B79") }

    // 她原来的竖线:香槟白金,低饱和、带一点冷调的浅金。宽 2pt,颜色和宽度都不要动(见上)。
    private var goldGradient: LinearGradient {
        LinearGradient(
            colors: [Color(hex: "#F7EFD8"), Color(hex: "#E6D7AC")],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    /// 右上角那行小字
    private var status: String {
        switch phase {
        case .active: return Self.short(thread.expiresAt.timeIntervalSince(now)) + " left"
        case .decide, .waiting: return "time's up"
        case .ended: return "ended"
        }
    }

    /// 还剩多久可以决定
    private var decisionLeft: String {
        Self.short(thread.decisionDeadline.timeIntervalSince(now))
    }

    /// 列表上写得短:够一小时写小时,不够写分钟,最少 1m
    private static func short(_ seconds: TimeInterval) -> String {
        let total = max(60, seconds)
        return total >= 3600 ? "\(Int(total / 3600))h" : "\(Int(total / 60))m"
    }

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            // 左边那道竖线:亮着 = 这段对话还在;结束了变灰
            RoundedRectangle(cornerRadius: 2)
                .fill(isEnded
                      ? LinearGradient(colors: [Color(hex: "#E8E0CC")], startPoint: .top, endPoint: .bottom)
                      : goldGradient
                )
                .frame(width: 2, height: 64)

            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(thread.nickname)
                        .font(Theme.ui(16, .semibold))
                        .foregroundColor(isEnded ? endedText : Theme.ink)
                        .lineLimit(1)

                    Spacer(minLength: 8)

                    Text(status)
                        .font(Theme.ui(11, .semibold))
                        .tracking(0.3)
                        .foregroundColor(isEnded ? endedText : Theme.ink3)
                        .fixedSize()
                }

                // 中间这一行的右边 = 这一行的正中:没读的小金珠放这里,一眼看得出是哪一段对话的
                HStack(alignment: .center, spacing: 8) {
                    Text(verbatim: "re: \(thread.postTitle)")
                        .font(Theme.ui(12, .medium))
                        .foregroundColor(isEnded ? endedText : Theme.ink2)
                        .lineLimit(1)
                    Spacer(minLength: 8)
                    if hasUnread { pearl }
                }

                thirdLine
            }
        }
        .padding(.vertical, 12)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }

    /// 第三行:平时是最后一句话;到时间以后那 24 小时里,是"要不要继续"和还剩多久
    @ViewBuilder
    private var thirdLine: some View {
        switch phase {
        case .decide:
            clockLine("Continue? \(decisionLeft) left to decide", strong: true)
        case .waiting:
            clockLine("Waiting for her to decide · \(decisionLeft) left", strong: false)
        case .active, .ended:
            Text(lastMessage)
                .font(Theme.ui(14, hasUnread ? .medium : .regular))
                .foregroundColor(isEnded ? endedText : (hasUnread ? Theme.ink : Theme.ink2))
                .lineLimit(1)
        }
    }

    /// 小沙漏 + 一句话(和聊天页里那句问话下面的是同一个沙漏)
    private func clockLine(_ text: String, strong: Bool) -> some View {
        HStack(spacing: 5) {
            Image(systemName: "hourglass")
                .font(.system(size: 11, weight: .medium))
                .accessibilityHidden(true)
            Text(verbatim: text)
                .font(Theme.ui(14, strong ? .medium : .regular))
                .lineLimit(1)
                .minimumScaleFactor(0.9)
        }
        .foregroundColor(strong ? Theme.ink : Theme.ink2)
    }

    /// 未读只提示"有没有":她原来那颗珍珠感的小金珠,原样
    private var pearl: some View {
        Circle()
            .fill(
                RadialGradient(
                    colors: [
                        Color(hex: "#FFFDF4"),
                        Color(hex: "#F9EEC6"),
                        Color(hex: "#EFD88E"),
                        Color(hex: "#DDBC55")
                    ],
                    center: UnitPoint(x: 0.4, y: 0.35),
                    startRadius: 0.5,
                    endRadius: 5.5
                )
            )
            .frame(width: 10, height: 10)
            .shadow(color: Color(hex: "#D0AC5F").opacity(0.35), radius: 2, y: 1)
            .accessibilityLabel("Unread")
    }
}

// MARK: - 和 founder 的那一行
//
// **草稿。只在示例里出现(InboxPreview.founder 不是 nil 的时候),后端还没接。**
// 她 2026-11-25 16:05:"我想要上线,我就必须要有这个 founder 对话框"。整件事见 claude/here-founder-chat-idea.md。
//
// 现在的样子(她 16:27 说的):就是一行普通的对话,只有两处不一样——
//   1. 左边那道竖线深一点(品牌金 Theme.brandGold;别的行是香槟色)。宽度、高度和别的行一样。
//   2. 右上角别的行写还剩多久的地方,写的是 founder。
// 名字是一个昵称,和所有人一样(占位:first light,等她自己定);没有头像。
// 不置顶(她 16:43:"我占着第一行会不会很烦啊"):和别的还在的对话一起按先后排,只是永远不会结束。见 entries(at:)。
//
// 第一版(16:25)她没要,不要再拿出来:
// - 头像(一个 "C" 的金色圆片,打算以后换成她的照片):"我也不想要放我的照片……既然大家都没有照片,那我干嘛要放照片?"
// - 真名 + founder 小标签:"如果我想跟品牌调性一样的话……我难道不应该就是写一个我的昵称吗?"
// - 放在一张卡片里 / 下面加一道细线、右上角一颗图钉:"不要把我的这个框做的这么明显……
//   只要大家能看出来我这个跟别人不太一样就行了,别这么不一样。"
struct FounderRow: View {
    let nickname: String
    let lastMessage: String
    /// 右上角那两个字。系统消息那一行用的是同一个画法,写的是 system(她 2026-11-25 19:22 说照这一行做)。
    var label: String = "founder"
    /// 有没读的:中间那行右边一颗小金珠,最后一句话加深——和别的行同一个做法
    var unread: Int = 0

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            // 和别的行同一道竖线(2pt 宽、64pt 高),只是金色深一点
            RoundedRectangle(cornerRadius: 2)
                .fill(Theme.brandGold)
                .frame(width: 2, height: 64)

            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(verbatim: nickname)
                        .font(Theme.ui(16, .semibold))
                        .foregroundColor(Theme.ink)
                        .lineLimit(1)

                    Spacer(minLength: 8)

                    Text(verbatim: label)
                        .font(Theme.ui(11, .semibold))
                        .tracking(0.3)
                        .foregroundColor(Theme.ink3)
                        .fixedSize()
                }

                // 这两行(founder、Here)没有 "re: …" 那一行:它们不是从哪条帖子开始的。
                // 定了(老板 2026-11-25 19:33:"founder 和 Here 都不要有那个 re: … 比较好吧")。
                // 竖线还是 64pt 高,所以这一行和别的行一样高,只是里面少一行字。
                HStack(alignment: .center, spacing: 8) {
                    Text(verbatim: lastMessage)
                        .font(Theme.ui(14, unread > 0 ? .medium : .regular))
                        .foregroundColor(unread > 0 ? Theme.ink : Theme.ink2)
                        .lineLimit(1)
                    Spacer(minLength: 8)
                    if unread > 0 { UnreadPearl() }
                }
            }
        }
        .padding(.vertical, 12)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}

#Preview {
    InboxView(app: AppState(authService: AuthService()), navigateToThreadId: .constant(nil), isChatOpen: .constant(false))
}

/// 没读的小金珠。和 ThreadRow 里那一颗是同一个画法、同样的数(那一行锁定了,所以这里另抄一份,没有去动它)。
private struct UnreadPearl: View {
    var body: some View {
        Circle()
            .fill(
                RadialGradient(
                    colors: [
                        Color(hex: "#FFFDF4"),
                        Color(hex: "#F9EEC6"),
                        Color(hex: "#EFD88E"),
                        Color(hex: "#DDBC55")
                    ],
                    center: UnitPoint(x: 0.4, y: 0.35),
                    startRadius: 0.5,
                    endRadius: 5.5
                )
            )
            .frame(width: 10, height: 10)
            .shadow(color: Color(hex: "#D0AC5F").opacity(0.35), radius: 2, y: 1)
            .accessibilityLabel("Unread")
    }
}
