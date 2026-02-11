import SwiftUI

struct FeedView: View {
    let posts: [Post]
    let onStartChat: (Post) -> Void

    var body: some View {
        NavigationStack {
            if posts.isEmpty {
                VStack(spacing: 12) {
                    Text("No posts in the last 24 hours.")
                        .font(.headline)
                    Text("Tap ❤️ to share how you feel.")
                        .foregroundStyle(.secondary)
                }
                .padding()
                .navigationTitle("Posts")
            } else {
                List(posts) { post in
                    VStack(alignment: .leading, spacing: 10) {
                        // Title
                        Text(post.title)
                            .font(.headline)
                            .padding(.top, 6)

                        // Body text
                        if !post.bodyText.isEmpty {
                            Text(post.bodyText)
                                .font(.body)
                                .foregroundStyle(.secondary)
                        }

                        // Images
                        if !post.images.isEmpty {
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 8) {
                                    ForEach(post.images.indices, id: \.self) { idx in
                                        Image(uiImage: post.images[idx])
                                            .resizable()
                                            .scaledToFill()
                                            .frame(width: 140, height: 140)
                                            .clipShape(RoundedRectangle(cornerRadius: 10))
                                    }
                                }
                            }
                        }

                        Button("Private chat") {
                            onStartChat(post)
                        }
                        .buttonStyle(.borderedProminent)
                        .padding(.bottom, 6)
                    }
                }
                .navigationTitle("Posts")
            }
        }
    }
}

#Preview {
    FeedView(
        posts: [Post(title: "Sample", bodyText: "A sample post with text only")],
        onStartChat: { _ in }
    )
}
