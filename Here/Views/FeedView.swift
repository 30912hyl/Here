import SwiftUI

// MARK: - Shared gold palette (FeedView)
private let goldColors: [Color] = [
    Color(hex: "#F8EFD6"),
    Color(hex: "#F2DFAF"),
    Color(hex: "#E8C97A")
]

private let goldAccent = Color(hex: "#E6C35C")
private let goldGradient = LinearGradient(
    colors: goldColors,
    startPoint: .topLeading,
    endPoint: .bottomTrailing
)


// MARK: - FeedView

struct FeedView: View {
    let posts: [Post]
    let tags: [AppState.TagCount]
    let uid: String
    let onStartChat: (Post) -> Void
    let onToggleLike: (Post, Bool) -> Void
    @State private var selectedTag: String? = nil

    var filteredPosts: [Post] {
        guard let tag = selectedTag else { return posts }
        return posts.filter { $0.tags.contains(tag) }
    }

    var body: some View {
        ZStack {
            SparkleBackground()

            VStack(spacing: 0) {
            if !posts.isEmpty {
                TagBar(tags: tags, selectedTag: $selectedTag)
                    .padding(.vertical, 6)
            }

            if filteredPosts.isEmpty {
                VStack(spacing: 16) {
                    Image(systemName: "heart")
                        .font(.system(size: 40, weight: .thin))
                        .foregroundStyle(goldGradient)
                    Text(posts.isEmpty ? "No posts yet." : "No posts tagged #\(selectedTag ?? "").")
                        .font(.system(size: 16, weight: .light))
                        .foregroundColor(goldAccent)
                    if !posts.isEmpty {
                        Text("Be the first to share.")
                            .font(.system(size: 13, weight: .light))
                            .foregroundColor(Color(hex: "#D8C898"))
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
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
                .ignoresSafeArea(edges: .bottom)
                .id(selectedTag ?? "all")
                .background(.clear)
            }
            }
        }
    }
}

// MARK: - TagBar

struct TagBar: View {
    let tags: [AppState.TagCount]
    @Binding var selectedTag: String?

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                TagPill(label: "all", count: nil, isSelected: selectedTag == nil) {
                    selectedTag = nil
                }
                ForEach(tags) { item in
                    TagPill(label: item.tag, count: item.count, isSelected: selectedTag == item.tag) {
                        selectedTag = (selectedTag == item.tag) ? nil : item.tag
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 4)
        }
    }
}

// MARK: - TagPill

struct TagPill: View {
    let label: String
    let count: Int?
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Text("#\(label)")
                    .font(.system(size: 15, weight: .medium))
                    .tracking(0.2)
                if let count {
                    Text("\(count)")
                        .font(.system(size: 13, weight: .regular))
                        .opacity(0.75)
                }
            }
            .foregroundStyle(isSelected ? Color.white : goldAccent)
            .padding(.horizontal, 14)
            .padding(.vertical, 7)
            .background {
                if isSelected {
                    Capsule().fill(goldGradient)
                } else {
                    Capsule().fill(Color.white)
                        .overlay(Capsule().strokeBorder(goldAccent, lineWidth: 1))
                }
            }
        }
        .buttonStyle(.plain)
        .animation(.easeInOut(duration: 0.15), value: isSelected)
    }
}

// MARK: - Soft Corner Mask

private extension View {
    /// Clips content with a blurred rounded-rect mask so corners fade out smoothly.
    func softCorners(radius: CGFloat = 20, fade: CGFloat = 8) -> some View {
        self.mask(
            RoundedRectangle(cornerRadius: radius, style: .continuous)
                .blur(radius: fade)
        )
    }
}

// MARK: - Post Image Strip

private struct PostImageStrip: View {
    let imageURLs: [String]
    let onTap: (String) -> Void
    private let imgW: CGFloat = 155
    private let imgH: CGFloat = 207  // 3:4 portrait ratio

    var body: some View {
        HStack(spacing: 10) {
            ForEach(Array(imageURLs.enumerated()), id: \.offset) { _, urlString in
                if let url = URL(string: urlString) {
                    AsyncImage(url: url) { phase in
                        switch phase {
                        case .success(let img):
                            img.resizable()
                                .scaledToFill()
                                .frame(width: imgW, height: imgH)
                                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                                .onTapGesture { onTap(urlString) }
                        default:
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .fill(Color(hex: "#F2DFAF").opacity(0.5))
                                .frame(width: imgW, height: imgH)
                        }
                    }
                }
            }
            //.scrollTargetBehavior(.paging)
            //.ignoresSafeArea(edges: .top)
        }
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
    @State private var optimisticLiked: Bool? = nil
    @State private var selectedImageURL: String? = nil

    private var liked: Bool { optimisticLiked ?? post.likedBy.contains(uid) }
    private var displayCount: Int {
        guard let optimistic = optimisticLiked else { return post.likeCount }
        let serverLiked = post.likedBy.contains(uid)
        guard optimistic != serverLiked else { return post.likeCount }
        return max(0, post.likeCount + (optimistic ? 1 : -1))
    }
    var body: some View {
        ZStack {
            Color.clear

            VStack(spacing: 0) {
                GeometryReader { geo in
                    VStack(alignment: .leading, spacing: 16) {
                        Text(post.title)
                            .font(.system(size: 26, weight: .bold))
                            .foregroundColor(Color(hex: "#5C3A1E"))

                        if !post.bodyText.isEmpty {
                            Text(post.bodyText)
                                .font(.system(size: 17, weight: .regular))
                                .foregroundColor(Color(hex: "#5C3A1E"))
                                .lineSpacing(8)
                        }

                        if !post.imageURLs.isEmpty {
                            // Negative horizontal padding breaks out of the parent's 28pt inset
                            // so images can scroll edge-to-edge. The strip re-applies leading
                            // padding internally to stay aligned with the text above.
                            ScrollView(.horizontal, showsIndicators: false) {
                                PostImageStrip(imageURLs: post.imageURLs, onTap: { selectedImageURL = $0 })
                                    .padding(.leading, 28)
                                    .padding(.trailing, 40)
                                    .padding(.vertical, 4)
                            }
                            .padding(.horizontal, -28)
                        }
                    }
                    .padding(.horizontal, 28)
                    .frame(width: geo.size.width, height: geo.size.height, alignment: .center)
                }

                HStack(spacing: 20) {
                    Button {
                        let currentLiked = liked
                        optimisticLiked = !currentLiked
                        onToggleLike(post, currentLiked)
                        if !currentLiked {
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.4)) { likeScale = 1.4 }
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                                withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) { likeScale = 1.0 }
                            }
                        }  
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: liked ? "heart.fill" : "heart")
                                .font(.system(size: 26, weight: .light))
                                .foregroundStyle(liked ? goldGradient : LinearGradient(colors: [Color(hex: "#D8C898")], startPoint: .top, endPoint: .bottom))
                                .scaleEffect(likeScale)
                            Text("\(displayCount)")
                                .font(.system(size: 16, weight: .regular))
                                .monospacedDigit()
                                .foregroundColor(liked ? goldAccent : Color(hex: "#D8C898"))
                        }
                    }

                    if post.authorUID != uid {
                        Button { onStartChat(post) } label: {
                            HStack(spacing: 8) {
                                Image(systemName: "bubble.left")
                                    .font(.system(size: 17, weight: .light))
                                Text("Chat privately")
                                    .font(.system(size: 16, weight: .regular))
                                    .tracking(0.3)
                            }
                            .foregroundColor(.white)
                            .padding(.horizontal, 22)
                            .padding(.vertical, 12)
                            .background(goldGradient)
                            .clipShape(Capsule())
                        }
                    }
                    
                    Spacer()

                    Menu {
                        Button(role: .destructive) { showReport = true } label: {
                            Label("Report Post", systemImage: "flag")
                        }
                    } label: {
                        Image(systemName: "ellipsis")
                            .font(.system(size: 18, weight: .light))
                            .foregroundColor(Color(hex: "#D8C898"))
                    }
                }
                .padding(.horizontal, 28)
                .padding(.vertical, 20)
                .padding(.bottom, 80)
            }
        }
        .onChange(of: post.likedBy) {
            if let optimistic = optimisticLiked, post.likedBy.contains(uid) == optimistic {
                optimisticLiked = nil
            }
        }
        .alert("Report this post?", isPresented: $showReport) {
            Button("Report", role: .destructive) { }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("Thank you for helping keep this space safe.")
        }
        .fullScreenCover(isPresented: Binding(
            get: { selectedImageURL != nil },
            set: { if !$0 { selectedImageURL = nil } }
        )) {
            if let urlStr = selectedImageURL, let url = URL(string: urlStr) {
                ImageViewerSheet(url: url) { selectedImageURL = nil }
            }
        }
    }
}

// MARK: - Full Screen Image Viewer

private struct ImageViewerSheet: View {
    let url: URL
    let onDismiss: () -> Void

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Color.black.ignoresSafeArea()
            AsyncImage(url: url) { phase in
                switch phase {
                case .success(let img):
                    img.resizable()
                        .scaledToFit()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                default:
                    ProgressView().tint(.white)
                }
            }
            Button { onDismiss() } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.white)
                    .padding(12)
                    .background(Color.white.opacity(0.25))
                    .clipShape(Circle())
            }
            .padding(.top, 56)
            .padding(.trailing, 20)
        }
        .ignoresSafeArea()
    }
}

// MARK: - Sparkle Background

private struct SparkleParticle {
    let x: CGFloat
    let y: CGFloat
    let outerR: CGFloat
    let isStar: Bool
    let phase: Double
    let phase2: Double
    let duration: Double
    let duration2: Double
    let colorIndex: Int

    static let palette: [Color] = [
        Color(hex: "#EDD870"),
        Color(hex: "#F0E088"),
        Color(hex: "#F4E8A0"),
        Color(hex: "#F8F0C0"),
        Color(hex: "#EAD878"),
    ]

    func opacity(at date: Date) -> Double {
        let t = date.timeIntervalSinceReferenceDate
        let a = sin((t / duration  + phase)  * .pi * 2)
        let b = sin((t / duration2 + phase2) * .pi * 2)
        // Multiply the positive halves of two sine waves: a particle only brightens
        // when both waves crest at the same time, so most particles are dark most of the time.
        let v = max(0.0, a) * max(0.0, b)
        return pow(v, 1.5)
    }
}

struct SparkleBackground: View {
    private let particles: [SparkleParticle]

    init(count: Int = 2500) {
        var rng = SystemRandomNumberGenerator()
        particles = (0..<count).map { i in
            let isStar = i % 3 == 0
            // Power distribution: concentrates particles toward the top of the screen.
            // rawY is uniform [0,1]; raising it to 1.8 skews values toward 0 (top).
            let rawY = CGFloat.random(in: 0.0...1.0, using: &rng)
            let y = pow(rawY, 1.8) * 0.52
            return SparkleParticle(
                x:          CGFloat.random(in: 0.02...0.98, using: &rng),
                y:          y,
                outerR:     isStar
                                ? CGFloat.random(in: 4.0...8.0,  using: &rng)
                                : CGFloat.random(in: 1.5...3.0,  using: &rng),
                isStar:     isStar,
                phase:      Double.random(in: 0...1,        using: &rng),
                phase2:     Double.random(in: 0...1,        using: &rng),
                // Tiered durations (in seconds): 10% fast, 25% medium, 65% slow.
                // Mixing speeds gives a natural starfield feel — most stars breathe
                // slowly, a few flicker quickly.
                duration:   {
                    let r = Double.random(in: 0...1, using: &rng)
                    if r < 0.10 { return Double.random(in: 5.0...8.0,   using: &rng) }
                    if r < 0.35 { return Double.random(in: 10.0...18.0, using: &rng) }
                    return          Double.random(in: 20.0...40.0, using: &rng)
                }(),
                duration2:  {
                    let r = Double.random(in: 0...1, using: &rng)
                    if r < 0.10 { return Double.random(in: 3.0...6.0,   using: &rng) }
                    if r < 0.35 { return Double.random(in: 7.0...13.0,  using: &rng) }
                    return          Double.random(in: 14.0...28.0, using: &rng)
                }(),
                colorIndex: Int.random(in: 0..<5,           using: &rng)
            )
        }
    }

    var body: some View {
        ZStack {
            Color.white
            TimelineView(.animation(minimumInterval: 0.05)) { timeline in
                Canvas { context, size in
                    for p in particles {
                        let raw     = p.opacity(at: timeline.date)
                        let yFade   = max(0.0, 1.0 - p.y / 0.48)
                        let opacity = raw * yFade
                        guard opacity > 0.08 else { continue }

                        let cx    = p.x * size.width
                        let cy    = p.y * size.height
                        let color = SparkleParticle.palette[p.colorIndex].opacity(opacity)

                        if p.isStar {
                            context.draw(
                                Text("✦")
                                    .font(.system(size: p.outerR * 2))
                                    .foregroundStyle(color),
                                at: CGPoint(x: cx, y: cy),
                                anchor: .center
                            )
                        } else {
                            let r = p.outerR
                            context.fill(
                                Path(ellipseIn: CGRect(x: cx-r, y: cy-r, width: r*2, height: r*2)),
                                with: .color(color)
                            )
                        }
                    }
                }
            }
        }
        .ignoresSafeArea()
    }
}

// MARK: - Preview

#Preview("Full feed") {
    FeedView(
        posts: [
            Post(title: "Feeling grateful", bodyText: "Had a wonderful day today and wanted to share the vibes.", imageURLs: [
                "https://picsum.photos/id/10/400/400",
                "https://picsum.photos/id/20/400/400",
                "https://picsum.photos/id/30/400/400",
                "https://picsum.photos/id/40/400/400",
                "https://picsum.photos/id/50/400/400",
            ], authorUID: "preview", tags: ["grateful", "happy"]),
            Post(title: "Can't sleep", bodyText: "Anyone else up late? #sad #anxious", authorUID: "preview", tags: ["sad", "anxious"]),
        ],
        tags: [
            AppState.TagCount(tag: "happy", count: 2),
            AppState.TagCount(tag: "grateful", count: 1),
            AppState.TagCount(tag: "sad", count: 1),
        ],
        uid: "preview",
        onStartChat: { _ in },
        onToggleLike: { _, _ in }
    )
    .background(Color(hex: "#FAF6EE"))
}

#Preview("Single post with images") {
    SinglePostView(
        post: Post(
            title: "Feeling grateful",
            bodyText: "Had a wonderful day today and wanted to share the vibes with everyone here.",
            imageURLs: [
                "https://picsum.photos/id/10/400/400",
                "https://picsum.photos/id/20/400/400",
                "https://picsum.photos/id/30/400/400",
                "https://picsum.photos/id/40/400/400",
                "https://picsum.photos/id/50/400/400",
            ],
            authorUID: "preview"
        ),
        uid: "preview",
        onStartChat: { _ in },
        onToggleLike: { _, _ in }
    )
    .background(Color(hex: "#FAF6EE"))
}

#Preview("Single post text only") {
    SinglePostView(
        post: Post(
            title: "Can't sleep",
            bodyText: "Anyone else up late tonight? #sad #anxious",
            authorUID: "preview"
        ),
        uid: "preview",
        onStartChat: { _ in },
        onToggleLike: { _, _ in }
    )
    .background(Color(hex: "#FAF6EE"))
}
