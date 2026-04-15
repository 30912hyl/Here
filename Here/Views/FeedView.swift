import SwiftUI

struct FeedView: View {
    let posts: [Post]
    let onStartChat: (Post) -> Void
    let onLike: (String) -> Void

    var body: some View {
        if posts.isEmpty {
            ZStack {
                StarryBackgroundView()
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
    @State private var selectedImageURL: String? = nil

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
                LinearGradient(
                    stops: [
                        .init(color: Color(hex: "#F7E7CE"), location: 0.0),
                        .init(color: Color(hex: "#FFFFFF"), location: 0.5)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .ignoresSafeArea()

                StarryBackgroundView()

                VStack(spacing: 0) {
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

                            if !post.imageURLs.isEmpty {
                                ImageGridView(
                                    imageURLs: post.imageURLs,
                                    onImageTap: { urlString in
                                        selectedImageURL = urlString
                                    }
                                )
                            }
                        }
                        .padding(.horizontal, 28)
                        .frame(minHeight: geo.size.height - 140, alignment: .center)
                    }

                    HStack(spacing: 20) {
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
                }
            }
            .fullScreenCover(item: Binding(
                get: { selectedImageURL.map { FullScreenImageItem(url: $0) } },
                set: { selectedImageURL = $0?.url }
            )) { item in
                FullScreenImageView(imageURL: item.url) {
                    selectedImageURL = nil
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
}

// MARK: - 图片网格（放大版）
struct ImageGridView: View {
    let imageURLs: [String]
    let onImageTap: (String) -> Void

    var body: some View {
        let columns = [
            GridItem(.flexible(), spacing: 12),
            GridItem(.flexible(), spacing: 12)
        ]

        LazyVGrid(columns: columns, spacing: 12) {
            ForEach(imageURLs, id: \.self) { urlString in
                if let url = URL(string: urlString) {
                    Button {
                        onImageTap(urlString)
                    } label: {
                        AsyncImage(url: url) { phase in
                            switch phase {
                            case .success(let image):
                                image
                                    .resizable()
                                    .scaledToFill()
                                    .frame(width: 160, height: 160)
                                    .clipShape(RoundedRectangle(cornerRadius: 16))
                            case .failure:
                                Color.gray.opacity(0.3)
                                    .frame(width: 160, height: 160)
                                    .clipShape(RoundedRectangle(cornerRadius: 16))
                                    .overlay(
                                        Image(systemName: "photo")
                                            .font(.system(size: 40))
                                            .foregroundColor(.gray)
                                    )
                            case .empty:
                                Color.gray.opacity(0.3)
                                    .frame(width: 160, height: 160)
                                    .clipShape(RoundedRectangle(cornerRadius: 16))
                                    .overlay(ProgressView())
                            @unknown default:
                                EmptyView()
                            }
                        }
                    }
                }
            }
        }
    }
}

// MARK: - 全屏图片查看器
struct FullScreenImageView: View {
    let imageURL: String
    let onDismiss: () -> Void

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if let url = URL(string: imageURL) {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .scaledToFit()
                    case .failure:
                        VStack(spacing: 12) {
                            Image(systemName: "photo")
                                .font(.system(size: 50))
                                .foregroundColor(.white.opacity(0.5))
                            Text("Failed to load image")
                                .foregroundColor(.white.opacity(0.7))
                        }
                    case .empty:
                        ProgressView()
                            .tint(.white)
                    @unknown default:
                        EmptyView()
                    }
                }
            }

            VStack {
                HStack {
                    Spacer()
                    Button {
                        onDismiss()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 32))
                            .foregroundColor(.white.opacity(0.8))
                            .padding()
                    }
                }
                Spacer()
            }
        }
    }
}

// MARK: - 辅助类型
struct FullScreenImageItem: Identifiable {
    let id = UUID()
    let url: String
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
