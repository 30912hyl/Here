//
//  AppState.swift
//  Here
//
//  Created by Aaron Lee on 2/10/26.
//
import SwiftUI
import FirebaseFirestore
import Combine

@MainActor
final class AppState: ObservableObject {
    static let chatTTL: TimeInterval = 24 * 60 * 60

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
            }
    }

    // MARK: - Posts

    func addPost(title: String, bodyText: String, images: [UIImage]) async {
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
                authorUID: uid
            )

            try db.collection("posts").addDocument(from: post)
            print("Post saved with \(imageURLs.count) image(s)")
        } catch {
            print("Error adding post: \(error.localizedDescription)")
        }
    }

    // MARK: - Threads

    func createThreadFromPost(_ post: Post) async -> String? {
        guard !uid.isEmpty, post.id != nil else { return nil }

        // Don't chat with yourself
        guard post.authorUID != uid else { return nil }

        let thread = ChatThread(
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
        guard let thread = threads.first(where: { $0.id == threadId }),
              thread.bothSaidYes,
              !thread.hasExtendedOnce,
              !thread.isManuallyFrozen else { return }

        let newExpiry = Date().addingTimeInterval(Self.chatTTL)

        // Reset choices and extend
        var resetChoices: [String: String] = [:]
        for uid in thread.participants {
            resetChoices[uid] = ContinueChoice.undecided.rawValue
        }

        do {
            try await db.collection("threads").document(threadId).updateData([
                "expiresAt": Timestamp(date: newExpiry),
                "hasExtendedOnce": true,
                "continueChoices": resetChoices
            ])

            // Add system message
            let msg = ChatMessage(
                text: "Conversation continued for 24 hours.",
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
