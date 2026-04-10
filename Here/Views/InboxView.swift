// InboxView.swift
import SwiftUI

struct InboxView: View {
    @ObservedObject var app: AppState

    var activeThreads: [ChatThread] { app.threads.filter { !$0.isFrozen() } }
    var endedThreads: [ChatThread] { app.threads.filter { $0.isFrozen() } }

    var body: some View {
        NavigationStack {
            List {
                if app.threads.isEmpty {
                    Text("No conversations yet.")
                        .foregroundStyle(Color(hex: "#D4C5A0"))
                        .font(.system(size: 14, weight: .light))
                        .listRowBackground(Color.white)
                } else {
                    if !activeThreads.isEmpty {
                        ForEach(activeThreads) { thread in
                            NavigationLink {
                                ChatDetailView(thread: thread, app: app)
                            } label: {
                                ThreadCard(thread: thread, isEnded: false, app: app)
                            }
                            .listRowBackground(Color.white)
                            .listRowSeparator(.hidden)
                        }
                    }

                    if !endedThreads.isEmpty {
                        ForEach(endedThreads) { thread in
                            NavigationLink {
                               ChatDetailView(thread: thread, app: app)
                            } label: {
                                ThreadCard(thread: thread, isEnded: true, app: app)
                            }
                            .listRowBackground(Color.white)
                            .listRowSeparator(.hidden)
                        }
                    }
                }
            }
            .listStyle(.plain)
            .background(Color.white)
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

// MARK: - Thread Card
struct ThreadCard: View {
    let thread: ChatThread
    let isEnded: Bool
    @ObservedObject var app: AppState

    let unreadCount: Int = 0

    var lastMessage: String {
        let threadId = thread.id ?? ""
        return app.messages[threadId]?.last?.text ?? "No messages yet"
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
            RoundedRectangle(cornerRadius: 2)
                .fill(isEnded
                      ? LinearGradient(colors: [Color(hex: "#E8E0CC")], startPoint: .top, endPoint: .bottom)
                      : goldGradient
                )
                .frame(width: 2, height: 44)

            VStack(alignment: .leading, spacing: 4) {
                Text(thread.nickname)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundColor(isEnded ? Color(hex: "#C4B89A") : Color(hex: "#2C2416"))

                Text("re: \(thread.postTitle)")
                    .font(.system(size: 12, weight: .light))
                    .foregroundColor(isEnded ? Color(hex: "#D4C9B0") : Color(hex: "#C4B89A"))

                Text(lastMessage)
                    .font(.system(size: 13, weight: .light))
                    .foregroundColor(isEnded ? Color(hex: "#D4C9B0") : Color(hex: "#8C7E6A"))
                    .lineLimit(1)
            }

            Spacer()

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
    InboxView(app: AppState(authService: AuthService()))
}
