import SwiftUI

struct FeedView: View {
    let posts: [Post]
    let onStartChat: (Post) -> Void

    var body: some View {
        if posts.isEmpty {
            VStack(spacing: 12) {
                Text("No posts in the last 24 hours.")
                    .font(.headline)
                Text("Tap ❤️ to share how you feel.")
                    .foregroundStyle(.secondary)
            }
            .padding()
        } else {
            ScrollView(.vertical, showsIndicators: false) {
                LazyVStack(spacing: 0) {
                    ForEach(posts) { post in
                        SinglePostView(post: post, onStartChat: onStartChat)
                            .containerRelativeFrame(.vertical)
                    }
                }
            }
            .scrollTargetBehavior(.paging)
            .ignoresSafeArea()
        }
    }
}

struct SinglePostView: View {
    let post: Post
    let onStartChat: (Post) -> Void

    var body: some View {
        ZStack {
            // Background: first image fills the screen, or a gradient fallback
            if let firstURL = post.imageURLs.first, let url = URL(string: firstURL) {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .scaledToFill()
                            .overlay(Color.black.opacity(0.4))
                    case .failure:
                        gradientFallback
                    case .empty:
                        gradientFallback.overlay(ProgressView().tint(.white))
                    @unknown default:
                        gradientFallback
                    }
                }
            } else {
                gradientFallback
            }

            // Content centered
            VStack(alignment: .leading, spacing: 10) {
                Text(post.title)
                    .font(.title2)
                    .bold()
                    .foregroundStyle(.white)

                if !post.bodyText.isEmpty {
                    Text(post.bodyText)
                        .font(.body)
                        .foregroundStyle(.white.opacity(0.85))
                        .lineLimit(4)
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
                                    .clipShape(RoundedRectangle(cornerRadius: 8))
                                }
                            }
                        }
                    }
                }

                Button {
                    onStartChat(post)
                } label: {
                    Text("Private chat")
                        .fontWeight(.semibold)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(.white.opacity(0.2))
            }
            .padding(.horizontal, 20)
        }
        .clipped()
    }
    
    private var gradientFallback: some View {
        LinearGradient(
            colors: [.black, Color(.darkGray)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
}

#Preview {
    FeedView(posts: [], onStartChat: { _ in })
}
