import SwiftUI

struct FeedView: View {
    let posts: [Post]
    let onStartChat: (Post) -> Void
    let onLike: (String) -> Void

    var body: some View {
        if posts.isEmpty {
            VStack(spacing: 16) {
                Image(systemName: "heart")
                    .font(.system(size: 40, weight: .thin))
                    .foregroundStyle(LinearGradient(
                        colors: [Color(hex: "#C9A84C"), Color(hex: "#E8CC7A"), Color(hex: "#B8922E")],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ))
                Text("No posts yet.")
                    .font(.system(size: 16, weight: .light))
                    .foregroundColor(Color(hex: "#C4A55A"))
                Text("Be the first to share.")
                    .font(.system(size: 13, weight: .light))
                    .foregroundColor(Color(hex: "#D4C5A0"))
            }
        } else {
            ScrollView(.vertical, showsIndicators: false) {
                LazyVStack(spacing: 0) {
                    ForEach(posts) { post in
                        SinglePostView(
                            post: post,
                            onStartChat: onStartChat,
                            onLike: onLike
                        )
                        .containerRelativeFrame(.vertical)
                    }
                }
            }
            .scrollTargetBehavior(.paging)
            .ignoresSafeArea(edges: .top)
        }
    }
}

// MARK: - Single Post
struct SinglePostView: View {
    let post: Post
    let onStartChat: (Post) -> Void
    let onLike: (String) -> Void

    @State private var liked = false
    @State private var likeScale = 1.0
    @State private var showReport = false

    var goldGradient: LinearGradient {
        LinearGradient(
            colors: [Color(hex: "#C9A84C"), Color(hex: "#E8CC7A"), Color(hex: "#B8922E")],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    var body: some View {
        GeometryReader { geo in
            ZStack {
                Color.white.ignoresSafeArea()
                
                // Background image if exists
                if let firstURL = post.imageURLs.first, let url = URL(string: firstURL) {
                    AsyncImage(url: url) { phase in
                        switch phase {
                        case .success(let image):
                            image
                                .resizable()
                                .scaledToFill()
                                .frame(width: geo.size.width, height: geo.size.height)
                                .clipped()
                                //.overlay(Color.white.opacity(0.15))
                        case .failure:
                            EmptyView()
                        case .empty:
                            //gradientFallback.overlay(ProgressView().tint(.white))
                            EmptyView()
                        @unknown default:
                            EmptyView()
                        }
                    }
                    .clipped()
                }
                
                VStack(spacing: 0) {
                    // Scrollable content area - centered
                    ScrollView(.vertical, showsIndicators: false) {
                        VStack(alignment: .leading, spacing: 16) {
                            Text(post.title)
                                .font(.system(size: 24, weight: .light))
                                .foregroundColor(.black)
                            
                            if !post.bodyText.isEmpty {
                                Text(post.bodyText)
                                    .font(.system(size: 16, weight: .light))
                                    .foregroundColor(Color(hex: "#5C5C5C"))
                                    .lineSpacing(6)
                            }
                            
                            // Extra image thumbnails
                            if post.imageURLs.count > 1 {
                                ScrollView(.horizontal, showsIndicators: false) {
                                    HStack(spacing: 8) {
                                        ForEach(post.imageURLs.dropFirst(), id: \.self) { urlString in
                                            if let url = URL(string: urlString) {
                                                AsyncImage(url: url) { image in
                                                    image.resizable().scaledToFill()
                                                } placeholder: {
                                                    Color.gray.opacity(0.3)
                                                }
                                                .frame(width: 80, height: 80)
                                                .clipShape(RoundedRectangle(cornerRadius: 12))
                                            }
                                        }
                                    }
                                }
                            }
                        }
                        .padding(.horizontal, 28)
                        .frame(minHeight: geo.size.height - 140, alignment: .center)
                    }
                    
                    // Action buttons — always pinned at bottom
                    HStack(spacing: 20) {
                        // Like button
                        Button {
                            guard !liked else { return }
                            liked = true
                            if let postId = post.id {
                                onLike(postId)
                            }
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.4)) {
                                likeScale = 1.4
                            }
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                                withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
                                    likeScale = 1.0
                                }
                            }
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: liked ? "heart.fill" : "heart")
                                    .font(.system(size: 20, weight: .light))
                                    .foregroundStyle(
                                        liked
                                        ? goldGradient
                                        : LinearGradient(colors: [Color(hex: "#D4C5A0")], startPoint: .top, endPoint: .bottom)
                                    )
                                    .scaleEffect(likeScale)
                                Text("\(post.likeCount)")
                                    .font(.system(size: 13, weight: .light))
                                    .foregroundColor(liked ? Color(hex: "#C9A84C") : Color(hex: "#D4C5A0"))
                            }
                        }
                        
                        // Chat button
                        Button {
                            onStartChat(post)
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: "bubble.left")
                                    .font(.system(size: 14, weight: .light))
                                Text("Chat privately")
                                    .font(.system(size: 13, weight: .light))
                                    .tracking(0.3)
                            }
                            .foregroundColor(.white)
                            .padding(.horizontal, 18)
                            .padding(.vertical, 9)
                            .background(goldGradient)
                            .clipShape(Capsule())
                        }
                        
                        Spacer()
                        
                        // Report menu
                        Menu {
                            Button(role: .destructive) {
                                showReport = true
                            } label: {
                                Label("Report Post", systemImage: "flag")
                            }
                        } label: {
                            Image(systemName: "ellipsis")
                                .font(.system(size: 18, weight: .light))
                                .foregroundColor(Color(hex: "#D4C5A0"))
                        }
                    }
                    .padding(.horizontal, 28)
                    .padding(.vertical, 20)
                    //.padding(.bottom, 50) // Clear the tab bar
                }
            }
        }
        .alert("Report this post?", isPresented: $showReport) {
            Button("Report", role: .destructive) { }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("Thank you for helping keep this space safe.")
        }
    }
//    private var gradientFallback: some View {
//        LinearGradient(
//            colors: [.black, Color(.darkGray)],
//            startPoint: .topLeading,
//            endPoint: .bottomTrailing
//        )
//    }
}

#Preview {
    FeedView(
        posts: [
            Post(title: "Feeling grateful", bodyText: "Had a wonderful day today and wanted to share the vibes.", authorUID: "preview"),
            Post(title: "Can't sleep", bodyText: "Anyone else up late thinking about everything?", authorUID: "preview"),
            Post(title: "New here", bodyText: "Just downloaded this app. Excited to connect.", authorUID: "preview")
        ],
        onStartChat: { _ in },
        onLike: { _ in }
    )
}
