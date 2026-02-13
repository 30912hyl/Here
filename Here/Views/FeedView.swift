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
            if let firstImage = post.images.first {
                Image(uiImage: firstImage)
                    .resizable()
                    .scaledToFill()
                    .overlay(Color.black.opacity(0.4))
            } else {
                LinearGradient(
                    colors: [.black, Color(.darkGray)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
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

                // Extra images (if more than 1)
                if post.images.count > 1 {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(post.images.dropFirst().indices, id: \.self) { idx in
                                Image(uiImage: post.images[idx])
                                    .resizable()
                                    .scaledToFill()
                                    .frame(width: 80, height: 80)
                                    .clipShape(RoundedRectangle(cornerRadius: 8))
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
}

#Preview {
    FeedView(
        posts: [
            Post(title: "Feeling grateful", bodyText: "Had a wonderful day today and wanted to share the vibes."),
            Post(title: "Can't sleep", bodyText: "Anyone else up late thinking about everything?"),
            Post(title: "New here", bodyText: "Just downloaded this app. Excited to connect.")
        ],
        onStartChat: { _ in }
    )
}
