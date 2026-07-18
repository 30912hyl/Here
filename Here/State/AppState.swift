import SwiftUI
import FirebaseFirestore
import UserNotifications

@MainActor
final class AppState: ObservableObject {
    static let chatTTL: TimeInterval = 48 * 60 * 60

    private let db = Firestore.firestore()
    private var postsListener: ListenerRegistration?
    private var threadsListener: ListenerRegistration?
    private var messageListeners: [String: ListenerRegistration] = [:]

    var authService: AuthService

    @Published var posts: [Post] = []
    @Published var threads: [ChatThread] = []
    @Published var messages: [String: [ChatMessage]] = [:]  // threadId -> messages

    var uid: String { authService.uid ?? "" }

    init(authService: AuthService) {
        self.authService = authService
    }

    // MARK: - Listeners

    func startListening() {
        listenToPosts()
        listenToThreads()
    }

    func stopListening() {
        postsListener?.remove()
        threadsListener?.remove()
        messageListeners.values.forEach { $0.remove() }
        messageListeners.removeAll()
        messages.removeAll()
    }

    private func listenToPosts() {
        postsListener = db.collection("posts")
            .order(by: "createdAt", descending: true)
            .addSnapshotListener { [weak self] snapshot, error in
                if let error {
                    print("Posts listener error: \(error.localizedDescription)")
                    return
                }
                guard let docs = snapshot?.documents else { return }
                print("Fetched \(docs.count) posts")
                self?.posts = docs.compactMap { try? $0.data(as: Post.self) }
                print("Decoded \(self?.posts.count ?? 0) posts")
            }
    }

    private func listenToThreads() {
        guard !uid.isEmpty else { return }

        threadsListener = db.collection("threads")
            .whereField("participants", arrayContains: uid)
            .order(by: "createdAt", descending: true)
            .addSnapshotListener { [weak self] snapshot, error in
                guard let self, let docs = snapshot?.documents else { return }
                self.threads = docs.compactMap { try? $0.data(as: ChatThread.self) }

                // Start listening to messages for each thread
                for thread in self.threads {
                    guard let threadId = thread.id else { continue }
                    if self.messageListeners[threadId] == nil {
                        self.listenToMessages(threadId: threadId)
                    }
                }
                self.syncBadge()
            }
    }

    private func listenToMessages(threadId: String) {
        messageListeners[threadId] = db.collection("threads").document(threadId)
            .collection("messages")
            .order(by: "createdAt", descending: false)
            .addSnapshotListener { [weak self] snapshot, error in
                guard let docs = snapshot?.documents else { return }
                let msgs = docs.compactMap { try? $0.data(as: ChatMessage.self) }
                self?.messages[threadId] = msgs
                self?.syncBadge()
            }
    }

    // MARK: - Unread

    func unreadCount(in thread: ChatThread) -> Int {
        guard let threadId = thread.id, !uid.isEmpty else { return 0 }
        let lastRead = thread.lastRead[uid] ?? .distantPast
        return (messages[threadId] ?? [])
            .filter { $0.senderUID != uid && $0.senderUID != "system" && $0.createdAt > lastRead }
            .count
    }

    /// iMessage-style: number of conversations with unread messages,
    /// not the total message count.
    var unreadThreadCount: Int {
        threads.filter { unreadCount(in: $0) > 0 }.count
    }

    /// Stamps "read up to now" for the current user on a thread.
    func markThreadRead(threadId: String) async {
        guard !uid.isEmpty else { return }
        do {
            try await db.collection("threads").document(threadId).updateData([
                "lastRead.\(uid)": Timestamp(date: Date())
            ])
        } catch {
            print("Error marking thread read: \(error.localizedDescription)")
        }
    }

    /// Mirrors the unread-conversation count onto the app icon and the
    /// server-side counter that push notifications use for their badge number.
    private func syncBadge() {
        let total = unreadThreadCount
        UNUserNotificationCenter.current().setBadgeCount(total, withCompletionHandler: nil)
        guard !uid.isEmpty else { return }
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

    func addPost(title: String, bodyText: String, images: [UIImage], tags: [String] = [], isPrivate: Bool = false) async {
        guard !uid.isEmpty else { return }
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

            try db.collection("posts").addDocument(from: post)
            print("Post saved with \(imageURLs.count) image(s)")
        } catch {
            print("Error adding post: \(error.localizedDescription)")
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

    func createThreadFromPost(_ post: Post) async -> String? {
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

        let thread = ChatThread(
            postId: post.id,
            postTitle: post.title,
            participants: [uid, post.authorUID]
        )

        do {
            let ref = try db.collection("threads").addDocument(from: thread)

            // Add an initial system message
            let msg = ChatMessage(
                text: "Started from: \"\(post.title)\"",
                senderUID: "system"
            )
            try ref.collection("messages").addDocument(from: msg)

            return ref.documentID
        } catch {
            print("Error creating thread: \(error.localizedDescription)")
            return nil
        }
    }

    func sendMessage(threadId: String, text: String) async {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        // Check if frozen
        guard let thread = threads.first(where: { $0.id == threadId }),
              !thread.isFrozen() else { return }

        let msg = ChatMessage(text: trimmed, senderUID: uid)

        do {
            try db.collection("threads").document(threadId)
                .collection("messages")
                .addDocument(from: msg)
        } catch {
            print("Error sending message: \(error.localizedDescription)")
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
                  !thread.isManuallyFrozen else { return }

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
