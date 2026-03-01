//
//  InboxView.swift
//  Here
//
//  Created by yuchen on 1/27/26.
//
import SwiftUI

struct InboxView: View {
    @ObservedObject var app: AppState

    var body: some View {
        NavigationStack {
            List {
                if app.threads.isEmpty {
                    Text("No chats yet. Start one from a post.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(app.threads) { thread in
                        NavigationLink {
                            ChatDetailView(thread: thread, app: app)
                        } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(thread.postTitle).font(.headline)
                                Text(thread.isFrozen() ? "Frozen" : "Active")
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
}

#Preview {
    InboxView(app: AppState(authService: AuthService()))
}
