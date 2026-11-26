import SwiftUI
import UIKit
import PhotosUI

// MARK: - 聊天页(进到一个对话里的那一页)
//
// 设计 = 画布上她 11-19 点过头的那一版("聊天页:采用第一版的改进,她满意"),
// 按之后在真机上定的颜色规则校过(Theme.swift):金色只做品牌和光,要读、要按的都是棕色。
//
// 从上到下:
// 1. 顶栏:对方的昵称;下面一个小圆环 + 还剩多久(一直看得到);右边一个盾牌,
//    里面是结束、举报、拉黑。
// 2. 一张小卡片:这段对话是从哪条帖子开始的。点一下能看那条帖子。
// 3. 消息。对方的是白底;我的是最淡的金色底("点亮的东西"),这样一眼分得出谁说的。
//    连着发的几条算一组,一组下面写一次时间;换了一天,中间写一次日期。
// 4. 输入框(1 到 5 行,自己长高)和发送键。
//
// 时间(2026-11-22 她定的):
// - 一段对话 48 小时。顶栏写 "ends in 12h 30m"。
// - 到时间以后对话停住,两个人各自回答要不要再聊 48 小时。这个决定只开放 24 小时。
//   还剩多久,写在那句问话的正下面。不写在顶栏:第一版写在顶栏,她在真机上一眼就说反直觉,
//   "谁会在下面有这个问题,然后跑到最上面去看?"(相关的东西要挨着放。)顶栏这时只写 "time's up"。
//   两个人都选 Yes 就续上;我选了 No,或者 24 小时过了,就结束。
// - 对方选了什么不显示:只写 "Waiting for her to decide...",到点一起结束。
//
// 人称(2026-11-22 她定的):Here 里都是女性,提到对方一律 she / her,
// 不写 they、this person、the other person。
//
// 和画布不一样的只有一处:画布上发送键是金色底。控件上的金色她在真机上全否了
// ("纯黄色特别特别丑"),所以这里是:没字的时候是一个安静的空心圈,有字了变成实心的深棕。
// 依据(claude/here-design-principles.md):发送是这一页最主要的动作,一屏里最显眼的只能有一个;
// 她给发帖按钮选的也是实心的那个("最有存在感")。
//
// 这一页以前的毛病(11-22 量的):小字和背景的对比度只有 2:1 左右(要求 4.5:1)、13–15pt 的细体、
// 发送键 36pt(要求 44pt)、金色的字、双方的气泡长得一样、输入框只有一行。

/// 只给检查面板用:传了就显示这些示例消息,不读也不写后端。正式流程里永远是 nil。
struct ChatPreview {
    let me: String
    let messages: [ChatMessage]
    /// 点 "STARTED FROM" 小卡片时给看的帖子。nil = 帖子已经离开了的样子。
    var post: Post? = nil
    /// true = 从面板里单独打开的,没有上一页,要自己画一个返回。
    /// false = 从示例的 Chats 列表点进来的,系统已经给了返回。
    var standalone = true
    /// true = 和 founder 的对话(草稿)。它不是从帖子开始的,所以顶上不画 "STARTED FROM" 那张小卡片;
    /// 它没有期限,所以顶栏昵称下面不写还剩多久,写 founder。
    var isFounder = false
    /// 哪几条消息是照片(草稿:发图片的后端还没接,现在只有示例里有)。键是消息的 id。
    var photos: [String: ChatPhoto] = [:]
    /// true = 系统消息那一段(草稿)。样子照 founder 那一段(她 2026-11-25 19:22:"系统就完全可以 copy 这个样子"):
    /// 没有 "STARTED FROM" 小卡片,顶栏昵称下面写 system。另外三处不一样,因为这一段只有 Here 在说话:
    /// 没有盾牌(没有可以结束、举报、拉黑的人),没有输入框(回不了),最下面一行小字说明这一点。
    var isSystem = false
    /// 这段结束了的对话什么时候从两个人的列表里消失(草稿)。她 2026-11-25 19:18 定的:彻底结束 7 天后整段删掉。
    /// 现在只有示例里有;真的日期要等后台在对话上记下来。nil = 不写这一行。
    var disappearsAt: Date? = nil
}

/// 一条消息带的图。草稿:她 2026-11-25 17:01 定了"所有人都能发",后端当晚开始做;这里只是先看样子。
enum ChatPhoto {
    /// 从相册里选的(示例里只留在这台手机上)
    case image(UIImage)
    /// 示例里代替一张真照片的画
    case placeholder
    /// 对方发来的图,服务器还没检查完(消息上还没有 imageOK),所以现在不能给我看。只会出现在对方那一边。
    /// 定了(老板 2026-11-25 19:55:"可以啊")。
    case checking
    /// 这张图没通过检查。两边看到的是同一句话
    /// (老板 2026-11-25 19:55:"两边就是看到一样的不就好了吗")。图本身已经删了,这条消息留着。
    case rejected

    // 没有"照片已经删掉、对话还在"这种状态:照片跟着对话走,对话在它就在,对话消失它一起消失
    // (老板 2026-11-25 19:55:"什么叫对话还在,但照片不在了?这我觉得不 make sense")。不要再加回来。

    /// 看不了图的时候,气泡里写的那句话。nil = 有图可看。
    var status: String? {
        switch self {
        case .checking: return "Checking photo…"
        case .rejected: return "Photo didn't pass the check"   // 英文是草稿
        case .image, .placeholder: return nil
        }
    }

    /// 能点开放大的那张图。示例里的画、看不了的图都没有。
    var viewable: UIImage? {
        if case .image(let image) = self { return image }
        return nil
    }
}

/// 点开放大的那一张
private struct ViewedChatPhoto: Identifiable {
    let id = UUID()
    let image: UIImage
}


struct ChatDetailView: View {
    let thread: ChatThread
    @ObservedObject var app: AppState
    var preview: ChatPreview? = nil

    @State private var input = ""
    /// 替这一页拿着输入框背后的系统文本框(发送、清空要直接跟它说)
    @State private var inputController = ChatInputController()
    @State private var showEndedActions = false
    @State private var showBlockConfirm = false
    @State private var showSourcePost = false
    @State private var filterMessage: String?
    @State private var contactWarning: String?
    @State private var pendingText: String?
    /// 示例模式里"发出去"的话只留在这一页,不出这台手机
    @State private var previewSent: [ChatMessage] = []
    /// 示例里从相册选的图(只留在这台手机上)。键是消息的 id。
    @State private var previewPhotos: [String: ChatPhoto] = [:]
    /// 点了哪张照片(全屏看,和帖子里的图同一个查看器)
    @State private var viewedPhoto: ViewedChatPhoto?
    @State private var pickedPhoto: PhotosPickerItem?
    @State private var previewChoice: ContinueChoice?
    @Environment(\.dismiss) private var dismiss

    /// Scroll target that sits after the message list's bottom padding, so
    /// programmatic scrolls land exactly where a manual swipe-to-bottom rests.
    private static let bottomAnchorId = "bottomAnchor"

    private var isPreview: Bool { preview != nil }
    private var uid: String { preview?.me ?? app.uid }
    private var threadId: String { thread.id ?? "" }
    private var messages: [ChatMessage] {
        if let preview { return preview.messages + previewSent }
        return app.messages[threadId] ?? []
    }
    private var myChoice: ContinueChoice { previewChoice ?? thread.myContinueChoice(uid: uid) }
    /// 哪几条消息是照片(现在只有示例里有)
    private var photos: [String: ChatPhoto] {
        (preview?.photos ?? [:]).merging(previewPhotos) { _, picked in picked }
    }
    private var canSend: Bool { !input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    /// 这段对话是从哪条帖子开始的。别人的帖子过了 48 小时就不再给看(和 Feed 一样);
    /// 自己的帖子一直看得到(和个人页的 Archived 一样)。找不到 = 已经离开了。
    private var sourcePost: Post? {
        if let preview { return preview.post }
        guard let postId = thread.postId,
              let post = app.posts.first(where: { $0.id == postId }) else { return nil }
        if post.authorUID != uid, post.expiresAt <= Date() { return nil }
        return post
    }

    var body: some View {
        ZStack {
            // 和发帖页、聊天列表同一张纸
            PaperBackground()

            VStack(spacing: 0) {
                if preview?.isFounder != true && preview?.isSystem != true { startedFromCard }

                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 6) {
                            ForEach(ChatRow.rows(from: messages, uid: uid, photos: photos)) { row in
                                rowView(row)
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.top, 10)
                        .padding(.bottom, 12)

                        Color.clear
                            .frame(height: 1)
                            .id(Self.bottomAnchorId)
                    }
                    .defaultScrollAnchor(.bottom)
                    .scrollDismissesKeyboard(.interactively)
                    // 滚到卡片底下和输入框上面的消息淡出去,不是被一刀切掉
                    .mask {
                        VStack(spacing: 0) {
                            LinearGradient(colors: [.clear, .black], startPoint: .top, endPoint: .bottom)
                                .frame(height: 12)
                            Color.black
                            LinearGradient(colors: [.black, .clear], startPoint: .top, endPoint: .bottom)
                                .frame(height: 12)
                        }
                    }
                    .onChange(of: messages.count) {
                        withAnimation { proxy.scrollTo(Self.bottomAnchorId, anchor: .bottom) }
                        guard !isPreview else { return }
                        // Still in the thread — anything that just arrived counts as
                        // read. Own/system messages never count as unread, so don't
                        // burn a Firestore write re-stamping lastRead for them.
                        if let last = messages.last,
                           last.senderUID != uid, last.senderUID != "system" {
                            Task { await app.markThreadRead(threadId: threadId) }
                        }
                    }
                    .onAppear {
                        // Messages are usually loaded before this view is pushed, so
                        // onChange never fires; the tab-bar hide animation also shifts
                        // layout after defaultScrollAnchor applies. Jump after layout.
                        DispatchQueue.main.async {
                            proxy.scrollTo(Self.bottomAnchorId, anchor: .bottom)
                        }
                        guard !isPreview else { return }
                        PushManager.shared.activeThreadId = threadId
                        // Ended chats keep only their latest message in memory; load the full
                        // history while this one is on screen (reading back, reporting)
                        app.openThread(threadId)
                        Task { await app.markThreadRead(threadId: threadId) }
                    }
                    .onDisappear {
                        guard !isPreview else { return }
                        if PushManager.shared.activeThreadId == threadId {
                            PushManager.shared.activeThreadId = nil
                        }
                        // Left without ever sending — the unsent draft evaporates
                        app.discardDraft(threadId: threadId)
                        app.closeThread(threadId)
                    }
                }

                // 每半分钟看一次钟:到时间了,输入框自己换成"要不要继续";24 小时过了,换成"已结束"
                if preview?.isSystem == true {
                    systemFootnote
                } else {
                    TimelineView(.periodic(from: .now, by: 30)) { context in
                        if phase(at: context.date) == .active {
                            chatInputBar
                        } else {
                            frozenBottomArea(at: context.date)
                        }
                    }
                }
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .principal) { header }

            // 从面板里单独打开的示例没有上一页,自己给一个返回
            if preview?.standalone == true {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "chevron.left")
                    }
                    .accessibilityLabel("Back")
                }
            }

            // 系统消息那一段没有盾牌:没有可以结束、举报、拉黑的人
            if preview?.isSystem != true {
                ToolbarItem(placement: .topBarTrailing) { safetyMenu }
            }
        }
        // 返回、盾牌:都是次要的棕色,不是系统蓝,也不是金色
        .tint(Theme.ink2)
        .alert("Share contact details?", isPresented: Binding(get: { contactWarning != nil },
                                                               set: { if !$0 { contactWarning = nil } })) {
            Button("Send anyway") {
                if let text = pendingText { deliver(text) }
                pendingText = nil
            }
            Button("Cancel", role: .cancel) { pendingText = nil }
        } message: {
            Text(contactWarning ?? "")
        }
        .alert("Can't send this", isPresented: Binding(get: { filterMessage != nil },
                                                        set: { if !$0 { filterMessage = nil } })) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(filterMessage ?? "")
        }
        .alert("Block her?", isPresented: $showBlockConfirm) {
            Button("Block", role: .destructive) {
                if !isPreview {
                    Task { await app.blockUser(in: thread) }
                }
                dismiss()
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("This conversation will end, and you won't see her posts or messages anymore. She won't be notified.")
        }
        .sheet(isPresented: $showEndedActions) {
            ReportSheet(
                title: "Why are you reporting this conversation?",
                message: "Your report is anonymous. The conversation will end, and she won't be told why."
            ) { reasons, details in
                guard !isPreview else { return }
                Task { await app.reportChat(thread: thread, reasons: reasons, details: details) }
            }
        }
        .fullScreenCover(item: $viewedPhoto) { photo in
            FullScreenImageView(imageURL: "", localImage: photo.image) { viewedPhoto = nil }
        }
        .sheet(isPresented: $showSourcePost) {
            let post = sourcePost
            SourcePostSheet(
                title: thread.postTitle,
                post: post,
                isMine: post?.authorUID == uid
            )
            // 有帖子:先露半屏,看一眼就回来,长的话往上拉。
            // 帖子不在了:只有两行字,露一小截就够,不留半屏空白。
            .presentationDetents(post == nil ? [.height(200)] : [.medium, .large])
            .presentationDragIndicator(.visible)
            .presentationBackground(Theme.paper)
        }
    }

    // MARK: - 时间:进行中 / 等两个人决定 / 结束

    private enum Phase { case active, deciding, ended }

    private func phase(at now: Date) -> Phase {
        if !thread.isFrozen(now: now) { return .active }
        // 到时间了、24 小时还没过、我也没说 No:还在等两个人决定
        if thread.isAwaitingDecision(now: now), myChoice != .no { return .deciding }
        return .ended
    }

    /// 顶栏的圆环:只在进行中画,画的是还剩的时间占 48 小时的多少。
    private func remainingFraction(at now: Date) -> Double? {
        guard phase(at: now) == .active else { return nil }
        return min(1, thread.expiresAt.timeIntervalSince(now) / (48 * 60 * 60))
    }

    /// 顶栏那行小字:现在是什么状态。
    private func timeText(at now: Date) -> String {
        switch phase(at: now) {
        case .active:
            return "ends in " + Self.duration(thread.expiresAt.timeIntervalSince(now))
        case .deciding:
            // 还剩多久决定不写在这里,写在下面那句问话旁边(decisionClock)
            return "time's up"
        case .ended:
            return "ended"
        }
    }

    /// "12h 30m";不到一小时只写分钟,最少写 1m
    private static func duration(_ seconds: TimeInterval) -> String {
        let total = max(60, seconds)
        let hours = Int(total / 3600)
        let minutes = Int(total.truncatingRemainder(dividingBy: 3600) / 60)
        return hours == 0 ? "\(minutes)m" : "\(hours)h \(minutes)m"
    }

    // MARK: - 顶栏

    /// 昵称,下面是还剩多久。每半分钟自己更新一次。
    private var header: some View {
        VStack(spacing: 2) {
            Text(thread.nickname)
                .font(Theme.ui(17, .semibold))
                .foregroundColor(Theme.ink)
                .lineLimit(1)

            if preview?.isFounder == true || preview?.isSystem == true {
                // 和 founder 的对话、系统消息都没有期限(草稿):这里不写还剩多久
                Text(preview?.isSystem == true ? "system" : "founder")
                    .font(Theme.ui(12, .medium))
                    .foregroundColor(Theme.ink2)
            } else {
                TimelineView(.periodic(from: .now, by: 30)) { context in
                    HStack(spacing: 6) {
                        if let fraction = remainingFraction(at: context.date) {
                            CountdownRing(fraction: fraction)
                        }
                        Text(timeText(at: context.date))
                            .font(Theme.ui(12, .medium))
                            .foregroundColor(Theme.ink2)
                    }
                }
            }
        }
        .accessibilityElement(children: .combine)
    }

    /// 盾牌:结束、举报、拉黑。都收在这里,不占页面,也不容易误点。
    private var safetyMenu: some View {
        Menu {
            // End without reporting
            Button(role: .destructive) {
                guard !isPreview else { return }
                Task { await app.manualFreezeThread(threadId: threadId) }
            } label: {
                Label("End Conversation", systemImage: "xmark.circle")
            }

            // Report and end — the conversation is only ended once the
            // report is submitted, so cancelling the sheet changes nothing
            Button(role: .destructive) {
                showEndedActions = true
            } label: {
                Label("Report & End", systemImage: "flag")
            }

            Button(role: .destructive) {
                showBlockConfirm = true
            } label: {
                Label("Block & End", systemImage: "hand.raised")
            }
        } label: {
            Image(systemName: "shield")
                .font(.system(size: 17, weight: .regular))
                .foregroundColor(Theme.ink2)
        }
        .accessibilityLabel("Safety and reporting")
    }

    // MARK: - 从哪条帖子开始的

    /// 点一下:从下面升起那条帖子(只读)。右边的小箭头说明它能点。
    private var startedFromCard: some View {
        Button {
            showSourcePost = true
        } label: {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("STARTED FROM")
                        .font(Theme.ui(11, .bold))
                        .tracking(1.1)
                        .foregroundColor(Theme.ink3)
                    Text(thread.postTitle)
                        .font(Theme.ui(15, .semibold))
                        .foregroundColor(Theme.ink)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(Theme.ink3)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color.white.opacity(0.9)))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Theme.hairline, lineWidth: 1))
            .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(PressFade())
        .padding(.horizontal, 16)
        .padding(.top, 6)
        .padding(.bottom, 2)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text(verbatim: "Started from: \(thread.postTitle)"))
        .accessibilityHint("Shows the post")
    }

    // MARK: - 消息

    @ViewBuilder
    private func rowView(_ row: ChatRow) -> some View {
        switch row.kind {
        case .day(let label):
            // 换了一天
            Text(label)
                .font(Theme.ui(11, .bold))
                .tracking(1.1)
                .foregroundColor(Theme.ink2)
                .frame(maxWidth: .infinity)
                .padding(.top, 8)
                .padding(.bottom, 2)

        case .bubble(let text, let isMe, let endsGroup):
            ChatBubble(text: text, isMe: isMe, endsGroup: endsGroup)

        case .photo(let photo, let isMe, let endsGroup):
            if let status = photo.status {
                ChatPhotoStatusBubble(text: status, isMe: isMe, endsGroup: endsGroup)
            } else {
                ChatPhotoBubble(photo: photo, isMe: isMe, endsGroup: endsGroup) {
                    if let image = photo.viewable { viewedPhoto = ViewedChatPhoto(image: image) }
                }
            }

        case .time(let label, let isMe):
            // 一组消息下面写一次时间,靠在说话的人那一边
            Text(label)
                .font(Theme.ui(11, .semibold))
                .tracking(0.3)
                .foregroundColor(Theme.ink2)
                .frame(maxWidth: .infinity, alignment: isMe ? .trailing : .leading)
                .padding(.horizontal, 6)
                .padding(.bottom, 6)

        case .note(let text):
            // 系统说的话(比如"续了 48 小时"):居中的一行小字,不是气泡
            Text(text)
                .font(Theme.ui(12, .medium))
                .foregroundColor(Theme.ink2)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 24)
                .padding(.vertical, 6)
        }
    }

    // MARK: - Sending

    /// Single send path for the arrow button and the keyboard's Send key.
    private func send() {
        // 先让键盘把没落定的字落定,再读输入框里现在真正的字
        let text = inputController.settledText().trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        switch ContentFilter.check(.message, text) {
        case .blocked(let reason):
            filterMessage = reason   // keep the text so they can edit it
            return
        case .confirm(let warning):
            pendingText = text
            contactWarning = warning
            return
        case .ok:
            break
        }
        deliver(text)
    }

    /// 发出去,并且把输入框当面清空(为什么要"当面":见最下面 ChatInputField 的说明)。
    private func deliver(_ text: String) {
        inputController.clear()
        input = ""
        if isPreview {
            previewSent.append(ChatMessage(id: "preview-sent-\(previewSent.count)", text: text, senderUID: uid))
            return
        }
        Task { await app.sendMessage(threadId: threadId, text: text) }
    }

    // MARK: - Input Bar

    /// 选图的按钮现在只在示例里出现:发图片的后端还没接,正式流程里先不露出来。
    private var showsPhotoButton: Bool { isPreview }

    /// 示例里:从相册选的那张图当成我发的一条消息,只留在这台手机上
    private func addPreviewPhoto(_ image: UIImage) {
        let id = "preview-photo-\(previewSent.count)"
        previewPhotos[id] = .image(image)
        previewSent.append(ChatMessage(id: id, text: "", senderUID: uid))
    }

    private var chatInputBar: some View {
        HStack(alignment: .bottom, spacing: 10) {
            if showsPhotoButton {
                // 选图的按钮:输入框左边,和发送键一样大的一个安静的圆按钮。
                // 定了(老板 2026-11-25 17:28 选的 A)。另一种——放在输入框里面的右端——她没要,不要再拿出来。
                PhotosPicker(selection: $pickedPhoto, matching: .images) {
                    Image(systemName: "photo")
                        .font(.system(size: 18, weight: .regular))
                        .foregroundColor(Theme.ink2)
                        .frame(width: 48, height: 48)
                        .background(Circle().fill(Color.white.opacity(0.6)))
                        .overlay(Circle().strokeBorder(Theme.outline, lineWidth: 1))
                        .contentShape(Circle())
                }
                .buttonStyle(PressFade())
                .accessibilityLabel("Send a photo")
            }

            // 一行起步,字多了自己长高,最多五行,再多就在框里滚
            ZStack(alignment: .topLeading) {
                if input.isEmpty {
                    Text("say something kind…")
                        .font(Theme.ui(16))
                        .foregroundColor(Theme.ink3)
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                }
                ChatInputField(text: $input, controller: inputController, onSend: send)
                    .frame(minWidth: 0, maxWidth: .infinity)
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 13)
            .frame(minHeight: 48)
            .background(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(Color.white)
                    // 字四周那一圈留白也是输入框:点那里一样开始打字
                    .onTapGesture { inputController.focus() }
            )
            .overlay(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .strokeBorder(Theme.outline, lineWidth: 1)
                    .allowsHitTesting(false)
            )

            Button {
                send()
            } label: {
                // 没字:安静的空心圈。有字:实心的深棕,这一页最显眼的东西。
                Image(systemName: "arrow.up")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(canSend ? Theme.paper : Theme.tabOff)
                    .frame(width: 48, height: 48)
                    .background(Circle().fill(canSend ? Theme.ink : Color.white.opacity(0.6)))
                    .overlay(Circle().strokeBorder(canSend ? Color.clear : Theme.outline, lineWidth: 1))
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .disabled(!canSend)
            .animation(.easeInOut(duration: 0.15), value: canSend)
            .accessibilityLabel("Send")
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .padding(.bottom, 10)
        .onChange(of: pickedPhoto) {
            guard let item = pickedPhoto else { return }
            pickedPhoto = nil
            Task {
                // 示例里:读出选的那张图,当成我发的一条消息
                if let data = try? await item.loadTransferable(type: Data.self),
                   let image = UIImage(data: data) {
                    await MainActor.run { addPreviewPhoto(image) }
                }
            }
        }
    }

    /// 系统消息那一段的最下面:这里回不了,所以没有输入框,只有一行小字说清楚。
    /// 草稿:这句英文等她看。
    private var systemFootnote: some View {
        Text("Updates from Here. You can't reply to these.")
            .font(Theme.ui(12, .medium))
            .foregroundColor(Theme.ink3)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 24)
            .padding(.top, 10)
            .padding(.bottom, 14)
    }

    // MARK: - Frozen Bottom Area

    private func frozenBottomArea(at now: Date) -> some View {
        VStack(spacing: 14) {
            if phase(at: now) == .deciding {
                if myChoice == .yes {
                    // 钟紧贴着它说的那句话:中间只留 6pt
                    VStack(spacing: 6) {
                        endedLine("Waiting for her to decide...")
                        decisionClock(at: now, "left")
                    }
                } else {
                    VStack(spacing: 6) {
                        Text("Continue this conversation for another 48 hours?")
                            .font(Theme.ui(15))
                            .foregroundColor(Theme.ink)
                            .multilineTextAlignment(.center)
                        decisionClock(at: now, "left to decide")
                    }

                    // 两个按钮一样大、一样重:要不要继续由她自己定,不替她选
                    HStack(spacing: 12) {
                        choiceButton("No", .no)
                        choiceButton("Yes", .yes)
                    }
                }
            } else {
                VStack(spacing: 6) {
                    endedLine("This conversation has ended.")
                    // 还有几天消失:提前说清楚,免得哪天突然没了(草稿,英文等她看)
                    if let line = disappearsLine(at: now) {
                        Text(line)
                            .font(Theme.ui(12, .medium))
                            .foregroundColor(Theme.ink3)
                            .multilineTextAlignment(.center)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 24)
        .padding(.top, 14)
        .padding(.bottom, 18)
    }

    /// 还剩多久可以决定:一个小沙漏 + "23h 29m left to decide"。
    /// 挨着那句问话放:问题在哪,钟就在哪。
    /// 这里用沙漏,不用顶栏那个小圆环:刚到时间的时候圆环是满的,满的圆环看着像字母 O。
    private func decisionClock(at now: Date, _ suffix: String) -> some View {
        let remaining = thread.decisionDeadline.timeIntervalSince(now)
        return HStack(spacing: 5) {
            Image(systemName: "hourglass")
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(Theme.ink2)
                .accessibilityHidden(true)
            Text(Self.duration(remaining) + " " + suffix)
                .font(Theme.ui(13, .medium))
                .foregroundColor(Theme.ink2)
        }
        .accessibilityElement(children: .combine)
    }

    /// "还有几天消失"那一行:当天写 today,第二天写 tomorrow,再往后写还有几天。
    private func disappearsLine(at now: Date) -> String? {
        // 示例里用示例的日期；真的对话用服务器写在对话上的那个日期（还没写就不显示这一行）
        guard let date = preview?.disappearsAt ?? thread.deleteAfter else { return nil }
        guard date > now else { return nil }
        // 按日历上的天数算(今天、明天、再往后数几天),这样每过一个半夜数字正好少 1,不会跳着变
        let calendar = Calendar.current
        let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: now),
                                           to: calendar.startOfDay(for: date)).day ?? 0
        if days <= 0 { return "It disappears today." }
        if days == 1 { return "It disappears tomorrow." }
        return "It disappears in \(days) days."
    }

    private func endedLine(_ text: String) -> some View {
        Text(text)
            .font(Theme.ui(15))
            .foregroundColor(Theme.ink2)
            .multilineTextAlignment(.center)
    }

    /// 和确认页的 Yes / No 同一种按钮:透一点底下的纸,一圈棕色的线
    private func choiceButton(_ title: String, _ choice: ContinueChoice) -> some View {
        Button {
            if isPreview {
                previewChoice = choice
                return
            }
            Task {
                await app.setContinueChoice(threadId: threadId, choice: choice)
            }
        } label: {
            Text(title)
                .font(Theme.ui(16, .medium))
                .foregroundColor(Theme.ink)
                .frame(maxWidth: .infinity)
                .frame(height: 48)
                .background(Capsule().fill(Color.white.opacity(0.6)))
                .overlay(Capsule().strokeBorder(Theme.line, lineWidth: 1))
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - 还剩多久的小圆环
private struct CountdownRing: View {
    let fraction: Double

    var body: some View {
        ZStack {
            Circle().stroke(Theme.outline, lineWidth: 2)
            Circle()
                .trim(from: 0, to: max(0.03, fraction))
                .stroke(Theme.ink2, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
        .frame(width: 12, height: 12)
        .accessibilityHidden(true)
    }
}

// MARK: - 一个气泡
private struct ChatBubble: View {
    let text: String
    let isMe: Bool
    /// 一组里的最后一条:靠说话的人那一侧的下角收小,像一个小尾巴
    let endsGroup: Bool

    private var shape: UnevenRoundedRectangle {
        UnevenRoundedRectangle(
            cornerRadii: RectangleCornerRadii(
                topLeading: 20,
                bottomLeading: (!isMe && endsGroup) ? 6 : 20,
                bottomTrailing: (isMe && endsGroup) ? 6 : 20,
                topTrailing: 20
            ),
            style: .continuous
        )
    }

    var body: some View {
        HStack(spacing: 0) {
            if isMe { Spacer(minLength: 0) }

            Text(text)
                .font(Theme.ui(16))
                .lineSpacing(3)
                .foregroundColor(Theme.ink)
                .padding(.horizontal, 15)
                .padding(.vertical, 11)
                // 对方:白底、极淡的线。我:最淡的金色底、稍深一点的线。
                .background(shape.fill(isMe ? Theme.selectedFill : Color.white))
                .overlay(shape.strokeBorder(isMe ? Theme.outline : Theme.hairline, lineWidth: 1))
                // 一个气泡最宽 292pt,长的话在里面换行
                .frame(maxWidth: 292, alignment: isMe ? .trailing : .leading)

            if !isMe { Spacer(minLength: 0) }
        }
    }
}

// MARK: - 一张照片的气泡(草稿)
/// 和文字气泡同一个形状(同样的圆角、同样的小尾巴、同样一圈细线),里面是一张图。
/// 宽度固定 220pt;高度跟着照片的比例走,最矮 150、最高 290,超出的部分裁掉。
private struct ChatPhotoBubble: View {
    let photo: ChatPhoto
    let isMe: Bool
    let endsGroup: Bool
    /// 点一下:全屏看这张图
    var onTap: () -> Void = {}

    private static let width: CGFloat = 220

    private var shape: UnevenRoundedRectangle {
        UnevenRoundedRectangle(
            cornerRadii: RectangleCornerRadii(
                topLeading: 20,
                bottomLeading: (!isMe && endsGroup) ? 6 : 20,
                bottomTrailing: (isMe && endsGroup) ? 6 : 20,
                topTrailing: 20
            ),
            style: .continuous
        )
    }

    /// 能点开的照片对读屏来说是一个按钮
    private var traits: AccessibilityTraits { photo.viewable == nil ? [] : .isButton }

    private var height: CGFloat {
        guard case .image(let image) = photo, image.size.width > 0 else { return Self.width }
        return min(max(Self.width * image.size.height / image.size.width, 150), 290)
    }

    var body: some View {
        HStack(spacing: 0) {
            if isMe { Spacer(minLength: 0) }

            content
                .frame(width: Self.width, height: height)
                .clipShape(shape)
                .overlay(shape.strokeBorder(Theme.outline, lineWidth: 1))
                .contentShape(shape)
                .onTapGesture(perform: onTap)
                .accessibilityLabel("Photo")
                .accessibilityAddTraits(traits)

            if !isMe { Spacer(minLength: 0) }
        }
    }

    @ViewBuilder
    private var content: some View {
        switch photo {
        case .image(let image):
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
        case .placeholder:
            // 示例里代替一张真照片:一块暖色,中间一个小爪印
            ZStack {
                LinearGradient(colors: [Theme.champagne, Theme.hereFill], startPoint: .topLeading, endPoint: .bottomTrailing)
                Image(systemName: "pawprint.fill")
                    .font(.system(size: 54))
                    .foregroundColor(Color.white.opacity(0.9))
            }
        case .checking, .rejected:
            // 这两种不画图,画的是下面那个小气泡
            Color.clear
        }
    }
}

// MARK: - 看不了图时的小气泡(草稿)
/// 和文字气泡一模一样的形状、底色、边线(所以一眼看得出是谁发的),
/// 里面是一个小照片图标加一句话,字用第二档棕色(比消息的字淡):它是在说明情况,不是谁说的话。
/// 两种情况用同一个样子:对方的图还在检查;这张图没通过检查(两边都是这一句)。
private struct ChatPhotoStatusBubble: View {
    let text: String
    let isMe: Bool
    let endsGroup: Bool

    private var shape: UnevenRoundedRectangle {
        UnevenRoundedRectangle(
            cornerRadii: RectangleCornerRadii(
                topLeading: 20,
                bottomLeading: (!isMe && endsGroup) ? 6 : 20,
                bottomTrailing: (isMe && endsGroup) ? 6 : 20,
                topTrailing: 20
            ),
            style: .continuous
        )
    }

    var body: some View {
        HStack(spacing: 0) {
            if isMe { Spacer(minLength: 0) }

            HStack(spacing: 8) {
                Image(systemName: "photo")
                    .font(.system(size: 14, weight: .medium))
                Text(text)
                    .font(Theme.ui(15))
            }
            // ink2:在白底上 5.6:1、在我这边的淡金底上 5.2:1(再淡一档的 ink3 在淡金底上只有 4.3:1,不够)
            .foregroundColor(Theme.ink2)
            .padding(.horizontal, 15)
            .padding(.vertical, 11)
            .background(shape.fill(isMe ? Theme.selectedFill : Color.white))
            .overlay(shape.strokeBorder(isMe ? Theme.outline : Theme.hairline, lineWidth: 1))
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(text)

            if !isMe { Spacer(minLength: 0) }
        }
    }
}

// MARK: - 点开"从哪条帖子开始的"
/// 只读:标签、标题、正文、图片,和 Feed 里同一个样子。
/// 这里没有 here、聊天、举报:那些在帖子页和盾牌里。
private struct SourcePostSheet: View {
    /// 对话里记下的标题:帖子不在了也还有它
    let title: String
    /// nil = 帖子已经离开了(过了 48 小时,或者被删了)
    let post: Post?
    let isMine: Bool

    @State private var selectedImageURL: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                // 这是谁写的。都是女性,所以写 she。
                Text(post == nil ? "STARTED FROM" : (isMine ? "YOU WROTE" : "SHE WROTE"))
                    .font(Theme.ui(11, .bold))
                    .tracking(1.1)
                    .foregroundColor(Theme.ink3)

                if let post {
                    let tags = post.tags.filter(\.isEmojiOnly)
                    if !tags.isEmpty {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 6) {
                                ForEach(tags, id: \.self) { tag in
                                    Text(tag)
                                        .font(.system(size: 15))
                                        .padding(.horizontal, 10)
                                        .frame(height: 30)
                                        .background(Capsule().fill(Color.white.opacity(0.85)))
                                        .overlay(Capsule().stroke(Theme.outline, lineWidth: 1))
                                }
                            }
                            .padding(.vertical, 1)
                        }
                    }

                    // 标题的粗细跟帖子页走(中等,她 2026-11-23 17:37 定的):同一条帖子不能两个样子
                    Text(post.title)
                        .font(Theme.ui(28, .medium))
                        .foregroundColor(Theme.ink)

                    if !post.bodyText.isEmpty {
                        Text(post.bodyText)
                            .font(Theme.ui(17))
                            .foregroundColor(Theme.ink2)
                            .lineSpacing(7)
                    }

                    if !post.imageURLs.isEmpty {
                        ImageGridView(
                            imageURLs: post.imageURLs,
                            onImageTap: { urlString in
                                selectedImageURL = urlString
                            }
                        )
                    }
                } else {
                    Text(title)
                        .font(Theme.ui(28, .medium))
                        .foregroundColor(Theme.ink)

                    // 和发帖页那句 "Leaves the feed after 48 hours." 是一个说法
                    Text("This post has left the feed. Posts stay for 48 hours.")
                        .font(Theme.ui(15))
                        .foregroundColor(Theme.ink2)
                        .lineSpacing(4)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 28)
            .padding(.top, 36)
            .padding(.bottom, 28)
        }
        .fullScreenCover(item: Binding(
            get: { selectedImageURL.map { FullScreenImageItem(url: $0) } },
            set: { selectedImageURL = $0?.url }
        )) { item in
            FullScreenImageView(imageURL: item.url) {
                selectedImageURL = nil
            }
        }
    }
}

// MARK: - 输入框
//
// 为什么不用 SwiftUI 自带的 TextField:
// 她在真机上发现(11-22,英文键盘,点的是页面上的箭头):消息发出去了,字还留在输入框里。
// 模拟器里重现不出来(英文、拼音、箭头、键盘上的发送键都试过,都会清空)。
// 最可能的原因:真机的键盘是另一个进程。点发送的那一刻,键盘手里还有一个没落定的"自动改错",
// 它晚一步才把字写回来,正好落在我们清空之后。SwiftUI 的 TextField 不让我们碰它背后的文本框,
// 只能"清一次、下一拍再清一次"地碰运气(以前的 Issue #14 就是这么修的,没修住)。
//
// 这里直接用系统的文本框,三件事自己做:
// 1. 发送前:先让键盘把没落定的字落定(拼音没选的字、等着的自动改错),再读出真正的字。
// 2. 发送后:当面把文本框清空。系统文本框被程序改了字会通知键盘,键盘就不会再拿旧的字来写。
// 3. 再加一道保险:刚发完的半秒里,如果键盘还是把一整段字写回来,不收。一个一个打的字照常。
//
// 顺带:键盘上的 Send 键 = 发送,键盘不收起(连着发几条不用每次重新点输入框)。

/// 替页面拿着输入框背后的系统文本框。
@MainActor
final class ChatInputController {
    fileprivate weak var textView: UITextView?
    /// 刚发完一条的那一刻
    fileprivate var sentAt = Date.distantPast
    /// 发完以后用户有没有自己打过字(打过了,保险就不再管)
    fileprivate var typedSinceSend = true

    /// 和 Theme.ui(16) 同一个字:SF Pro Rounded 16
    fileprivate static let font: UIFont = {
        let base = UIFont.systemFont(ofSize: 16, weight: .regular)
        guard let rounded = base.fontDescriptor.withDesign(.rounded) else { return base }
        return UIFont(descriptor: rounded, size: 16)
    }()
    fileprivate static let maxLines = 5

    fileprivate var isJustAfterSend: Bool { Date().timeIntervalSince(sentAt) < 0.5 }

    /// 让键盘把手里没落定的东西落定,再读出输入框里现在的字。
    func settledText() -> String {
        guard let view = textView else { return "" }
        if view.markedTextRange != nil { view.unmarkText() }
        // 告诉键盘"光标要动了":它会把等着的自动改错收掉
        view.inputDelegate?.selectionWillChange(view)
        view.inputDelegate?.selectionDidChange(view)
        return view.text ?? ""
    }

    /// 当面清空。
    func clear() {
        sentAt = Date()
        typedSinceSend = false
        guard let view = textView else { return }
        view.text = ""
        view.undoManager?.removeAllActions()
        refreshHeight()
    }

    func focus() {
        _ = textView?.becomeFirstResponder()
    }

    /// 超过五行就在框里滚;没超过就不滚(跟着长高)。然后请 SwiftUI 重新量一次高度。
    fileprivate func refreshHeight() {
        guard let view = textView else { return }
        let width = view.bounds.width
        if width > 1 {
            let fitting = view.sizeThatFits(CGSize(width: width, height: .greatestFiniteMagnitude)).height
            let tooTall = fitting > Self.font.lineHeight * CGFloat(Self.maxLines) + 0.5
            if view.isScrollEnabled != tooTall { view.isScrollEnabled = tooTall }
        }
        view.invalidateIntrinsicContentSize()
    }
}

struct ChatInputField: UIViewRepresentable {
    @Binding var text: String
    let controller: ChatInputController
    let onSend: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeUIView(context: Context) -> UITextView {
        let view = UITextView()
        view.delegate = context.coordinator
        view.backgroundColor = .clear
        view.font = ChatInputController.font
        view.textColor = Theme.inkUIColor
        view.tintColor = UIColor(Theme.ink2)     // 光标:次要的棕色
        view.textContainerInset = .zero
        view.textContainer.lineFragmentPadding = 0
        view.isScrollEnabled = false
        view.showsVerticalScrollIndicator = false
        view.returnKeyType = .send
        view.enablesReturnKeyAutomatically = true
        view.accessibilityLabel = "Message"
        // 宽度听外面的,不要被自己的字撑开
        view.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        controller.textView = view
        return view
    }

    func updateUIView(_ view: UITextView, context: Context) {
        // 字只从里往外走(打字 → text)。要清空走 controller.clear(),当面清。
        context.coordinator.parent = self
    }

    /// 宽度:给多少用多少。高度:一行到五行。
    func sizeThatFits(_ proposal: ProposedViewSize, uiView: UITextView, context: Context) -> CGSize? {
        let line = ChatInputController.font.lineHeight
        guard let width = proposal.width, width.isFinite, width > 1 else {
            return CGSize(width: 1, height: line.rounded(.up))
        }
        let fitting = uiView.sizeThatFits(CGSize(width: width, height: .greatestFiniteMagnitude)).height
        let height = min(max(fitting, line), line * CGFloat(ChatInputController.maxLines))
        return CGSize(width: width, height: height.rounded(.up))
    }

    final class Coordinator: NSObject, UITextViewDelegate {
        var parent: ChatInputField

        init(_ parent: ChatInputField) {
            self.parent = parent
        }

        func textView(_ textView: UITextView, shouldChangeTextIn range: NSRange, replacementText text: String) -> Bool {
            // 键盘上的 Send:发送,键盘留着
            if text == "\n" {
                parent.onSend()
                return false
            }
            let controller = parent.controller
            if controller.isJustAfterSend {
                // 刚发完的半秒里,键盘把一整段字写回来(晚到的自动改错):不收
                if text.count > 1 { return false }
                controller.typedSinceSend = true
            }
            return true
        }

        func textViewDidChange(_ textView: UITextView) {
            let controller = parent.controller
            // 同一道保险的另一半:没经过上面那一步就冒出来的字,也清掉
            if controller.isJustAfterSend, !controller.typedSinceSend, !textView.text.isEmpty {
                textView.text = ""
            }
            if parent.text != textView.text {
                parent.text = textView.text
            }
            controller.refreshHeight()
        }
    }
}

// MARK: - 把消息排成一行一行要画的东西
/// 日期、气泡、一组下面的时间、系统说的话。
private struct ChatRow: Identifiable {
    enum Kind {
        case day(String)
        case bubble(text: String, isMe: Bool, endsGroup: Bool)
        case photo(ChatPhoto, isMe: Bool, endsGroup: Bool)
        case time(String, isMe: Bool)
        case note(String)
    }

    let id: String
    let kind: Kind

    /// 连着、同一个人、间隔不到 5 分钟的几条算一组。
    static func rows(from messages: [ChatMessage], uid: String, photos: [String: ChatPhoto] = [:]) -> [ChatRow] {
        let calendar = Calendar.current
        // "Started from: …" 那条系统消息不再画:上面那张小卡片已经说了
        let visible = messages.filter { !($0.senderUID == "system" && $0.text.hasPrefix("Started from:")) }

        var rows: [ChatRow] = []
        var lastDay: Date?
        for (index, message) in visible.enumerated() {
            let key = message.id ?? "local-\(index)"
            let day = calendar.startOfDay(for: message.createdAt)
            if lastDay != day {
                rows.append(ChatRow(id: "day-\(index)-\(key)", kind: .day(dayLabel(day, calendar: calendar))))
                lastDay = day
            }

            if message.senderUID == "system" {
                rows.append(ChatRow(id: "note-\(key)", kind: .note(message.text)))
                continue
            }

            let isMe = message.senderUID == uid
            var endsGroup = true
            if index + 1 < visible.count {
                let next = visible[index + 1]
                endsGroup = next.senderUID != message.senderUID
                    || calendar.startOfDay(for: next.createdAt) != day
                    || next.createdAt.timeIntervalSince(message.createdAt) > 5 * 60
            }

            if let photo = photos[key] {
                rows.append(ChatRow(id: "msg-\(key)", kind: .photo(photo, isMe: isMe, endsGroup: endsGroup)))
            } else {
                rows.append(ChatRow(id: "msg-\(key)", kind: .bubble(text: message.text, isMe: isMe, endsGroup: endsGroup)))
            }
            if endsGroup {
                let time = message.createdAt.formatted(date: .omitted, time: .shortened)
                rows.append(ChatRow(id: "time-\(key)", kind: .time(time, isMe: isMe)))
            }
        }
        return rows
    }

    private static func dayLabel(_ day: Date, calendar: Calendar) -> String {
        if calendar.isDateInToday(day) { return "TODAY" }
        if calendar.isDateInYesterday(day) { return "YESTERDAY" }
        return day.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day()).uppercased()
    }
}

#Preview {
    NavigationStack {
        ChatDetailView(
            thread: ChatThread(
                postTitle: "Wandering Soul",
                participants: ["me", "other"]
            ),
            app: AppState(authService: AuthService())
        )
    }
}
