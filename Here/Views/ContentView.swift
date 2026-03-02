import SwiftUI

struct ContentView: View {
    @EnvironmentObject var authService: AuthService
    
    @State private var selectedTab: MainTab = .feed
    @State private var lastNonCreateTab: MainTab = .feed
    @State private var showCreateSheet = false
    @StateObject private var app = AppState(authService: AuthService())

    var body: some View {
        Group {
            if authService.isSignedIn {
                mainTabView
            } else {
                ProgressView("Connecting...")
            }
        }
        .onAppear {
            print("ContentView appeared, isSignedIn: \(authService.isSignedIn)")
            if authService.isSignedIn {
                app.authService = authService
                app.startListening()
            }
        }
        .onChange(of: authService.isSignedIn) {
            print("isSignedIn changed to: \(authService.isSignedIn)")
            if authService.isSignedIn {
                app.authService = authService
                app.startListening()
            }
        }
        .onDisappear {
            app.stopListening()
        }
    }

    private var mainTabView: some View {
        TabView(selection: $selectedTab) {

            VoiceView()
                .tabItem { Label("Voice", systemImage: "waveform") }
                .tag(MainTab.voice)

            FeedView(
                posts: app.posts,
                onStartChat: { post in
                    Task {
                        _ = await app.createThreadFromPost(post)
                        selectedTab = .inbox
                    }
                }
            )
            .tabItem { Label("Posts", systemImage: "rectangle.portrait.on.rectangle.portrait") }
            .tag(MainTab.feed)

            Color.clear
                .tabItem { Label(" ", systemImage: "heart.fill") }
                .tag(MainTab.create)

            InboxView(app: app)
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
        .sheet(isPresented: $showCreateSheet) {
            CreatePostView(app: app)
        }
    }
}

#Preview {
    ContentView()
        .environmentObject(AuthService())
}
