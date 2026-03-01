import SwiftUI

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

    private var timeRemainingText: String {
        let remaining = thread.expiresAt.timeIntervalSince(Date())
        guard remaining > 0 else { return "Conversation ended" }
        let hours = Int(remaining / 3600)
        let minutes = Int((remaining.truncatingRemainder(dividingBy: 3600)) / 60)
        return "Ends in \(hours)h \(minutes)m"
    }

    var goldGradient: LinearGradient {
        LinearGradient(
            colors: [Color(hex: "#C9A84C"), Color(hex: "#E8CC7A"), Color(hex: "#B8922E")],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    var body: some View {
        ZStack {
            Color.white.ignoresSafeArea()

            VStack(spacing: 0) {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 10) {
                            ForEach(thread.messages) { m in
                                MessageBubble(message: m)
                                    .id(m.id)
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                    }
                    .onChange(of: thread.messages.count) {
                        if let last = thread.messages.last {
                            withAnimation { proxy.scrollTo(last.id, anchor: .bottom) }
                        }
                    }
                }

                if !frozen {
                    chatInputBar
                } else {
                    frozenBottomArea
                }
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(Color.white, for: .navigationBar)
        .toolbar {
            // Nickname in gold as title
            ToolbarItem(placement: .principal) {
                Text(thread.title)
                    .font(.system(size: 16, weight: .light))
                    .tracking(0.5)
                    .foregroundStyle(goldGradient)
            }

            // Help menu
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    // Time remaining info
                    Text(timeRemainingText)

                    Divider()

                    // End without reporting
                    Button(role: .destructive) {
                        onManualFreeze(thread.id)
                    } label: {
                        Label("End Conversation", systemImage: "xmark.circle")
                    }

                    // Report and end
                    Button(role: .destructive) {
                        onManualFreeze(thread.id)
                        showEndedActions = true
                    } label: {
                        Label("Report & End", systemImage: "flag")
                    }

                } label: {
                    Text("Help")
                        .font(.system(size: 14, weight: .light))
                        .foregroundStyle(goldGradient)
                }
            }
        }
        .alert("Report this conversation?", isPresented: $showEndedActions) {
            Button("Report", role: .destructive) { }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("Thank you for helping keep this space safe.")
        }
        .onAppear { maybeApplyExtensionIfReady() }
        .onChange(of: thread.myContinueChoice) { maybeApplyExtensionIfReady() }
        .onChange(of: thread.otherContinueChoice) { maybeApplyExtensionIfReady() }
    }

    // MARK: - Input Bar
    private var chatInputBar: some View {
        HStack(spacing: 12) {
            TextField("", text: $input)
                .font(.system(size: 15, weight: .light))
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(Color.white)
                .clipShape(Capsule())
                .overlay(
                    Capsule()
                        .stroke(Color(hex: "#E8E0CC"), lineWidth: 1)
                )

            Button {
                let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty else { return }
                onSend(thread.id, trimmed)
                input = ""
            } label: {
                Image(systemName: "arrow.up")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundColor(.white)
                    .frame(width: 36, height: 36)
                    .background(goldGradient)
                    .clipShape(Circle())
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Color.white)
        .overlay(
            Rectangle()
                .frame(height: 0.5)
                .foregroundColor(Color(hex: "#E8E0CC")),
            alignment: .top
        )
    }

    // MARK: - Frozen Bottom Area
    private var frozenBottomArea: some View {
        VStack(spacing: 12) {
            if thread.isManuallyFrozen {
                Text("This conversation has ended.")
                    .font(.system(size: 13, weight: .light))
                    .foregroundColor(Color(hex: "#C4A55A"))
            }

            if expired {
                if thread.hasExtendedOnce {
                    Text("This conversation has ended.")
                        .font(.system(size: 13, weight: .light))
                        .foregroundColor(Color(hex: "#C4A55A"))
                } else {
                    switch thread.myContinueChoice {
                    case .undecided:
                        Text("Continue this conversation for one more day?")
                            .font(.system(size: 13, weight: .light))
                            .foregroundColor(Color(hex: "#C4A55A"))
                            .multilineTextAlignment(.center)

                        HStack(spacing: 16) {
                            Button("No") {
                                thread.myContinueChoice = .no
                                showEndedActions = true
                            }
                            .font(.system(size: 14, weight: .light))
                            .foregroundStyle(Color(hex: "#C4A55A"))
                            .padding(.horizontal, 24)
                            .padding(.vertical, 8)
                            .overlay(Capsule().stroke(Color(hex: "#E8E0CC"), lineWidth: 1))

                            Button("Yes") {
                                thread.myContinueChoice = .yes
                            }
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(.white)
                            .padding(.horizontal, 24)
                            .padding(.vertical, 8)
                            .background(goldGradient)
                            .clipShape(Capsule())
                        }

                    case .yes:
                        Text("Waiting for her to decide...")
                            .font(.system(size: 13, weight: .light))
                            .foregroundColor(Color(hex: "#C4A55A"))

                    case .no:
                        Text("This conversation has ended.")
                            .font(.system(size: 13, weight: .light))
                            .foregroundColor(Color(hex: "#C4A55A"))
                    }
                }
            }
        }
        .padding()
        .background(Color.white)
        .overlay(
            Rectangle()
                .frame(height: 0.5)
                .foregroundColor(Color(hex: "#E8E0CC")),
            alignment: .top
        )
    }

    // MARK: - Extension Logic
    private func maybeApplyExtensionIfReady() {
        guard !thread.isManuallyFrozen else { return }
        guard Date() >= thread.expiresAt else { return }
        guard !thread.hasExtendedOnce else { return }
        guard thread.myContinueChoice == .yes && thread.otherContinueChoice == .yes else { return }
        thread.expiresAt = Date().addingTimeInterval(AppState.chatTTL)
        thread.hasExtendedOnce = true
        thread.myContinueChoice = .undecided
        thread.otherContinueChoice = .undecided
        thread.messages.append(ChatMessage(text: "Conversation continued for 48 hours.", isMe: false))
    }
}

// MARK: - Message Bubble
struct MessageBubble: View {
    let message: ChatMessage

    var body: some View {
        HStack {
            if message.isMe { Spacer(minLength: 60) }
            Text(message.text)
                .font(.system(size: 15, weight: .light))
                .foregroundColor(.black)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(Color.white)
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(Color(hex: "#E8E0CC"), lineWidth: 1)
                )
            if !message.isMe { Spacer(minLength: 60) }
        }
    }
}

#Preview {
    NavigationStack {
        ChatDetailView(
            thread: .constant(ChatThread(
                title: "Wandering Soul",
                messages: [
                    ChatMessage(text: "hey, your post really resonated with me", isMe: false),
                    ChatMessage(text: "thank you, I really needed to hear that", isMe: true),
                    ChatMessage(text: "how are you feeling now?", isMe: false)
                ],
                ttlSeconds: AppState.chatTTL
            )),
            isFrozenNow: { _ in false },
            onSend: { _, _ in },
            onManualFreeze: { _ in }
        )
    }
}
