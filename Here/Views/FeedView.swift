import SwiftUI

struct FeedView: View {
    let posts: [Post]
    let uid: String
    let onStartChat: (Post) -> Void
    let onToggleLike: (Post, Bool) -> Void

    @State private var selectedTag: String? = nil
    @State private var showAllTags = false

    private var tagCounts: [TagCount] {
        var freq: [String: Int] = [:]
        var firstSeen: [String: Int] = [:]
        for post in posts {
            // Legacy text tags may exist in Firestore — tags are emoji-only now
            for tag in post.tags where tag.isEmojiOnly {
                freq[tag, default: 0] += 1
                if firstSeen[tag] == nil { firstSeen[tag] = firstSeen.count }
            }
        }
        // Dictionary order is hash-seeded and changes every launch, so ties must
        // be broken deterministically or pills shuffle between sessions/renders
        return freq
            .map { TagCount(tag: $0.key, count: $0.value) }
            .sorted {
                if $0.count != $1.count { return $0.count > $1.count }
                return firstSeen[$0.tag, default: .max] < firstSeen[$1.tag, default: .max]
            }
    }

    private var filteredPosts: [Post] {
        guard let tag = selectedTag else { return posts }
        let matching = posts.filter { $0.tags.contains(tag) }
        // Tag disappeared (e.g. its posts expired) — fall back to everything
        return matching.isEmpty ? posts : matching
    }

    var body: some View {
        if posts.isEmpty {
            ZStack {
                StarryBackgroundView()
                VStack(spacing: 16) {
                    Image(systemName: "heart")
                        .font(.system(size: 40, weight: .thin))
                        .foregroundStyle(LinearGradient(
                            colors: [Color(hex: "#DDBE74")],
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
            ZStack(alignment: .top) {
                ScrollView(.vertical, showsIndicators: false) {
                    LazyVStack(spacing: 0) {
                        ForEach(filteredPosts) { post in
                            SinglePostView(
                                post: post,
                                uid: uid,
                                onStartChat: onStartChat,
                                onToggleLike: onToggleLike
                            )
                            .containerRelativeFrame(.vertical)
                        }
                    }
                }
                .scrollTargetBehavior(.paging)
                .ignoresSafeArea()
                .id(selectedTag ?? "all")  // switching tags resets scroll to the first post

                EmojiTagBar(
                    tags: tagCounts,
                    selectedTag: $selectedTag,
                    onExpand: {
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.86)) {
                            showAllTags = true
                        }
                    }
                )
                .padding(.top, 4)
            }
            .overlay {
                if showAllTags {
                    AllTagsOverlay(
                        tags: tagCounts,
                        selectedTag: $selectedTag,
                        onClose: {
                            withAnimation(.spring(response: 0.35, dampingFraction: 0.86)) {
                                showAllTags = false
                            }
                        }
                    )
                    .transition(.move(edge: .top).combined(with: .opacity))
                }
            }
        }
    }
}

// MARK: - Emoji 标签筛选条
struct TagCount: Identifiable {
    var id: String { tag }
    let tag: String
    let count: Int
}

struct EmojiTagBar: View {
    let tags: [TagCount]
    @Binding var selectedTag: String?
    let onExpand: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    EmojiTagPill(label: "All", count: nil, isSelected: selectedTag == nil) {
                        selectedTag = nil
                    }
                    ForEach(tags) { item in
                        EmojiTagPill(
                            label: "#\(item.tag)",
                            count: item.count,
                            isSelected: selectedTag == item.tag
                        ) {
                            selectedTag = (selectedTag == item.tag) ? nil : item.tag
                        }
                    }
                }
                .padding(.leading, 16)
                .padding(.vertical, 6)
            }

            if !tags.isEmpty {
                Button(action: onExpand) {
                    Image(systemName: "chevron.down")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(Color(hex: "#9A7B2E"))
                        .frame(width: 30, height: 30)
                        .background(Circle().fill(.ultraThinMaterial))
                        .overlay(Circle().stroke(Color(hex: "#E8CC7A").opacity(0.7), lineWidth: 1))
                }
                .buttonStyle(.plain)
                .padding(.trailing, 16)
            }
        }
    }
}

// MARK: - 全屏标签页(下拉展开,上下滑动浏览全部标签)
struct AllTagsOverlay: View {
    let tags: [TagCount]
    @Binding var selectedTag: String?
    let onClose: () -> Void

    var body: some View {
        ZStack(alignment: .top) {
            Rectangle()
                .fill(.ultraThinMaterial)
                .background(Color(hex: "#F7E7CE").opacity(0.45))
                .ignoresSafeArea()
                .onTapGesture { onClose() }

            VStack(spacing: 0) {
                HStack {
                    Text("Tags")
                        .font(.system(size: 22, weight: .light))
                        .foregroundColor(Color(hex: "#5C3A1E"))
                    Spacer()
                    Button(action: onClose) {
                        Image(systemName: "chevron.up")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(Color(hex: "#9A7B2E"))
                            .frame(width: 32, height: 32)
                            .background(Circle().fill(.ultraThinMaterial))
                            .overlay(Circle().stroke(Color(hex: "#E8CC7A").opacity(0.7), lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)
                .padding(.bottom, 14)

                ScrollView(.vertical, showsIndicators: false) {
                    LazyVGrid(
                        columns: [GridItem(.adaptive(minimum: 88), spacing: 10)],
                        spacing: 12
                    ) {
                        EmojiTagPill(label: "All", count: nil, isSelected: selectedTag == nil) {
                            selectedTag = nil
                            onClose()
                        }
                        ForEach(tags) { item in
                            EmojiTagPill(
                                label: "#\(item.tag)",
                                count: item.count,
                                isSelected: selectedTag == item.tag
                            ) {
                                selectedTag = (selectedTag == item.tag) ? nil : item.tag
                                onClose()
                            }
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 40)
                }
            }
        }
    }
}

struct EmojiTagPill: View {
    let label: String
    let count: Int?
    let isSelected: Bool
    let action: () -> Void

    private var goldGradient: LinearGradient {
        LinearGradient(
            colors: [Color(hex: "#DDBE74")],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Text(label)
                    .font(.system(size: 14, weight: .medium))
                if let count {
                    Text("\(count)")
                        .font(.system(size: 11, weight: .semibold))
                        .opacity(0.7)
                }
            }
            .foregroundColor(isSelected ? Color(hex: "#A98634") : Color(hex: "#9A7B2E"))
            .padding(.horizontal, 13)
            .padding(.vertical, 7)
            .background {
                if isSelected {
                    GoldShimmerCapsule(lineWidth: 2)
                } else {
                    Capsule().fill(.ultraThinMaterial)
                }
            }
            .overlay {
                if !isSelected {
                    Capsule().stroke(Color(hex: "#E8CC7A").opacity(0.7), lineWidth: 1)
                }
            }
            .shadow(color: Color(hex: "#D0AC5F").opacity(isSelected ? 0.25 : 0.1), radius: 4, y: 1)
        }
        .buttonStyle(.plain)
        .animation(.easeInOut(duration: 0.15), value: isSelected)
    }
}

// MARK: - Single Post
struct SinglePostView: View {
    let post: Post
    let uid: String
    let onStartChat: (Post) -> Void
    let onToggleLike: (Post, Bool) -> Void

    @State private var likeScale = 1.0
    @State private var showReport = false
    @State private var selectedImageURL: String? = nil
    @State private var optimisticLiked: Bool? = nil

    private var liked: Bool { optimisticLiked ?? post.likedBy.contains(uid) }
    private var displayCount: Int {
        guard let optimistic = optimisticLiked else { return post.likeCount }
        let serverLiked = post.likedBy.contains(uid)
        guard optimistic != serverLiked else { return post.likeCount }
        return max(0, post.likeCount + (optimistic ? 1 : -1))
    }

    var goldGradient: LinearGradient {
        LinearGradient(
            colors: [Color(hex: "#DDBE74")],
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

                            if !post.tags.filter(\.isEmojiOnly).isEmpty {
                                ScrollView(.horizontal, showsIndicators: false) {
                                    HStack(spacing: 6) {
                                        ForEach(post.tags.filter(\.isEmojiOnly), id: \.self) { tag in
                                            Text("#\(tag)")
                                                .font(.system(size: 15))
                                                .padding(.horizontal, 10)
                                                .padding(.vertical, 5)
                                                .background(Capsule().fill(Color(hex: "#F7E7CE").opacity(0.55)))
                                                .overlay(Capsule().stroke(Color(hex: "#E8CC7A").opacity(0.7), lineWidth: 1))
                                        }
                                    }
                                }
                            }

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
                        .frame(minHeight: geo.size.height - 230, alignment: .center)
                    }

                    HStack(spacing: 20) {
                        Button {
                            let currentLiked = liked
                            optimisticLiked = !currentLiked
                            onToggleLike(post, currentLiked)
                            if !currentLiked {
                                withAnimation(.spring(response: 0.3, dampingFraction: 0.4)) {
                                    likeScale = 1.4
                                }
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                                    withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
                                        likeScale = 1.0
                                    }
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
                                Text("\(displayCount)")
                                    .font(.system(size: 13, weight: .light))
                                    .monospacedDigit()
                                    .foregroundColor(liked ? Color(hex: "#C9A84C") : Color(hex: "#D4C5A0"))
                            }
                        }

                        // Chat button — hidden on own posts
                        if post.authorUID != uid {
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
                                .foregroundColor(Color(hex: "#A98634"))
                                .padding(.horizontal, 18)
                                .padding(.vertical, 10)
                                .background(GoldShimmerCapsule(lineWidth: 2.5, colors: GoldShimmer.softColors))
                                .shadow(color: Color(hex: "#D0AC5F").opacity(0.12), radius: 5, y: 1)
                            }
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
                    .padding(.top, 20)
                    // Keeps the action row above the floating glass tab bar
                    .padding(.bottom, 112)
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
        .onChange(of: post.likedBy) {
            // Server state caught up — drop the optimistic override
            optimisticLiked = nil
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
                        // Downsampled decode — full-res AsyncImage here got the app
                        // jetsam-killed once a few photo posts were on screen
                        RemoteImageView(url: url, maxPixelSize: 600) { phase in
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
                            case .loading:
                                Color.gray.opacity(0.3)
                                    .frame(width: 160, height: 160)
                                    .clipShape(RoundedRectangle(cornerRadius: 16))
                                    .overlay(ProgressView())
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
                RemoteImageView(url: url, maxPixelSize: 1600) { phase in
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
                    case .loading:
                        ProgressView()
                            .tint(.white)
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
            Post(title: "Feeling grateful", bodyText: "Had a wonderful day today and wanted to share the vibes.", authorUID: "preview", tags: ["😄", "🍚🥄"]),
            Post(title: "Can't sleep", bodyText: "Anyone else up late thinking about everything?", authorUID: "preview", tags: ["😴", "🌙"]),
            Post(title: "New here", bodyText: "Just downloaded this app. Excited to connect.", authorUID: "preview")
        ],
        uid: "preview",
        onStartChat: { _ in },
        onToggleLike: { _, _ in }
    )
}
