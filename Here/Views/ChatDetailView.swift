//
//  ChatDetailView.swift
//  Here
//
//  Created by Aaron Lee on 2/10/26.
//
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

    var body: some View {
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 10) {
                        ForEach(messages) { m in
                            HStack {
                                if m.isMe(uid: uid) { Spacer() }
                                Text(m.text)
                                    .padding(10)
                                    .background(
                                        m.senderUID == "system"
                                            ? Color.yellow.opacity(0.15)
                                            : Color(.secondarySystemBackground)
                                    )
                                    .clipShape(RoundedRectangle(cornerRadius: 12))
                                    .foregroundStyle(
                                        m.senderUID == "system" ? .secondary : .primary
                                    )
                                if !m.isMe(uid: uid) { Spacer() }
                            }
                            .id(m.id)
                        }
                    }
                    .padding()
                }
                .defaultScrollAnchor(.bottom)
                .onChange(of: messages.count) {
                    if let lastId = messages.last?.id {
                        withAnimation {
                            proxy.scrollTo(lastId, anchor: .bottom)
                        }
                    }
                }
            }

            Divider()

            if !frozen {
                chatInputBar
            } else {
                frozenBottomArea
            }
        }
        .navigationTitle(thread.postTitle)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Freeze") {
                    Task { await app.manualFreezeThread(threadId: threadId) }
                }
            }
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
                let text = input
                input = ""
                Task { await app.sendMessage(threadId: threadId, text: text) }
            }
            .buttonStyle(.borderedProminent)
            .disabled(input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
        .padding()
    }

    private var frozenBottomArea: some View {
        VStack(spacing: 10) {
            if thread.isManuallyFrozen {
                Text("This chat is frozen. You can't send messages.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .padding(.top, 6)
            } else if expired {
                if thread.hasExtendedOnce {
                    Text("This conversation has ended.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)

                    Button("Options") { showEndedActions = true }
                        .buttonStyle(.bordered)
                } else {
                    switch myChoice {
                    case .undecided:
                        Text("This chat is archived. Continue this conversation for one more day?")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)

                        HStack(spacing: 12) {
                            Button("No") {
                                Task {
                                    await app.setContinueChoice(threadId: threadId, choice: .no)
                                }
                                showEndedActions = true
                            }
                            .buttonStyle(.bordered)

                            Button("Yes") {
                                Task {
                                    await app.setContinueChoice(threadId: threadId, choice: .yes)
                                }
                            }
                            .buttonStyle(.borderedProminent)
                        }

                        Text("You won't be told what the other person chose unless both of you say Yes.")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)

                    case .yes:
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

                        Button("Options") { showEndedActions = true }
                            .buttonStyle(.bordered)
                    }
                }
            } else {
                Text("This chat is frozen. You can't send messages.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
    }
}
