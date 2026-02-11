//
//  InboxView.swift
//  Here
//
//  Created by yuchen on 1/27/26.
//
import SwiftUI

struct InboxView: View {
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

#Preview {
    InboxView(
        threads: .constant([]),
        isFrozenNow: { _ in false },
        onSend: { _, _ in },
        onManualFreeze: { _ in }
    )
}
