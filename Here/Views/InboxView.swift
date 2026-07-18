// InboxView.swift
import SwiftUI

struct InboxView: View {
    @ObservedObject var app: AppState
    @Binding var navigateToThreadId: String?
    // Tells ContentView to hide the floating tab bar while a chat is open,
    // otherwise it covers the message input bar.
    @Binding var isChatOpen: Bool

    @State private var navigationPath = NavigationPath()

    // Most recently active conversations first, like iMessage
    var activeThreads: [ChatThread] {
        app.threads.filter { !$0.isFrozen() }
            .sorted { app.lastActivity(of: $0) > app.lastActivity(of: $1) }
    }
    var endedThreads: [ChatThread] {
        app.threads.filter { $0.isFrozen() }
            .sorted { app.lastActivity(of: $0) > app.lastActivity(of: $1) }
    }

    private func tryNavigate() {
        guard let threadId = navigateToThreadId,
              app.threads.contains(where: { $0.id == threadId }) else { return }
        navigationPath = NavigationPath()
        navigationPath.append(threadId)
        navigateToThreadId = nil
    }

    var body: some View {
        NavigationStack(path: $navigationPath) {
            List {
                if app.threads.isEmpty {
                    Text("No conversations yet.")
                        .foregroundStyle(Color(hex: "#E4DCC6"))
                        .font(.system(size: 14, weight: .light))
                        .listRowBackground(Color.white)
                } else {
                    if !activeThreads.isEmpty {
                        ForEach(activeThreads) { thread in
                            NavigationLink(value: thread.id ?? "") {
                                ThreadCard(thread: thread, isEnded: false, app: app, unreadCount: app.unreadCount(in: thread))
                            }
                            .listRowBackground(Color.white)
                            .listRowSeparator(.hidden)
                            .listRowInsets(EdgeInsets(top: 2, leading: 20, bottom: 2, trailing: 20))
                        }
                    }

                    // Ended
                    if !endedThreads.isEmpty {
                        ForEach(endedThreads) { thread in
                            NavigationLink(value: thread.id ?? "") {
                                ThreadCard(thread: thread, isEnded: true, app: app, unreadCount: app.unreadCount(in: thread))
                            }
                            .listRowBackground(Color.white)
                            .listRowSeparator(.hidden)
                            .listRowInsets(EdgeInsets(top: 2, leading: 20, bottom: 2, trailing: 20))
                        }
                    }
                }
            }
            .listStyle(.plain)
            .background(Color.white)
            .navigationTitle("Chats")
            .navigationDestination(for: String.self) { threadId in
                if let thread = app.threads.first(where: { $0.id == threadId }) {
                    ChatDetailView(thread: thread, app: app)
                }
            }
        }
        .onChange(of: navigateToThreadId) { tryNavigate() }
        // Threads arrive async — retry the pending navigation once the new thread lands
        .onChange(of: app.threads) { tryNavigate() }
        .onAppear { tryNavigate() }
        .onChange(of: navigationPath.count) {
            withAnimation(.easeInOut(duration: 0.25)) {
                isChatOpen = navigationPath.count > 0
            }
        }
        .onDisappear { isChatOpen = false }
    }
}

// MARK: - Thread Card
struct ThreadCard: View {
    let thread: ChatThread
    let isEnded: Bool
    @ObservedObject var app: AppState

    let unreadCount: Int

    var lastMessage: String {
        let threadId = thread.id ?? ""
        return app.messages[threadId]?.last?.text ?? "No messages yet"
    }

    // 香槟白金：低饱和、带一点冷调的浅金
    var goldGradient: LinearGradient {
        LinearGradient(
            colors: [Color(hex: "#F7EFD8"), Color(hex: "#E6D7AC")],
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
                .frame(width: 2, height: 66)

            VStack(alignment: .leading, spacing: 4) {
                Text(thread.nickname)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundColor(isEnded ? Color(hex: "#DBD1B4") : Color(hex: "#2C2416"))

                Text("re: \(thread.postTitle)")
                    .font(.system(size: 12, weight: .light))
                    .foregroundColor(isEnded ? Color(hex: "#D4C9B0") : Color(hex: "#DBD1B4"))

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
                    .foregroundColor(Color(hex: "#DBD1B4"))
            } else if unreadCount > 0 {
                // 未读只提示"有没有":珍珠感小金珠,大而柔的高光,做页面唯一重音
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [
                                Color(hex: "#FFFDF4"),
                                Color(hex: "#F9EEC6"),
                                Color(hex: "#EFD88E"),
                                Color(hex: "#DDBC55")
                            ],
                            center: UnitPoint(x: 0.4, y: 0.35),
                            startRadius: 0.5,
                            endRadius: 5.5
                        )
                    )
                    .frame(width: 10, height: 10)
                    .shadow(color: Color(hex: "#D0AC5F").opacity(0.35), radius: 2, y: 1)
            }
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 4)
    }
}



#Preview {
//     NavigationStack {
//         InboxView(
//             threads: .constant([
//                 ChatThread(title: "Wandering Soul", messages: [
//                     ChatMessage(text: "hey, your post really resonated with me", isMe: false)
//                 ], ttlSeconds: AppState.chatTTL),
//                 ChatThread(title: "Quiet Rain", messages: [
//                     ChatMessage(text: "thank you for listening", isMe: true)
//                 ], ttlSeconds: 0, isManuallyFrozen: true)
//             ]),
//             isFrozenNow: { thread in
//                 thread.isManuallyFrozen || Date() >= thread.expiresAt
//             },
//             onSend: { _, _ in },
//             onManualFreeze: { _ in }
//         )
//     }
    InboxView(app: AppState(authService: AuthService()), navigateToThreadId: .constant(nil), isChatOpen: .constant(false))
}
