#if DEBUG
import SwiftUI

// MARK: - 临时：真机上的检查面板
// 画布上看着对的东西，上了真机不一定对，所以直接在手机上看。
// 长按底栏的 Posts 打开。里面只有"去看某一页"的入口：单独看品牌页、按新用户的流程从头走一遍
// （品牌页 → 确认页）、不用验证手机就打开发帖页（只看不发）、聊天页（示例对话）、
// 示例帖子和对话（打开以后 Posts 里是示例帖子，Chats 里是示例对话，点进去就是聊天页）。
// 某一轮需要她在几个定好的方案里选一个时，把那一排临时加在最上面，选完就删。
//
// 11-21 以前这里有调颜色的滑杆。那是我把该我做的决定推给了她：她说得对，
// 应该是我给出定好的设计，她拍板。颜色已经定稿（Theme.swift），滑杆全部去掉了。
//
// 只在测试版（DEBUG）里编译，正式版里没有。
// 用完以后：删掉这个文件，以及 ContentView 里标着 DEBUG 的几处。
struct DesignReviewPanel: View {
    @Binding var isPresented: Bool
    /// 聊天页要用（示例对话不读也不写后端，但那一页的类型要它）
    let app: AppState

    @AppStorage(DesignSamples.storageKey) private var useSamplePosts = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// The same key HereApp reads: clearing it sends the app back to the first-run flow.
    @AppStorage("womenGateAnswer") private var womenGateAnswer = ""
    /// 验证手机号、确认条款那两张弹窗的类型要它（从这里打开只是看样子，不会真的用到）
    @EnvironmentObject private var auth: AuthService
    @State private var showReportSheet = false
    @State private var showPhoneSheet = false
    @State private var showTermsSheet = false
    @State private var showBrand = false
    @State private var showCreate = false
    @State private var showChat = false
    @State private var showChatEnded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("检查面板（只在测试版里有）")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(Theme.ink2)
                Spacer()
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) { isPresented = false }
                } label: {
                    Text("收起")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(Theme.ink)
                        .frame(width: 56, height: 32)
                        .background(Capsule().fill(Color.white))
                        .overlay(Capsule().stroke(Theme.outline, lineWidth: 1))
                }
                .buttonStyle(.plain)
            }

            // 临时：请她选的东西，放在最上面。点一下，那一页马上就换，不用关面板。
            // 私聊的金色（她说 2 和 3 先留着，全部做完再定；最深的那一档她不要了，已经删了）。
            // （个人页那两排——金色图标、Sign Out 放在哪——她 2026-11-25 都定了，已经删了。）
            // （Delete Account 放哪、两行字的金色，她也定了，那一排已经删了。）
            // （Chats 里置顶的 founder 那一行：卡片 / 头像那两种她没要，那一排已经删了。）
            // （聊天页选图的按钮：她 2026-11-25 17:28 选了 A＝输入框左边，那一排已经删了。）
            // （三张小弹窗的主按钮：她 2026-11-25 19:18 选了 A＝实心深棕，那一排已经删了。）
            // （私聊按钮的金色：她 2026-11-25 18:32 定了 3＝未读小圆点的那个金，那一排已经删了。）

            // （底部栏：她 2026-11-25 21:42 定了三个——Posts · ♥ · Chats，那一排开关已经删了。）
            // （Chats 页右上角的 Profile 图标：她 2026-11-25 21:50 选了 1＝白色圆按钮，那一排开关已经删了。）
            // （底栏的宽度：她 2026-11-25 22:11 选了 A＝274pt，和苹果自己三格的底栏一样宽，那一排开关已经删了。）
            // （Chats 那一格上的未读数字：她 2026-11-25 22:45 选了 A＝往下挪 3pt，那一排开关已经删了。）
            // （发帖页正文的提示语：她 2026-11-25 23:38 定了 "here's the thing…"，那一排开关已经删了。）

            if reduceMotion {
                // 系统开了"减弱动态效果"时背景停在第一帧——说清楚，免得以为坏了
                Text("这台手机开了“减弱动态效果”，所以背景不会动。在 设置 ▸ 辅助功能 ▸ 动态效果 里关掉就能看到。")
                    .font(.system(size: 11))
                    .foregroundColor(Theme.ink)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack(spacing: 8) {
                pageButton("看品牌页") { showBrand = true }
                // 按新用户的流程走一遍：品牌页 → 确认页。点 Yes 回到 app。
                pageButton("从头走一遍") {
                    isPresented = false
                    womenGateAnswer = ""
                }
            }

            // 发帖页：不用验证手机就能打开。只看不发——点 Send 只是关掉，什么都不会发出去。
            pageButton("看发帖页（只看不发）") { showCreate = true }

            // 聊天页：一段示例对话。在里面打字、点发送都只留在这一页，不会发给任何人。
            HStack(spacing: 8) {
                // 进行中的对话。点顶上的小卡片能看到开头那条帖子。
                pageButton("看聊天页") { showChat = true }
                // 48 小时到了以后的样子：问要不要再聊 48 小时，问话下面是 24 小时的倒计时。
                // 这一个里面点小卡片，看到的是“帖子已经离开了”的样子。
                pageButton("聊天 · 到时间了") { showChatEnded = true }
            }

            // 三张小弹窗：只看样子。举报不会交上去；验证手机号不发短信、不登录；确认条款不记录、不退出登录。
            HStack(spacing: 8) {
                pageButton("举报") { showReportSheet = true }
                pageButton("验证手机") { showPhoneSheet = true }
                pageButton("确认条款") { showTermsSheet = true }
            }

            Toggle(isOn: $useSamplePosts) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("示例帖子和对话")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(Theme.ink)
                    Text("只在这台手机上显示，不会发出去")
                        .font(.system(size: 11))
                        .foregroundColor(Theme.ink2)
                }
            }
            .tint(Theme.ink2)
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous).fill(Color.white.opacity(0.97))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(Theme.outline, lineWidth: 1)
        )
        .shadow(color: Theme.ink.opacity(0.10), radius: 16, y: 6)
        // 品牌页：点一下任意位置关闭
        .fullScreenCover(isPresented: $showBrand) {
            BrandScreen()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .contentShape(Rectangle())
                .onTapGesture { showBrand = false }
        }
        .fullScreenCover(isPresented: $showCreate) {
            CreatePostView(onSubmit: { _, _, _, _, _ in
                // 假装发了一下，然后关掉
                try? await Task.sleep(nanoseconds: 600_000_000)
                return true
            })
        }
        .fullScreenCover(isPresented: $showChat) {
            NavigationStack {
                ChatDetailView(thread: DesignSamples.chatThread(ended: false), app: app, preview: DesignSamples.chatPreview(postGone: false))
            }
        }
        .sheet(isPresented: $showReportSheet) {
            // 只看样子：点 Submit report 只是关掉，什么都不会交上去
            ReportSheet(
                title: "Why are you reporting this post?",
                message: "Your report is anonymous, and you won't see this post again."
            ) { _, _ in }
        }
        .sheet(isPresented: $showPhoneSheet) {
            PhoneSignInSheet(preview: true)
                .environmentObject(auth)
        }
        .sheet(isPresented: $showTermsSheet) {
            TermsUpdateSheet(preview: true)
                .environmentObject(auth)
        }
        .fullScreenCover(isPresented: $showChatEnded) {
            NavigationStack {
                ChatDetailView(thread: DesignSamples.chatThread(ended: true), app: app, preview: DesignSamples.chatPreview(postGone: true))
            }
        }
    }

    /// 临时：几个定好的方案里选一个。每个按钮写明它的字和它代表的值。选中的那个是实心的。
    private func choiceRow(_ title: String, selection: Binding<Int>, options: [(label: String, value: Int)]) -> some View {
        HStack(spacing: 8) {
            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(Theme.ink)
                .frame(width: 76, alignment: .leading)
            ForEach(options, id: \.value) { option in
                choiceButton(option.label, selected: selection.wrappedValue == option.value) { selection.wrappedValue = option.value }
            }
        }
    }

    private func choiceButton(_ title: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 15, weight: .bold))
                .foregroundColor(selected ? Theme.paper : Theme.ink)
                .frame(maxWidth: .infinity)
                .frame(height: 40)
                .background(Capsule().fill(selected ? Theme.ink : Color.white))
                .overlay(Capsule().stroke(Theme.outline, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    private func pageButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(Theme.ink)
                .frame(maxWidth: .infinity)
                .frame(height: 40)
                .background(Capsule().fill(Color.white))
                .overlay(Capsule().stroke(Theme.outline, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - 示例帖子
/// 几条只存在于这台手机上的帖子，用来在 Feed 里看排版：短的、长的、只有标题的。
/// 对它们点 here、聊天、举报都不会发出任何东西（ContentView 里拦住了）。
enum DesignSamples {
    static let storageKey = "design.samplePosts"

    /// 个人页的示例:绑了手机、有两条还在的帖子(一条只给自己看)、两条过期的、拉黑过两个人。
    /// 只在这台手机上显示;里面的 Sign Out、Delete Account、Unblock 点了不做任何事。
    static let profile: ProfilePreview = {
        let hour: TimeInterval = 3600
        let now = Date()
        return ProfilePreview(
            phone: "+14155558291",
            posts: [
                Post(id: "sample-mine-1", title: "Small win today", authorUID: "sample-me",
                     createdAt: now.addingTimeInterval(-3 * hour), tags: ["🌱"]),
                Post(id: "sample-mine-2", title: "Things I can't say out loud yet", authorUID: "sample-me",
                     createdAt: now.addingTimeInterval(-26 * hour), tags: ["🌙", "😴"], isPrivate: true),
                Post(id: "sample-mine-3", title: "First week at the new job", authorUID: "sample-me",
                     createdAt: now.addingTimeInterval(-5 * 24 * hour), tags: ["☕️"]),
                Post(id: "sample-mine-4", title: "I miss my grandmother's kitchen", authorUID: "sample-me",
                     createdAt: now.addingTimeInterval(-12 * 24 * hour), tags: ["🍚"])
            ],
            blocked: [
                ProfilePreview.Blocked(id: "sample-blocked-1", nickname: "wandering echo"),
                ProfilePreview.Blocked(id: "sample-blocked-2", nickname: nil)
            ]
        )
    }()

    static let posts: [Post] = [
        Post(
            id: "sample-1",
            title: "Couldn't sleep again",
            bodyText: "It's 3am and my brain is replaying every awkward thing I said this week. "
                + "I don't need advice. I just didn't want to be the only one awake.",
            authorUID: "sample-author",
            likeCount: 12,
            tags: ["😴", "🌙"]
        ),
        Post(
            id: "sample-2",
            title: "Small win today",
            bodyText: "I finally called the dentist. It took me four months to make a two-minute call. "
                + "That's it, that's the post.",
            authorUID: "sample-author",
            likeCount: 31,
            tags: ["🌱"]
        ),
        Post(
            id: "sample-3",
            title: "Does anyone else feel behind?",
            bodyText: "Everyone I know seems to be getting promoted, engaged, or moving somewhere with better light. "
                + "I'm still figuring out what I want for dinner.\n\n"
                + "I know it isn't a race. I say that to my friends all the time, and I mean it when I say it to them. "
                + "It's harder to mean it at eleven at night with my phone in my hand.\n\n"
                + "I think I just wanted to put this somewhere that isn't my notes app. If you're behind too, "
                + "we can be behind together for a minute.",
            authorUID: "sample-author",
            likeCount: 48,
            tags: ["💭", "☕️", "🌧️"]
        ),
        Post(
            id: "sample-4",
            title: "I'm tired today, and I'm letting that be okay.",
            authorUID: "sample-author",
            likeCount: 7,
            tags: ["🌸"]
        )
    ]

    // MARK: 示例对话（聊天页用）
    /// 只存在于这台手机上的一段对话，用来看聊天页的排版：两天、长短不一、双方都有连着发的。
    static let chatMe = "sample-me"

    /// 进行中的：35 个半小时以前开始，还剩 12 个半小时。
    /// 到时间了的：48 个半小时以前开始，也就是半小时前到的时间，还有 23 个半小时可以决定。
    static func chatThread(ended: Bool) -> ChatThread {
        ChatThread(
            id: ended ? "sample-thread-ended" : "sample-thread",
            postId: "sample-1",
            postTitle: "Couldn't sleep again",
            participants: [chatMe, "sample-author"],
            createdAt: Date().addingTimeInterval(-(ended ? 48.5 : 35.5) * 3600),
            nickname: "quiet moon"
        )
    }

    /// 开头那条帖子。示例对话里它是“我”写的（对方说的是 "your post really resonated with me"）。
    private static var chatSourcePost: Post {
        let sample = posts[0]
        return Post(
            id: sample.id,
            title: sample.title,
            bodyText: sample.bodyText,
            authorUID: chatMe,
            likeCount: sample.likeCount,
            tags: sample.tags
        )
    }

    /// postGone：点小卡片时看到“帖子已经离开了”的样子（用来看那句话；正式流程里自己的帖子一直看得到）。
    /// photoStates：看“看不了图”的两种样子。中间有她发的一张、我发的一张，都没通过检查（两边是同一句话）；
    /// 最后多一条她刚发来、还在检查的图。
    static func chatPreview(postGone: Bool, photoStates: Bool = false) -> ChatPreview {
        let now = Date()
        let her = "sample-author"
        func at(_ hoursAgo: Double, _ minutes: Double = 0) -> Date {
            now.addingTimeInterval(-(hoursAgo * 3600) + minutes * 60)
        }
        var lines: [(String, String, Date)] = [
            ("system", "Started from: \"Couldn't sleep again\"", at(20, -1)),
            (her, "hey, your post really resonated with me", at(20)),
            (her, "i've been awake since 2 doing the exact same thing", at(20, 1)),
            (chatMe, "thank you for saying that. it helps to know it's not just me", at(20, 3)),
            (chatMe, "what's keeping you up?", at(20, 3.5)),
            (her, "a conversation with my sister. i keep rewriting what i should have said", at(20, 6)),
            (chatMe, "i do that too. last week i wrote a whole speech in my head and then just said \"it's fine\". did you two talk again?", at(0, -42)),
            (her, "not yet. maybe tomorrow", at(0, -40)),
            (her, "thank you for staying up with me 🌙", at(0, -39))
        ]
        var photos: [Int: ChatPhoto] = [:]
        if photoStates {
            // 她在说姐姐那件事之后发过一张，我回了一张，都没通过
            lines.insert((her, "", at(20, 6.5)), at: 6)
            lines.insert((chatMe, "", at(20, 9)), at: 7)
            photos[6] = .rejected
            photos[7] = .rejected
            // 她刚又发来一张，还在检查
            lines.append((her, "", at(0, -0.3)))
            photos[lines.count - 1] = .checking
        }
        var preview = ChatPreview(
            me: chatMe,
            messages: lines.enumerated().map { index, line in
                ChatMessage(id: "sample-msg-\(index)", text: line.1, senderUID: line.0, createdAt: line.2)
            },
            post: postGone ? nil : chatSourcePost
        )
        for (index, photo) in photos { preview.photos["sample-msg-\(index)"] = photo }
        return preview
    }

    // MARK: 示例对话列表（Chats 用）
    /// 六段只存在于这台手机上的对话：没读的、读过的、等我回答的、等她的，和两段结束的。
    /// 点进去是同一段示例对话，只是昵称、时间和状态不同。在里面做的事都只留在这台手机上。
    /// 只算一次：时间是从第一次打开示例那一刻往回数的。
    static let inbox: InboxPreview = {
        let now = Date()
        func thread(_ id: String, _ nickname: String, _ title: String, startedHoursAgo: Double) -> ChatThread {
            ChatThread(
                id: id,
                postId: "sample-1",
                postTitle: title,
                participants: [chatMe, "sample-author"],
                createdAt: now.addingTimeInterval(-startedHoursAgo * 3600),
                nickname: nickname
            )
        }
        /// 从列表点进去的：系统已经给了返回，不用自己画
        /// `goneInDays`：结束了的对话还有几天消失（草稿：彻底结束 7 天后删，她 2026-11-25 19:18 定的）。
        func chat(postGone: Bool, goneInDays: Double? = nil, photoStates: Bool = false) -> ChatPreview {
            var preview = chatPreview(postGone: postGone, photoStates: photoStates)
            preview.standalone = false
            if let goneInDays { preview.disappearsAt = now.addingTimeInterval(goneInDays * 86_400) }
            return preview
        }

        // 顺序（最近有动静的在上面）：quiet moon → amber tide → soft rain → paper lantern → 两段结束的

        // 没读的：她 4 分钟前来了一条；还剩 12 个半小时
        let unreadThread = thread("sample-thread", "quiet moon", "Couldn't sleep again", startedHoursAgo: 35.5)
        // 读过的：我 25 分钟前回的；还剩将近 32 小时
        let readThread = thread("sample-thread-read", "amber tide", "First snow", startedHoursAgo: 16.2)
        // 等我回答的：一小时前到的时间
        let decideThread = thread("sample-thread-decide", "soft rain", "New here", startedHoursAgo: 49)
        // 等她的：我回答了 Yes，还剩 5 个多小时
        var waitingThread = thread("sample-thread-waiting", "paper lantern", "Small win today", startedHoursAgo: 66.3)
        waitingThread.continueChoices[chatMe] = ContinueChoice.yes.rawValue
        // 结束的（有人点了结束）
        var endedThread = thread("sample-thread-over", "wandering echo", "Feeling grateful", startedHoursAgo: 80)
        endedThread.isManuallyFrozen = true
        // 结束的（到时间以后 24 小时里没有续）
        let lapsedThread = thread("sample-thread-lapsed", "silver pine", "Long week", startedHoursAgo: 100)

        // 和 founder 的对话（草稿）。昵称是占位的；欢迎语是按她 11-25 16:27 和 16:43 说的意思起的草稿，等她改。
        // 她打字全小写，所以这里也全小写。最后一句是个问题、不是句号：她要看完的人想回（16:43）。
        // 聊天里现在只能发文字，所以还发不了狗的照片。
        // 三小时前来的：排在更近的几段对话后面，看得出它不置顶、和别的一起按先后排。
        let founderUID = "sample-founder"
        let founderAt = now.addingTimeInterval(-3 * 3600)
        let founderThread = ChatThread(
            id: "sample-thread-founder",
            postId: nil,
            postTitle: "welcome to here",
            participants: [chatMe, founderUID],
            createdAt: founderAt,
            nickname: "first light"
        )
        let founderLines = [
            "hi, i'm the founder of here 👋",
            "this first message is automated, because i can't be awake every time someone joins. everything after it is me, typing. there's a lot of ai out there and i'm not one. i'm a real person and i'm not going anywhere. i'm 23, i live in the bay area, and i have a little dog.",
            "in here i can't see who you are, so say anything. i reply to every message, and i care how you're feeling. think of me as a friend, not customer service.",
            "two serious things, then i'm done. if anyone on here ever makes you uncomfortable, report them and tell me. i want to know. and if you're ever in real danger, don't wait for me: profile → safety & reporting has people who can help right away.",
            "ok. do you want to see a picture of my dog?"
        ]
        // 后面接着两条：我回 "yes please!!"，她发来一张照片（一张代替真照片的画），好看看收到的照片是什么样子。
        var founderMessages = founderLines.enumerated().map { index, line in
            ChatMessage(id: "sample-founder-\(index)", text: line, senderUID: founderUID,
                        createdAt: founderAt.addingTimeInterval(Double(index)))
        }
        founderMessages.append(ChatMessage(id: "sample-founder-me", text: "yes please!!", senderUID: chatMe,
                                           createdAt: founderAt.addingTimeInterval(20 * 60)))
        let founderPhotoID = "sample-founder-photo"
        founderMessages.append(ChatMessage(id: founderPhotoID, text: "", senderUID: founderUID,
                                           createdAt: founderAt.addingTimeInterval(22 * 60)))
        let founderChat = ChatPreview(
            me: chatMe,
            messages: founderMessages,
            post: nil,
            standalone: false,
            isFounder: true,
            photos: [founderPhotoID: .placeholder]
        )
        let founderItem = InboxPreview.Item(thread: founderThread, lastMessage: "sent a photo", unread: 0,
                                            lastActivity: founderAt.addingTimeInterval(22 * 60), chat: founderChat)

        // 系统消息那一段（草稿）。她 2026-11-25 18:54：举报之后在 Chats 里收到一条“收到了”，她人工核实之后
        // 再收到一条“处理了”；19:22：样子照 founder 那一段做。这里放了两次举报：一条帖子（昨天，已经处理了）
        // 和一段对话（十分钟前，刚收到）。英文都是草稿，等她看。
        // Here 自己说话用正常的大小写（和 app 里别的字一样），不是 founder 的全小写。
        let systemUID = "sample-system"
        let systemLast = now.addingTimeInterval(-10 * 60)
        let systemThread = ChatThread(
            id: "sample-thread-system",
            postId: nil,
            postTitle: "your reports",
            participants: [chatMe, systemUID],
            createdAt: now.addingTimeInterval(-26 * 3600),
            nickname: "Here"
        )
        let systemLines: [(String, Date)] = [
            ("We got your report about the post “First snow”. Thank you for telling us. We look at every report within 24 hours.",
             now.addingTimeInterval(-26 * 3600)),
            ("We looked into your report about “First snow” and removed the post. Thank you for looking out for everyone here.",
             now.addingTimeInterval(-19 * 3600)),
            ("We got your report about your conversation with soft rain. Thank you for telling us. We look at every report within 24 hours.",
             systemLast)
        ]
        let systemChat = ChatPreview(
            me: chatMe,
            messages: systemLines.enumerated().map { index, line in
                ChatMessage(id: "sample-system-\(index)", text: line.0, senderUID: systemUID, createdAt: line.1)
            },
            post: nil,
            standalone: false,
            isSystem: true
        )
        let systemItem = InboxPreview.Item(thread: systemThread, lastMessage: systemLines[2].0, unread: 1,
                                           lastActivity: systemLast, chat: systemChat)

        return InboxPreview(me: chatMe, items: [
            InboxPreview.Item(thread: unreadThread, lastMessage: "thank you for staying up with me 🌙", unread: 1,
                              lastActivity: now.addingTimeInterval(-4 * 60), chat: chat(postGone: false)),
            InboxPreview.Item(thread: readThread, lastMessage: "thank you for listening", unread: 0,
                              lastActivity: now.addingTimeInterval(-25 * 60), chat: chat(postGone: true, photoStates: true)),
            InboxPreview.Item(thread: decideThread, lastMessage: "take your time", unread: 0,
                              lastActivity: now.addingTimeInterval(-5 * 3600), chat: chat(postGone: true)),
            InboxPreview.Item(thread: waitingThread, lastMessage: "same time tomorrow?", unread: 0,
                              lastActivity: now.addingTimeInterval(-20 * 3600), chat: chat(postGone: true)),
            InboxPreview.Item(thread: endedThread, lastMessage: "take care of yourself tonight", unread: 0,
                              lastActivity: now.addingTimeInterval(-40 * 3600), chat: chat(postGone: true, goneInDays: 5.3)),
            InboxPreview.Item(thread: lapsedThread, lastMessage: "sleep well", unread: 0,
                              lastActivity: now.addingTimeInterval(-53 * 3600), chat: chat(postGone: true, goneInDays: 0.9))
        ], founder: founderItem, system: systemItem)
    }()
}

#endif
