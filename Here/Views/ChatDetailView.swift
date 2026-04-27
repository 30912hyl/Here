import SwiftUI

struct ChatDetailView: View {
    let thread: ChatThread
    @ObservedObject var app: AppState

    @State private var input = ""
    @State private var showEndedActions = false

    private var uid: String { app.uid }
    private var threadId: String { thread.id ?? "" }
    private var messages: [ChatMessage] { app.messages[threadId] ?? [] }
    private var expired: Bool { thread.isExpired() }
    private var frozen: Bool { thread.isFrozen() }
    private var myChoice: ContinueChoice { thread.myContinueChoice(uid: uid) }
    private var otherChoice: ContinueChoice { thread.otherContinueChoice(uid: uid) }

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
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 10) {
                    ForEach(messages) { m in
                        MessageBubble(message: m, uid: uid)
                            .id(m.id)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }
            .defaultScrollAnchor(.bottom)
            .scrollDismissesKeyboard(.interactively)
            .onChange(of: messages.count) {
                if let lastId = messages.last?.id {
                    withAnimation { proxy.scrollTo(lastId, anchor: .bottom) }
                }
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                if !frozen {
                    chatInputBar
                } else {
                    frozenBottomArea
                }
            }
        }
        .background(Color.white.ignoresSafeArea())
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(Color.white, for: .navigationBar)
        .toolbar {
            // Nickname in gold as title
            ToolbarItem(placement: .principal) {
                Text(thread.postTitle)
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
                        Task { await app.manualFreezeThread(threadId: threadId) }
                    } label: {
                        Label("End Conversation", systemImage: "xmark.circle")
                    }

                    // Report and end
                    Button(role: .destructive) {
                        Task { await app.manualFreezeThread(threadId: threadId) }
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
    }

    // MARK: - Input Bar
    private var chatInputBar: some View {
        HStack(alignment: .bottom, spacing: 12) {
            TextField("", text: $input, axis: .vertical)
                .font(.system(size: 15, weight: .light))
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(Color.white)
                .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .stroke(Color(hex: "#E8E0CC"), lineWidth: 1)
                )

            Button {
                let text = input
                input = ""
                Task { await app.sendMessage(threadId: threadId, text: text) }
            } label: {
                Image(systemName: "arrow.up")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundColor(.white)
                    .frame(width: 36, height: 36)
                    .background(goldGradient)
                    .clipShape(Circle())
            }
            //.buttonStyle(.borderedProminent)
            .disabled(input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
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
            } else if expired {
                if thread.hasExtendedOnce {
                    Text("This conversation has ended.")
                        .font(.system(size: 13, weight: .light))
                        .foregroundColor(Color(hex: "#C4A55A"))
                } else {
                    switch myChoice {
                    case .undecided:
                        Text("Continue this conversation for one more day?")
                            .font(.system(size: 13, weight: .light))
                            .foregroundColor(Color(hex: "#C4A55A"))
                            .multilineTextAlignment(.center)

                        HStack(spacing: 16) {
                            Button("No") {
                                Task {
                                    await app.setContinueChoice(threadId: threadId, choice: .no)
                                }
                                showEndedActions = true
                            }
                            .font(.system(size: 14, weight: .light))
                            .foregroundStyle(Color(hex: "#C4A55A"))
                            .padding(.horizontal, 24)
                            .padding(.vertical, 8)
                            .overlay(Capsule().stroke(Color(hex: "#E8E0CC"), lineWidth: 1))

                            Button("Yes") {
                                Task {
                                    await app.setContinueChoice(threadId: threadId, choice: .yes)
                                }
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
}

// MARK: - Message Bubble
struct MessageBubble: View {
    let message: ChatMessage
    let uid: String
  
    private var isMe: Bool { message.isMe(uid: uid) }
    private var isSystem: Bool { message.senderUID == "system" }

    var body: some View {
        HStack {
            if isMe || isSystem { Spacer(minLength: 60) }
            
            Text(message.text)
                .font(.system(size: 15, weight: .light))
                .foregroundColor(isSystem ? Color(hex: "#C4A55A") : .black)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(isSystem ? Color(hex: "#FBF7ED") : Color.white)
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(Color(hex: "#E8E0CC"), lineWidth: 1)
                )
            if !isMe || isSystem { Spacer(minLength: 60) }
        }
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
