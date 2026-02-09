import SwiftUI
import Combine

// MARK: - Tabs

enum MainTab: Hashable {
    case voice, feed, create, inbox, profile
}

// MARK: - Models

struct Post: Identifiable {
    let id: UUID
    let text: String
    let createdAt: Date

    init(text: String, createdAt: Date = Date()) {
        self.id = UUID()
        self.text = text
        self.createdAt = createdAt
    }
}

struct ChatMessage: Identifiable {
    let id = UUID()
    let text: String
    let isMe: Bool
    let createdAt = Date()
}

enum ContinueChoice: String, Codable {
    case undecided
    case yes
    case no
}

struct ChatThread: Identifiable {
    let id: UUID
    let title: String
    var messages: [ChatMessage]

    // Manual freeze (for demo / admin)
    var isManuallyFrozen: Bool

    // Lifecycle
    let createdAt: Date
    var expiresAt: Date

    // Continue flow
    var hasExtendedOnce: Bool
    var myContinueChoice: ContinueChoice
    var otherContinueChoice: ContinueChoice

    init(
        title: String,
        messages: [ChatMessage] = [],
        createdAt: Date = Date(),
        ttlSeconds: TimeInterval,
        isManuallyFrozen: Bool = false
    ) {
        self.id = UUID()
        self.title = title
        self.messages = messages
        self.isManuallyFrozen = isManuallyFrozen
        self.createdAt = createdAt
        self.expiresAt = createdAt.addingTimeInterval(ttlSeconds)

        self.hasExtendedOnce = false
        self.myContinueChoice = .undecided
        self.otherContinueChoice = .undecided
    }
}

// MARK: - App State (local)

@MainActor
final class AppState: ObservableObject {
    static let postTTL: TimeInterval = 24 * 60 * 60
    static let chatTTL: TimeInterval = 24 * 60 * 60

    @Published var posts: [Post] = [
        Post(text: "Welcome — this is a sample post.")
    ]

    @Published var threads: [ChatThread] = []

    func activePosts(now: Date = Date()) -> [Post] {
        posts.filter { now.timeIntervalSince($0.createdAt) < Self.postTTL }
    }

    func isThreadExpired(_ thread: ChatThread, now: Date = Date()) -> Bool {
        now >= thread.expiresAt
    }

    func isThreadFrozenNow(_ thread: ChatThread, now: Date = Date()) -> Bool {
        thread.isManuallyFrozen || isThreadExpired(thread, now: now)
    }

    func createThreadFromPost(_ post: Post) -> UUID {
        let new = ChatThread(
            title: "From a post",
            messages: [
                ChatMessage(text: "Started from: “\(post.text.prefix(60))”", isMe: false)
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

// MARK: - Root

struct ContentView: View {
    @State private var selectedTab: MainTab = .feed
    @State private var lastNonCreateTab: MainTab = .feed
    @State private var showCreateSheet = false

    @StateObject private var app = AppState()

    var body: some View {
        let activePosts = app.activePosts()

        TabView(selection: $selectedTab) {

            VoiceViewLocal()
                .tabItem { Label("Voice", systemImage: "waveform") }
                .tag(MainTab.voice)

            FeedViewLocal(
                posts: activePosts,
                onStartChat: { post in
                    _ = app.createThreadFromPost(post)
                    selectedTab = .inbox
                }
            )
            .tabItem { Label("Posts", systemImage: "rectangle.portrait.on.rectangle.portrait") }
            .tag(MainTab.feed)

            Color.clear
                .tabItem { Label(" ", systemImage: "heart.fill") }
                .tag(MainTab.create)

            InboxViewLocal(
                threads: $app.threads,
                isFrozenNow: { thread in app.isThreadFrozenNow(thread) },
                onSend: { id, text in app.sendMessage(threadId: id, text: text) },
                onManualFreeze: { id in app.manualFreezeThread(threadId: id) }
            )
            .tabItem { Label("Chats", systemImage: "bubble.left.and.bubble.right") }
            .tag(MainTab.inbox)

            ProfileViewLocal()
                .tabItem { Label("Profile", systemImage: "person.crop.circle") }
                .tag(MainTab.profile)
        }
        .onChange(of: selectedTab) {
            let newValue = selectedTab
            if newValue != .create {
                lastNonCreateTab = newValue
                return
            }
            showCreateSheet = true
            selectedTab = lastNonCreateTab
        }
        .sheet(isPresented: $showCreateSheet) {
            CreatePostViewLocal { text in
                app.posts.insert(Post(text: text), at: 0)
            }
        }
    }
}

// MARK: - Posts Feed

struct FeedViewLocal: View {
    let posts: [Post]
    let onStartChat: (Post) -> Void

    var body: some View {
        NavigationStack {
            if posts.isEmpty {
                VStack(spacing: 12) {
                    Text("No posts in the last 24 hours.")
                        .font(.headline)
                    Text("Tap ❤️ to share how you feel.")
                        .foregroundStyle(.secondary)
                }
                .padding()
                .navigationTitle("Posts")
            } else {
                List(posts) { post in
                    VStack(alignment: .leading, spacing: 10) {
                        Text(post.text)
                            .padding(.top, 6)

                        Button("Private chat") {
                            onStartChat(post)
                        }
                        .buttonStyle(.borderedProminent)
                        .padding(.bottom, 6)
                    }
                }
                .navigationTitle("Posts")
            }
        }
    }
}

// MARK: - Create Post

struct CreatePostViewLocal: View {
    @Environment(\.dismiss) private var dismiss
    @State private var text = ""
    let onPost: (String) -> Void

    var body: some View {
        NavigationStack {
            Form {
                Section("Say what you feel") {
                    TextEditor(text: $text)
                        .frame(minHeight: 160)
                }
                Section {
                    Text("This post will disappear from the feed after 24 hours.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("New Post")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Post") {
                        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !trimmed.isEmpty else { return }
                        onPost(trimmed)
                        dismiss()
                    }
                    .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }
}

// MARK: - Chats

struct InboxViewLocal: View {
    @Binding var threads: [ChatThread]
    let isFrozenNow: (ChatThread) -> Bool
    let onSend: (UUID, String) -> Void
    let onManualFreeze: (UUID) -> Void

    var body: some View {
        NavigationStack {
            List {
                if threads.isEmpty {
                    Text("No chats yet. Start one from a post.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(threads) { t in
                        NavigationLink {
                            ChatDetailView(
                                thread: binding(for: t.id),
                                isFrozenNow: isFrozenNow,
                                onSend: onSend,
                                onManualFreeze: onManualFreeze
                            )
                        } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(t.title).font(.headline)
                                Text(isFrozenNow(t) ? "Frozen" : "Active")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Chats")
        }
    }

    private func binding(for id: UUID) -> Binding<ChatThread> {
        guard let idx = threads.firstIndex(where: { $0.id == id }) else {
            return .constant(ChatThread(title: "Missing", ttlSeconds: AppState.chatTTL))
        }
        return $threads[idx]
    }
}

// MARK: - Chat Detail (with 24h freeze + one-time continue)

struct ChatDetailView: View {
    @Binding var thread: ChatThread
    @State private var input: String = ""
    @State private var showEndedActions = false

    let isFrozenNow: (ChatThread) -> Bool
    let onSend: (UUID, String) -> Void
    let onManualFreeze: (UUID) -> Void

    private var now: Date { Date() }
    private var expired: Bool { now >= thread.expiresAt }
    private var frozen: Bool { isFrozenNow(thread) }

    var body: some View {
        // If both said YES and extension not used, auto-extend once.
        // (We only reveal "continued" by the fact that input comes back.)


        VStack(spacing: 0) {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 10) {
                    ForEach(thread.messages) { m in
                        HStack {
                            if m.isMe { Spacer() }
                            Text(m.text)
                                .padding(10)
                                .background(Color(.secondarySystemBackground))
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                            if !m.isMe { Spacer() }
                        }
                    }
                }
                .padding()
            }

            Divider()

            // Bottom area logic:
            // 1) Not frozen -> normal input
            // 2) Frozen because expired AND extension not used -> ask Yes/No / waiting
            // 3) Frozen and already extended once (or manual freeze) -> ended
            if !frozen {
                chatInputBar
            } else {
                frozenBottomArea
            }
        }
        .navigationTitle(thread.title)
        .onAppear {
            maybeApplyExtensionIfReady()
        }
        .onChange(of: thread.myContinueChoice) {
            maybeApplyExtensionIfReady()
        }
        .onChange(of: thread.otherContinueChoice) {
            maybeApplyExtensionIfReady()
        }

        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Freeze") { onManualFreeze(thread.id) }
            }

            #if DEBUG
            ToolbarItem(placement: .topBarLeading) {
                Menu("Debug") {
                    Button("Expire Now") {
                        thread.expiresAt = Date().addingTimeInterval(-1)
                    }
                    Button("Other YES") {
                        thread.otherContinueChoice = .yes
                    }
                    Button("Other NO") {
                        thread.otherContinueChoice = .no
                    }
                    Button("Reset Continue Choices") {
                        thread.myContinueChoice = .undecided
                        thread.otherContinueChoice = .undecided
                    }
                }
            }
            #endif
        }
        .alert("Conversation ended", isPresented: $showEndedActions) {
            Button("Report (placeholder)") { }
            Button("Block (placeholder)") { }
            Button("OK", role: .cancel) { }
        } message: {
            Text("You can report or block here later. For now this is a placeholder.")
        }
    }

    // MARK: - Subviews

    private var chatInputBar: some View {
        HStack(spacing: 10) {
            TextField("Message…", text: $input)
                .textFieldStyle(.roundedBorder)

            Button("Send") {
                let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty else { return }
                onSend(thread.id, trimmed)
                input = ""
            }
            .buttonStyle(.borderedProminent)
        }
        .padding()
    }

    private var frozenBottomArea: some View {
        VStack(spacing: 10) {
            // If manually frozen, just show frozen message.
            if thread.isManuallyFrozen {
                Text("This chat is frozen. You can’t send messages.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .padding(.top, 6)
                SpacerMin()
                returnAny()
            }

            // Expired due to time.
            if expired {
                if thread.hasExtendedOnce {
                    // Already extended once -> permanently end after second day.
                    Text("This conversation has ended.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)

                    Button("Options") {
                        showEndedActions = true
                    }
                    .buttonStyle(.bordered)
                } else {
                    // Extension still possible (one time).
                    switch thread.myContinueChoice {
                    case .undecided:
                        Text("This chat is archived. Continue this conversation for one more day?")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)

                        HStack(spacing: 12) {
                            Button("No") {
                                thread.myContinueChoice = .no
                                // Do NOT reveal other side choice.
                                showEndedActions = true
                            }
                            .buttonStyle(.bordered)

                            Button("Yes") {
                                thread.myContinueChoice = .yes
                                // Do NOT reveal other side choice unless both yes.
                            }
                            .buttonStyle(.borderedProminent)
                        }

                        Text("You won’t be told what the other person chose unless both of you say Yes.")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)

                    case .yes:
                        // Waiting state — do not tell whether other clicked.
                        Text("Request sent. Waiting for the other person to decide.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)

                        Text("If both of you say Yes, the chat will reopen for 24 hours.")
                            .font(.caption2)
                            .foregroundStyle(.secondary)

                    case .no:
                        Text("This conversation has ended.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)

                        Button("Options") {
                            showEndedActions = true
                        }
                        .buttonStyle(.bordered)
                    }
                }
            } else {
                // Not expired but frozen for some reason (shouldn't happen here)
                Text("This chat is frozen. You can’t send messages.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
    }

    // MARK: - Logic helpers

    private func maybeApplyExtensionIfReady() {
        // Only auto-extend when:
        // - expired
        // - not extended before
        // - not manually frozen
        // - both said YES
        guard !thread.isManuallyFrozen else { return }
        guard Date() >= thread.expiresAt else { return }
        guard thread.hasExtendedOnce == false else { return }
        guard thread.myContinueChoice == .yes && thread.otherContinueChoice == .yes else { return }

        // Extend for one more day
        thread.expiresAt = Date().addingTimeInterval(AppState.chatTTL)
        thread.hasExtendedOnce = true

        // Reset choices so we don’t keep showing states
        thread.myContinueChoice = .undecided
        thread.otherContinueChoice = .undecided

        // Optional: add a system message (local demo)
        thread.messages.append(ChatMessage(text: "Conversation continued for 24 hours.", isMe: false))
    }

    // MARK: - Tiny helpers to keep layout stable
    private func SpacerMin() -> some View { Spacer().frame(height: 0) }
    private func returnAny() -> some View { EmptyView() }
}

// MARK: - Simple placeholders

struct VoiceViewLocal: View {
    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 12) {
                Text("Voice (later)")
                    .font(.title2).bold()
                Text("We’ll open voice during scheduled hours once you have enough users.")
                    .foregroundStyle(.secondary)
                Spacer()
            }
            .padding()
            .navigationTitle("Voice")
        }
    }
}

struct ProfileViewLocal: View {
    var body: some View {
        NavigationStack {
            List {
                Text("Profile (anonymous)")
                Text("Archive (later)")
                Text("Safety / report (later)")
            }
            .navigationTitle("Profile")
        }
    }
}

#Preview {
    ContentView()
}
