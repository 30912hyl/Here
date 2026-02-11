import SwiftUI

struct ContentView: View {
    @State private var selectedTab: MainTab = .feed
    @State private var lastNonCreateTab: MainTab = .feed
    @State private var showCreateSheet = false

    @StateObject private var app = AppState()

    var body: some View {
        let activePosts = app.activePosts()

        TabView(selection: $selectedTab) {

            VoiceView()
                .tabItem { Label("Voice", systemImage: "waveform") }
                .tag(MainTab.voice)

            FeedView(
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

            InboxView(
                threads: $app.threads,
                isFrozenNow: { thread in app.isThreadFrozenNow(thread) },
                onSend: { id, text in app.sendMessage(threadId: id, text: text) },
                onManualFreeze: { id in app.manualFreezeThread(threadId: id) }
            )
            .tabItem { Label("Chats", systemImage: "bubble.left.and.bubble.right") }
            .tag(MainTab.inbox)

            ProfileView()
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
        .sheet(isPresented: $showCreateSheet) { [app] in
            CreatePostView { post in
                app.addPost(post)
            }
        }
    }
}

#Preview {
    ContentView()
}
