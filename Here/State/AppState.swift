import SwiftUI
import Combine

@MainActor
final class AppState: ObservableObject {
    static let postTTL: TimeInterval = 48 * 60 * 60
    static let chatTTL: TimeInterval = 48 * 60 * 60

    @Published var posts: [Post] = [
        Post(title: "Welcome", bodyText: "This is a sample post. Tap the ❤️ tab to share how you feel.")
    ]

    @Published var threads: [ChatThread] = []

    func addPost(_ post: Post) {
        posts.insert(post, at: 0)
    }

    func activePosts(now: Date = Date()) -> [Post] {
        posts.filter { now.timeIntervalSince($0.createdAt) < Self.postTTL }
    }

    func likePost(id: UUID) {
        guard let idx = posts.firstIndex(where: { $0.id == id }) else { return }
        posts[idx].likeCount += 1
    }

    func isThreadExpired(_ thread: ChatThread, now: Date = Date()) -> Bool {
        now >= thread.expiresAt
    }

    func isThreadFrozenNow(_ thread: ChatThread, now: Date = Date()) -> Bool {
        thread.isManuallyFrozen || isThreadExpired(thread, now: now)
    }

    func createThreadFromPost(_ post: Post) -> UUID {
        let new = ChatThread(
            title: "From: \(post.title)",
            messages: [
                ChatMessage(text: "Started from: \"\(post.title)\"", isMe: false)
            ],
            createdAt: Date(),
            ttlSeconds: Self.chatTTL
        )
        threads.insert(new, at: 0)
        return new.id
    }

    func manualFreezeThread(threadId: UUID) {
        guard let idx = threads.firstIndex(where: { $0.id == threadId }) else { return }
        threads[idx].isManuallyFrozen = true
    }

    func sendMessage(threadId: UUID, text: String) {
        guard let idx = threads.firstIndex(where: { $0.id == threadId }) else { return }
        if isThreadFrozenNow(threads[idx]) { return }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        threads[idx].messages.append(ChatMessage(text: trimmed, isMe: true))
        threads[idx].messages.append(ChatMessage(text: "I hear you 💛", isMe: false))
    }
}
