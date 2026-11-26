import SwiftUI
import FirebaseFirestore
import UserNotifications

@MainActor
final class AppState: ObservableObject {
    static let chatTTL: TimeInterval = 48 * 60 * 60

    private let db = Firestore.firestore()
    /// Feed: other people's live posts (and, until the private-posts index exists, the fallback query)
    private var feedListener: ListenerRegistration?
    /// The user's own posts, all of them — My Posts (Active / Archived) needs the expired ones too
    private var myPostsListener: ListenerRegistration?
    private var threadsListener: ListenerRegistration?
    private var userListener: ListenerRegistration?
    private var configListener: ListenerRegistration?
    private var messageListeners: [String: ListenerRegistration] = [:]
    /// Which threads currently have their full message history loaded (vs. only the latest message)
    private var fullHistoryThreads: Set<String> = []
    /// Threads open on screen right now — these always get full history
    private var openThreadIds: Set<String> = []

    private var feedPosts: [Post] = [] { didSet { mergePosts() } }
    private var ownPosts: [Post] = [] { didSet { mergePosts() } }

    var authService: AuthService

    /// Live feed posts plus all of the user's own posts (deduplicated). Everything that used to read
    /// the whole collection reads this, so the views didn't need to change.
    @Published var posts: [Post] = []
    @Published var threads: [ChatThread] = []
    @Published var messages: [String: [ChatMessage]] = [:]  // threadId -> messages

    /// Voice tab presence ("open to connect" toggle + live count). Lives here,
    /// not in VoiceView, so the toggle survives switching tabs.
    let voice = VoicePresenceService()

    /// A chat the sender has opened but not yet written in. Lives only on this
    /// device — nothing is created in Firestore (so the other person sees
    /// nothing) until the first message is sent. Discarded if they back out.
    @Published var draftThread: ChatThread?

    /// config/app:每台手机都要知道、谁也不能从手机上改的那几样(firestore.rules)。
    /// 还没读到、或者后台还没建这个文档时是 nil:那就没有 founder 对话,发图照常开着。
    @Published private(set) var appConfig: AppConfig?

    var uid: String { authService.uid ?? "" }

    init(authService: AuthService) {
        self.authService = authService
    }

    // MARK: - Listeners

    func startListening() {
        listenToConfig()
        listenToUser()
        listenToFeed()
        listenToMyPosts()
        listenToThreads()
        voice.start(uid: uid)
    }

    func stopListening() {
        voice.stop()
        configListener?.remove()
        configListener = nil
        userListener?.remove()
        userDocLoaded = false
        acceptedTermsVersion = nil
        isDeletingAccount = false
        feedListener?.remove()
        feedListener = nil
        myPostsListener?.remove()
        myPostsListener = nil
        feedPosts = []
        ownPosts = []
        threadsListener?.remove()
        messageListeners.values.forEach { $0.remove() }
        messageListeners.removeAll()
        fullHistoryThreads.removeAll()
        messages.removeAll()
        lastSyncedBadge = nil
    }

    // MARK: Config

    private func listenToConfig() {
        configListener?.remove()
        configListener = db.collection("config").document("app")
            .addSnapshotListener { [weak self] snapshot, _ in
                guard let self, let snapshot else { return }
                self.appConfig = snapshot.exists ? (try? snapshot.data(as: AppConfig.self)) : nil
            }
    }

    // MARK: Posts
    //
    // The feed used to listen to the entire posts collection — every post ever written, including
    // long-expired ones and other people's private ("just for me") posts — and filter on the phone.
    // That grows without limit and sends private posts to every device. Now:
    //   - the feed asks only for public posts that haven't expired yet
    //   - the user's own posts (any age, private or not) come from a separate query
    // Nothing on the server is deleted or hidden from moderation by this; it only changes what
    // each phone downloads.

    private func listenToFeed() {
        let now = Timestamp(date: Date())
        // Public + not expired. Needs a composite index (isPrivate, expiresAt). Until that index
        // exists Firestore rejects the query with FAILED_PRECONDITION, so fall back to
        // "not expired" only (private ones are still filtered out in the UI, as before).
        feedListener = db.collection("posts")
            .whereField("isPrivate", isEqualTo: false)
            .whereField("expiresAt", isGreaterThan: now)
            .addSnapshotListener { [weak self] snapshot, error in
                guard let self else { return }
                if let error {
                    let ns = error as NSError
                    print("Feed listener error: \(ns.localizedDescription)")
                    if ns.domain == FirestoreErrorDomain && ns.code == 9 {   // 9 = FAILED_PRECONDITION (index missing)
                        self.feedListener?.remove()
                        self.listenToFeedWithoutIndex(since: now)
                    }
                    return
                }
                guard let docs = snapshot?.documents else { return }
                self.feedPosts = docs.compactMap { try? $0.data(as: Post.self) }
            }
    }

    private func listenToFeedWithoutIndex(since now: Timestamp) {
        feedListener = db.collection("posts")
            .whereField("expiresAt", isGreaterThan: now)
            .addSnapshotListener { [weak self] snapshot, error in
                if let error {
                    print("Feed (fallback) listener error: \(error.localizedDescription)")
                    return
                }
                guard let docs = snapshot?.documents else { return }
                self?.feedPosts = docs.compactMap { try? $0.data(as: Post.self) }
            }
    }

    private func listenToMyPosts() {
        guard !uid.isEmpty else { return }
        myPostsListener = db.collection("posts")
            .whereField("authorUID", isEqualTo: uid)
            .addSnapshotListener { [weak self] snapshot, error in
                if let error {
                    print("My posts listener error: \(error.localizedDescription)")
                    return
                }
                guard let docs = snapshot?.documents else { return }
                self?.ownPosts = docs.compactMap { try? $0.data(as: Post.self) }
            }
    }

    private func mergePosts() {
        var byId: [String: Post] = [:]
        var unkeyed: [Post] = []
        for post in feedPosts + ownPosts {      // own posts win on duplicates (they're the fresher copy)
            if let id = post.id { byId[id] = post } else { unkeyed.append(post) }
        }
        posts = (Array(byId.values) + unkeyed).sorted { $0.createdAt > $1.createdAt }
    }

    private func listenToThreads() {
        guard !uid.isEmpty else { return }

        threadsListener = db.collection("threads")
            .whereField("participants", arrayContains: uid)
            .order(by: "createdAt", descending: true)
            .addSnapshotListener { [weak self] snapshot, error in
                guard let self, let docs = snapshot?.documents else { return }
                self.threads = docs.compactMap { try? $0.data(as: ChatThread.self) }
                self.refreshMessageListeners()
                self.syncBadge()
            }
    }

    // MARK: Messages
    //
    // Active conversations (and any conversation open on screen) keep their full history live.
    // Ended conversations only need their latest message for the inbox row, so they listen to
    // just that — the full history is loaded again the moment the user opens one, so reading it
    // back and reporting from it work exactly as before.

    private func wantsFullHistory(_ thread: ChatThread) -> Bool {
        guard let id = thread.id else { return false }
        return !thread.isFrozen() || openThreadIds.contains(id)
    }

    private func refreshMessageListeners() {
        let current = Dictionary(threads.compactMap { t in t.id.map { ($0, t) } }, uniquingKeysWith: { a, _ in a })
        // Threads that disappeared (deleted, or no longer ours): stop listening, free their messages
        for id in Array(messageListeners.keys) where current[id] == nil {
            messageListeners[id]?.remove()
            messageListeners[id] = nil
            fullHistoryThreads.remove(id)
            messages[id] = nil
        }
        for (id, thread) in current {
            let full = wantsFullHistory(thread)
            if messageListeners[id] == nil || fullHistoryThreads.contains(id) != full {
                listenToMessages(threadId: id, fullHistory: full)
            }
        }
    }

    private func listenToMessages(threadId: String, fullHistory: Bool) {
        messageListeners[threadId]?.remove()
        if fullHistory { fullHistoryThreads.insert(threadId) } else { fullHistoryThreads.remove(threadId) }
        var query: Query = db.collection("threads").document(threadId)
            .collection("messages")
            .order(by: "createdAt", descending: false)
        if !fullHistory {
            query = query.limit(toLast: 1)
        }
        messageListeners[threadId] = query.addSnapshotListener { [weak self] snapshot, error in
            guard let docs = snapshot?.documents else { return }
            let msgs = docs.compactMap { try? $0.data(as: ChatMessage.self) }
            self?.messages[threadId] = msgs
            self?.syncBadge()
        }
    }

    /// Called when a conversation is shown — guarantees its full history is loaded.
    func openThread(_ threadId: String) {
        guard !threadId.isEmpty else { return }
        openThreadIds.insert(threadId)
        if threads.contains(where: { $0.id == threadId }), !fullHistoryThreads.contains(threadId) {
            listenToMessages(threadId: threadId, fullHistory: true)
        }
    }

    /// Called when a conversation is closed — an ended one goes back to "latest message only".
    func closeThread(_ threadId: String) {
        openThreadIds.remove(threadId)
        refreshMessageListeners()
    }

    // MARK: - Unread

    /// When the conversation last had activity — its newest message, or the
    /// thread's creation time before anyone has written.
    func lastActivity(of thread: ChatThread) -> Date {
        guard let threadId = thread.id else { return thread.createdAt }
        return messages[threadId]?.last?.createdAt ?? thread.createdAt
    }

    func unreadCount(in thread: ChatThread) -> Int {
        guard let threadId = thread.id, !uid.isEmpty else { return 0 }
        let lastRead = thread.lastRead[uid] ?? .distantPast
        return (messages[threadId] ?? [])
            .filter { $0.senderUID != uid && $0.senderUID != "system" && $0.createdAt > lastRead }
            .count
    }

    /// iMessage-style: number of conversations with unread messages,
    /// not the total message count.
    /// Ended chats are excluded: the list shows them as "ended" with no unread
    /// dot, so counting them leaves a badge the user can never clear.
    var unreadThreadCount: Int {
        visibleThreads.filter { !$0.isFrozen() && unreadCount(in: $0) > 0 }.count
    }

    /// 到时间了、还在那 24 小时里、我还没回答"要不要继续"的对话有几段。
    /// 底栏 Chats 上的数字把它们也算上:不然不点进 Chats 就不知道有一段在等自己,24 小时过了它就没了。
    /// (不并进 unreadThreadCount:那个数还管桌面图标和推送的角标,只在收到消息时同步。)
    var pendingDecisionCount: Int {
        visibleThreads.filter {
            $0.isAwaitingDecision() && $0.myContinueChoice(uid: uid) == .undecided
        }.count
    }

    /// Stamps "read up to now" for the current user on a thread.
    func markThreadRead(threadId: String) async {
        // Drafts have no Firestore document yet — nothing to stamp
        guard !uid.isEmpty, threads.contains(where: { $0.id == threadId }) else { return }
        do {
            try await db.collection("threads").document(threadId).updateData([
                "lastRead.\(uid)": Timestamp(date: Date())
            ])
        } catch {
            print("Error marking thread read: \(error.localizedDescription)")
        }
    }

    private var lastSyncedBadge: Int?

    /// Mirrors the unread-conversation count onto the app icon and the
    /// server-side counter that push notifications use for their badge number.
    /// Every message listener calls this, so skip when nothing changed —
    /// otherwise app launch fires a burst of identical Firestore writes.
    private func syncBadge() {
        guard !uid.isEmpty else { return }
        let total = unreadThreadCount
        guard total != lastSyncedBadge else { return }
        lastSyncedBadge = total
        UNUserNotificationCenter.current().setBadgeCount(total, withCompletionHandler: nil)
        db.collection("users").document(uid).setData(["unreadTotal": total], merge: true)
    }

    // MARK: - Tags

    struct TagCount: Identifiable {
        var id: String { tag }
        let tag: String
        let count: Int
    }

    func topTags() -> [TagCount] {
        var freq: [String: Int] = [:]
        // Skip other users' private posts so their tags don't leak into the tag bar
        for post in posts where !post.isPrivate || post.authorUID == uid {
            for tag in post.tags {
                freq[tag, default: 0] += 1
            }
        }
        return freq
            .map { TagCount(tag: $0.key, count: $0.value) }
            .sorted { $0.count > $1.count }
    }

    // MARK: - Posts

    /// Uploads photos and saves the post. Returns false if it failed (photo
    /// upload error, or the server refused the post — e.g. a banned number),
    /// so the composer can keep the draft and say so. If the post is merely
    /// still queued because the phone went offline, that counts as success:
    /// Firestore sends it on reconnect, and reporting failure would invite a
    /// duplicate post.
    @discardableResult
    func addPost(title: String, bodyText: String, images: [UIImage], tags: [String] = [], isPrivate: Bool = false) async -> Bool {
        guard !uid.isEmpty else { return false }
        do {
            // Upload images first
            var imageURLs: [String] = []
            if !images.isEmpty {
                print("Uploading \(images.count) images...")
                imageURLs = try await StorageService.uploadImages(
                    images,
                    path: "posts/\(uid)/\(UUID().uuidString)"
                )
                print("Upload done, URLs: \(imageURLs)")
            }

            let post = Post(
                title: title,
                bodyText: bodyText,
                imageURLs: imageURLs,
                authorUID: uid,
                tags: tags.map { $0.lowercased() },
                isPrivate: isPrivate
            )

            // Wait (briefly) for the server to accept it; addDocument(from:)
            // would return at once and a rejection would only reach the log.
            let ref = db.collection("posts").document()
            let data = try Firestore.Encoder().encode(post)
            _ = try await waitForWrite(atMost: 15) { done in
                ref.setData(data, completion: done)
            }
            print("Post saved with \(imageURLs.count) image(s)")
            return true
        } catch {
            print("Error adding post: \(error.localizedDescription)")
            return false
        }
    }
  
    // MARK: - My posts

    /// The user's own posts, newest first. Includes private ones.
    var myPosts: [Post] {
        posts.filter { $0.authorUID == uid }.sorted { $0.createdAt > $1.createdAt }
    }

    /// The nickname this user knows a blocked person by — from a shared
    /// conversation, if there ever was one. Nicknames are per-thread, so the
    /// most recent thread wins.
    func knownNickname(for other: String) -> String? {
        threads
            .filter { $0.participants.contains(other) }
            .sorted { $0.createdAt > $1.createdAt }
            .first?.nickname
    }

    // MARK: - Account deletion

    /// Removes everything this user owns: posts (and their photos), the user
    /// document (push token, block list, badge count) and voice presence,
    /// and ends their open conversations.
    /// Messages already sent stay in the other participant's conversation —
    /// they are shared content — but nothing links them to a person once the
    /// auth user is deleted. Best effort: a failure on one item doesn't stop
    /// the rest, because the account is going away regardless.
    func deleteMyContent() async {
        guard !uid.isEmpty else { return }
        let me = uid
        isDeletingAccount = true
        voice.setAvailable(false)
        // Ask the server for every post this user wrote, so nothing is missed whatever is loaded
        var ids = Set(posts.filter { $0.authorUID == me }.compactMap(\.id))
        if let snap = try? await db.collection("posts").whereField("authorUID", isEqualTo: me).getDocuments() {
            ids.formUnion(snap.documents.map(\.documentID))
        }
        for id in ids {
            try? await db.collection("posts").document(id).delete()
        }
        await StorageService.deleteAllImages(forUser: me)
        // End every open conversation, so the other person can't keep writing
        // to an account that no longer exists.
        for thread in threads where !thread.isManuallyFrozen {
            guard let id = thread.id else { continue }
            try? await db.collection("threads").document(id).updateData(["isManuallyFrozen": true])
        }
        try? await db.collection("voicePresence").document(me).delete()
        try? await db.collection("users").document(me).delete()
        UserDefaults.standard.removeObject(forKey: Self.reportedPostIdsKey)
        reportedPostIds = []
    }

    // MARK: - Blocking

    /// People this user has blocked. Their posts and conversations are hidden
    /// on this device. Stored on the user's own document (owner-only rules).
    @Published private(set) var blockedUIDs: Set<String> = []

    /// Terms version this account last accepted (users/{uid}.termsVersion),
    /// and whether the user doc has been read at least once — so ContentView
    /// can ask accounts that accepted an older version (or none, e.g. before
    /// the woman / 18+ confirmation existed) to confirm again.
    @Published private(set) var acceptedTermsVersion: String?
    @Published private(set) var userDocLoaded = false
    /// True while the account is being deleted (its user doc disappears
    /// first), so nothing asks it to accept the terms on the way out.
    @Published private(set) var isDeletingAccount = false

    /// Conversations minus those with someone I've blocked.
    var visibleThreads: [ChatThread] {
        threads.filter { thread in
            !thread.participants.contains { $0 != uid && blockedUIDs.contains($0) }
        }
    }

    private func listenToUser() {
        guard !uid.isEmpty else { return }
        userListener = db.collection("users").document(uid)
            .addSnapshotListener { [weak self] snapshot, _ in
                guard let self else { return }
                let blocked = snapshot?.data()?["blocked"] as? [String] ?? []
                self.blockedUIDs = Set(blocked)
                // An empty answer from the local cache (fresh install, offline)
                // says nothing about the server; wait for the real document.
                if let snapshot, snapshot.exists || !snapshot.metadata.isFromCache {
                    self.acceptedTermsVersion = snapshot.data()?["termsVersion"] as? String
                    self.userDocLoaded = true
                }
                self.syncBadge()
            }
    }

    func blockUser(_ other: String) async {
        guard !uid.isEmpty, !other.isEmpty, other != uid else { return }
        blockedUIDs.insert(other)   // hide immediately; the listener confirms
        do {
            try await db.collection("users").document(uid).setData(
                ["blocked": FieldValue.arrayUnion([other])], merge: true)
        } catch {
            print("Error blocking user: \(error.localizedDescription)")
        }
    }

    func unblockUser(_ other: String) async {
        guard !uid.isEmpty else { return }
        blockedUIDs.remove(other)
        do {
            try await db.collection("users").document(uid).setData(
                ["blocked": FieldValue.arrayRemove([other])], merge: true)
        } catch {
            print("Error unblocking user: \(error.localizedDescription)")
        }
    }

    /// Blocks the other participant and ends the conversation.
    func blockUser(in thread: ChatThread) async {
        guard let other = thread.participants.first(where: { $0 != uid }) else { return }
        if let threadId = thread.id { await manualFreezeThread(threadId: threadId) }
        await blockUser(other)
    }

    // MARK: - Reports

    private static let reportedPostIdsKey = "reportedPostIds"

    /// Posts this device has reported. They're hidden from the reporter's feed
    /// right away — moderation happens later, from the Firebase console.
    @Published private(set) var reportedPostIds: Set<String> = Set(
        UserDefaults.standard.stringArray(forKey: AppState.reportedPostIdsKey) ?? []
    )

    /// Hides the post locally, then files a report for moderators. Clients can
    /// create reports but never read them (see firestore.rules).
    /// `reasons`:她勾的那几条(至少一条)。两种写法都存:`reasons` 是一条一条的列表,
    /// `reason` 是连起来的一句(给通知和后台看的人读)。
    func reportPost(_ post: Post, reasons: [String], details: String) async {
        guard let postId = post.id, !uid.isEmpty else { return }
        // Posts expire after 48h — drop ids of posts that no longer exist so the list stays tiny
        let liveIds = Set(posts.compactMap(\.id))
        reportedPostIds = reportedPostIds.intersection(liveIds).union([postId])
        UserDefaults.standard.set(Array(reportedPostIds), forKey: Self.reportedPostIdsKey)
        do {
            try await db.collection("reports").addDocument(data: [
                "type": "post",
                "postId": postId,
                "reportedUID": post.authorUID,
                "reporterUID": uid,
                "reason": reasons.joined(separator: ", "),
                "reasons": reasons,
                "details": details,
                // Snapshot the content: the post itself expires and disappears
                "title": post.title,
                "bodyText": post.bodyText,
                "imageURLs": post.imageURLs,
                "createdAt": FieldValue.serverTimestamp()
            ])
        } catch {
            print("Error reporting post: \(error.localizedDescription)")
        }
    }

    /// Ends the conversation and files a report with a transcript of the other
    /// person's recent messages, so moderators can act after the thread expires.
    func reportChat(thread: ChatThread, reasons: [String], details: String) async {
        guard let threadId = thread.id, !uid.isEmpty else { return }
        await manualFreezeThread(threadId: threadId)
        let other = thread.participants.first { $0 != uid } ?? ""
        // Read the history from the server so the transcript is complete even if only part of it is
        // loaded on this phone; fall back to what is loaded if that read fails.
        var history = messages[threadId] ?? []
        if let snap = try? await db.collection("threads").document(threadId).collection("messages")
            .order(by: "createdAt", descending: true).limit(to: 300).getDocuments() {
            history = Array(snap.documents.compactMap { try? $0.data(as: ChatMessage.self) }.reversed())
        }
        let transcript = history
            .filter { $0.senderUID == other }
            .suffix(30)
            .map { message -> [String: Any] in
                // 她发的照片也记进举报里:服务器会把这些文件留给管理员(functions: onReportCreated)
                var entry: [String: Any] = ["text": message.text, "at": Timestamp(date: message.createdAt)]
                if let path = message.imagePath { entry["imagePath"] = path }
                return entry
            }
        do {
            try await db.collection("reports").addDocument(data: [
                "type": "chat",
                "threadId": threadId,
                "postId": thread.postId ?? "",
                "postTitle": thread.postTitle,
                "reportedUID": other,
                "reporterUID": uid,
                "reason": reasons.joined(separator: ", "),
                "reasons": reasons,
                "details": details,
                "messages": transcript,
                "createdAt": FieldValue.serverTimestamp()
            ])
        } catch {
            print("Error reporting chat: \(error.localizedDescription)")
        }
    }

    func toggleLike(post: Post, alreadyLiked: Bool) async {
        guard let postId = post.id, !uid.isEmpty else { return }
        let countDelta = alreadyLiked ? (post.likeCount > 0 ? Int64(-1) : Int64(0)) : Int64(1)
        do {
            try await db.collection("posts").document(postId).updateData([
                "likeCount": FieldValue.increment(countDelta),
                "likedBy": alreadyLiked ? FieldValue.arrayRemove([uid]) : FieldValue.arrayUnion([uid])
            ])
        } catch {
            print("Error toggling like: \(error.localizedDescription)")
        }
    }

    // MARK: - Threads

    /// Opens a chat for a post WITHOUT creating anything in Firestore.
    /// Returns the thread id to navigate to: an existing conversation, the
    /// current draft, or a brand-new draft with its document id reserved
    /// up front so navigation stays stable when it's materialized later.
    func startChat(from post: Post) -> String? {
        guard !uid.isEmpty, post.id != nil else { return nil }

        // Don't chat with yourself
        guard post.authorUID != uid else { return nil }

        // Return existing active thread for this specific post if one exists
        if let existing = threads.first(where: {
            !$0.isFrozen() &&
            $0.postId == post.id &&
            $0.participants.contains(uid) &&
            $0.participants.contains(post.authorUID)
        }) {
            return existing.id
        }

        // Re-enter the unsent draft for this post instead of making another
        if let draft = draftThread, draft.postId == post.id {
            return draft.id
        }

        let ref = db.collection("threads").document()
        draftThread = ChatThread(
            id: ref.documentID,
            postId: post.id,
            postTitle: post.title,
            participants: [uid, post.authorUID]
        )
        return ref.documentID
    }

    /// Throws away the unsent draft (called when the sender leaves the chat
    /// without writing anything).
    func discardDraft(threadId: String) {
        guard draftThread?.id == threadId else { return }
        draftThread = nil
    }

    func sendMessage(threadId: String, text: String) async {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        let isDraft = draftThread?.id == threadId

        // Check if frozen (drafts are never frozen — they were just created)
        guard let thread = threads.first(where: { $0.id == threadId })
                ?? (isDraft ? draftThread : nil),
              !thread.isFrozen() else { return }

        do {
            // First message in a draft: create the real thread now. This is the
            // moment the conversation appears on the other person's device.
            if isDraft {
                try db.collection("threads").document(threadId).setData(from: thread)
                // 和 founder 的对话不是从帖子开始的,没有 "Started from" 这一句
                if !thread.isFounder {
                    let sys = ChatMessage(
                        text: "Started from: \"\(thread.postTitle)\"",
                        senderUID: "system"
                    )
                    try db.collection("threads").document(threadId)
                        .collection("messages")
                        .addDocument(from: sys)
                }
                draftThread = nil
            }

            let msg = ChatMessage(text: trimmed, senderUID: uid)
            try db.collection("threads").document(threadId)
                .collection("messages")
                .addDocument(from: msg)
        } catch {
            print("Error sending message: \(error.localizedDescription)")
        }
    }

    // MARK: 和 founder 的对话
    //
    // 每人一段,id 是固定的;只能由她自己用第一条回复创建,founder 不能主动找人。
    // 它不是从帖子开始的,也没有 48 小时(firestore.rules: startsWithFounder)。

    var founderThreadId: String { "founder_\(uid)" }

    /// 打开和 founder 的对话。已经有了就回它;没有就先在这台手机上放一个草稿,
    /// 发出第一条回复时才真的创建(和从帖子开始的对话同一个做法)。
    /// 后台没有配 founder,或者自己就是 founder,就没有这段对话。
    func startFounderChat() -> String? {
        guard !uid.isEmpty,
              let founder = appConfig?.founderUID, !founder.isEmpty, founder != uid else { return nil }
        let id = founderThreadId
        if threads.contains(where: { $0.id == id }) { return id }
        if draftThread?.id == id { return id }
        let hours = appConfig?.founderThreadHours ?? 0
        let now = Date()
        draftThread = ChatThread(
            id: id,
            postId: nil,
            postTitle: "",
            participants: [uid, founder],
            createdAt: now,
            kind: ChatThread.founderKind,
            expiresAt: hours > 0 ? now.addingTimeInterval(TimeInterval(hours) * 3600) : ChatThread.never
        )
        return id
    }

    // MARK: 聊天里的照片

    /// 后台的总开关(config/app.chatPhotos)。没读到配置时当作开着。
    var chatPhotosEnabled: Bool { appConfig?.chatPhotos != false }

    /// 发一张照片(可以带一句话)。顺序:先有对话,再上传,最后写消息;
    /// 消息没写成,就把传上去的那张拿回来。成功返回 true。
    /// 对方要等服务器检查过(消息上出现 imageOK)才看得到这张图。
    func sendPhoto(threadId: String, image: UIImage, text: String = "") async -> Bool {
        guard !uid.isEmpty, chatPhotosEnabled else { return false }
        let isDraft = draftThread?.id == threadId
        guard let thread = threads.first(where: { $0.id == threadId })
                ?? (isDraft ? draftThread : nil),
              !thread.isFrozen() else { return false }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)

        var uploaded: String?
        do {
            if isDraft {
                // 上传时 storage.rules 会去服务器上找这段对话是谁的,
                // 所以这里要等对话真的写到了服务器,再传图。
                let ref = db.collection("threads").document(threadId)
                try await ref.setData(try Firestore.Encoder().encode(thread))
                if !thread.isFounder {
                    let sys = ChatMessage(
                        text: "Started from: \"\(thread.postTitle)\"",
                        senderUID: "system"
                    )
                    try ref.collection("messages").addDocument(from: sys)
                }
                draftThread = nil
            }

            let path = try await StorageService.uploadChatPhoto(image, threadId: threadId, uid: uid)
            uploaded = path
            StorageService.rememberChatPhoto(image, path: path)

            let msg = ChatMessage(text: trimmed, senderUID: uid, imagePath: path)
            try db.collection("threads").document(threadId)
                .collection("messages")
                .addDocument(from: msg)
            return true
        } catch {
            print("Error sending photo: \(error.localizedDescription)")
            if let uploaded { await StorageService.deleteChatPhoto(path: uploaded) }
            return false
        }
    }

    func manualFreezeThread(threadId: String) async {
        do {
            try await db.collection("threads").document(threadId).updateData([
                "isManuallyFrozen": true
            ])
        } catch {
            print("Error freezing thread: \(error.localizedDescription)")
        }
    }

    func setContinueChoice(threadId: String, choice: ContinueChoice) async {
        // 到时间以后只有 24 小时可以回答(ChatThread.decisionWindow)。
        // 页面过了点就不再给按钮;这里再拦一道,免得一直开着的页面晚了还能点。
        if let thread = threads.first(where: { $0.id == threadId }), !thread.isAwaitingDecision() { return }
        do {
            try await db.collection("threads").document(threadId).updateData([
                "continueChoices.\(uid)": choice.rawValue
            ])

            // Check if both said yes → extend
            if choice == .yes {
                await checkAndExtendThread(threadId: threadId)
            }
        } catch {
            print("Error setting continue choice: \(error.localizedDescription)")
        }
    }

    private func checkAndExtendThread(threadId: String) async {
        do {
            // Read fresh from Firestore to avoid stale local state race condition
            let snap = try await db.collection("threads").document(threadId).getDocument()
            let thread = try snap.data(as: ChatThread.self)
            guard thread.bothSaidYes,
                  !thread.hasExtendedOnce,
                  !thread.isManuallyFrozen,
                  thread.isAwaitingDecision() else { return }

            let newExpiry = Date().addingTimeInterval(Self.chatTTL)

            // Reset choices and extend
            var resetChoices: [String: String] = [:]
            for uid in thread.participants {
                resetChoices[uid] = ContinueChoice.undecided.rawValue
            }

            try await db.collection("threads").document(threadId).updateData([
                "expiresAt": Timestamp(date: newExpiry),
                "hasExtendedOnce": true,
                "continueChoices": resetChoices
            ])

            // Add system message
            let msg = ChatMessage(
                text: "Conversation continued for 48 hours.",
                senderUID: "system"
            )
            try db.collection("threads").document(threadId)
                .collection("messages")
                .addDocument(from: msg)
        } catch {
            print("Error extending thread: \(error.localizedDescription)")
        }
    }
}
