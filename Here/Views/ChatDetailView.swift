//
//  ChatDetailView.swift
//  Here
//
//  Created by Aaron Lee on 2/10/26.
//
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

    var body: some View {
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
            if thread.isManuallyFrozen {
                Text("This chat is frozen. You can't send messages.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .padding(.top, 6)
            }

            if expired {
                if thread.hasExtendedOnce {
                    Text("This conversation has ended.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)

                    Button("Options") {
                        showEndedActions = true
                    }
                    .buttonStyle(.bordered)
                } else {
                    switch thread.myContinueChoice {
                    case .undecided:
                        Text("This chat is archived. Continue this conversation for one more day?")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)

                        HStack(spacing: 12) {
                            Button("No") {
                                thread.myContinueChoice = .no
                                showEndedActions = true
                            }
                            .buttonStyle(.bordered)

                            Button("Yes") {
                                thread.myContinueChoice = .yes
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

                        Button("Options") {
                            showEndedActions = true
                        }
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

    // MARK: - Logic

    private func maybeApplyExtensionIfReady() {
        guard !thread.isManuallyFrozen else { return }
        guard Date() >= thread.expiresAt else { return }
        guard thread.hasExtendedOnce == false else { return }
        guard thread.myContinueChoice == .yes && thread.otherContinueChoice == .yes else { return }

        thread.expiresAt = Date().addingTimeInterval(AppState.chatTTL)
        thread.hasExtendedOnce = true

        thread.myContinueChoice = .undecided
        thread.otherContinueChoice = .undecided

        thread.messages.append(ChatMessage(text: "Conversation continued for 24 hours.", isMe: false))
    }
}
