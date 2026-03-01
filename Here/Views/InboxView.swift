// InboxView.swift
import SwiftUI

struct InboxView: View {
    @Binding var threads: [ChatThread]
    let isFrozenNow: (ChatThread) -> Bool
    let onSend: (UUID, String) -> Void
    let onManualFreeze: (UUID) -> Void

    var activeThreads: [ChatThread] { threads.filter { !isFrozenNow($0) } }
    var endedThreads: [ChatThread] { threads.filter { isFrozenNow($0) } }

    var body: some View {
        List {
            if threads.isEmpty {
                Text("No conversations yet.")
                    .foregroundStyle(Color(hex: "#D4C5A0"))
                    .font(.system(size: 14, weight: .light))
                    .listRowBackground(Color.white)
            } else {
                // Active
                if !activeThreads.isEmpty {
                    ForEach(activeThreads) { thread in
                        NavigationLink {
                            ChatDetailView(
                                thread: binding(for: thread.id),
                                isFrozenNow: isFrozenNow,
                                onSend: onSend,
                                onManualFreeze: onManualFreeze
                            )
                        } label: {
                            ThreadCard(thread: thread, isEnded: false)
                        }
                        .listRowBackground(Color.white)
                        .listRowSeparator(.hidden)
                    }
                }

                // Ended
                if !endedThreads.isEmpty {
                    ForEach(endedThreads) { thread in
                        NavigationLink {
                            ChatDetailView(
                                thread: binding(for: thread.id),
                                isFrozenNow: isFrozenNow,
                                onSend: onSend,
                                onManualFreeze: onManualFreeze
                            )
                        } label: {
                            ThreadCard(thread: thread, isEnded: true)
                        }
                        .listRowBackground(Color.white)
                        .listRowSeparator(.hidden)
                    }
                }
            }
        }
        .listStyle(.plain)
        .background(Color.white)
    }

    private func binding(for id: UUID) -> Binding<ChatThread> {
        guard let idx = threads.firstIndex(where: { $0.id == id }) else {
            return .constant(ChatThread(title: "Missing", ttlSeconds: AppState.chatTTL))
        }
        return $threads[idx]
    }
}

// MARK: - Thread Card
struct ThreadCard: View {
    let thread: ChatThread
    let isEnded: Bool

    // 假设未读数，之后可以加到 ChatThread model 里
    let unreadCount: Int = 0

    var lastMessage: String {
        thread.messages.last?.text ?? "No messages yet"
    }

    var goldGradient: LinearGradient {
        LinearGradient(
            colors: [Color(hex: "#C9A84C"), Color(hex: "#E8CC7A"), Color(hex: "#B8922E")],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            // 左侧金色竖线
            RoundedRectangle(cornerRadius: 2)
                .fill(isEnded
                      ? LinearGradient(colors: [Color(hex: "#E8E0CC")], startPoint: .top, endPoint: .bottom)
                      : goldGradient
                )
                .frame(width: 2, height: 44)

            VStack(alignment: .leading, spacing: 4) {
                Text(thread.title)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundColor(isEnded ? Color(hex: "#C4B89A") : Color(hex: "#2C2416"))

                Text(lastMessage)
                    .font(.system(size: 13, weight: .light))
                    .foregroundColor(isEnded ? Color(hex: "#D4C9B0") : Color(hex: "#8C7E6A"))
                    .lineLimit(1)
            }

            Spacer()

            // 未读角标 / ended标记
            if isEnded {
                Text("ended")
                    .font(.system(size: 10, weight: .light))
                    .tracking(0.8)
                    .foregroundColor(Color(hex: "#C4B89A"))
            } else if unreadCount > 0 {
                ZStack {
                    Circle()
                        .fill(goldGradient)
                        .frame(width: 20, height: 20)
                    Text("\(unreadCount)")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.white)
                }
            }
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 4)
    }
}



#Preview {
    NavigationStack {
        InboxView(
            threads: .constant([
                ChatThread(title: "Wandering Soul", messages: [
                    ChatMessage(text: "hey, your post really resonated with me", isMe: false)
                ], ttlSeconds: AppState.chatTTL),
                ChatThread(title: "Quiet Rain", messages: [
                    ChatMessage(text: "thank you for listening", isMe: true)
                ], ttlSeconds: 0, isManuallyFrozen: true)
            ]),
            isFrozenNow: { thread in
                thread.isManuallyFrozen || Date() >= thread.expiresAt
            },
            onSend: { _, _ in },
            onManualFreeze: { _ in }
        )
    }
}
