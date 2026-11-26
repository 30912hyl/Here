import SwiftUI

struct FeedView: View {
    let posts: [Post]
    let uid: String
    let onStartChat: (Post) -> Void
    let onToggleLike: (Post, Bool) -> Void
    let onReportPost: (_ post: Post, _ reasons: [String], _ details: String) -> Void
    let onBlockUser: (Post) -> Void

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
                FeedSkyBackground()
                VStack(spacing: 12) {
                    Image(systemName: "heart")
                        .font(.system(size: 36, weight: .thin))
                        .foregroundColor(Theme.tabOff)
                    Text("No posts yet.")
                        .font(Theme.ui(17))
                        .foregroundColor(Theme.ink)
                    Text("Be the first to share.")
                        .font(Theme.ui(14))
                        .foregroundColor(Theme.ink2)
                }
            }
        } else {
            ZStack(alignment: .top) {
                // 背景放在滚动层下面,翻页时保持不动
                FeedSkyBackground()

                ScrollView(.vertical, showsIndicators: false) {
                    LazyVStack(spacing: 0) {
                        ForEach(filteredPosts) { post in
                            SinglePostView(
                                post: post,
                                uid: uid,
                                onStartChat: onStartChat,
                                onToggleLike: onToggleLike,
                                onReportPost: onReportPost,
                                onBlockUser: onBlockUser
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

// MARK: - 背景:会动的光
/// Feed 的背景是纸上那片会动的光(见 LiquidLight.swift),取代了原来的香槟金天空和星星。
/// 放在滚动层下面,翻页时光不跟着帖子走。
struct FeedSkyBackground: View {
    var body: some View {
        LiquidLightBackground(focusY: 0.5)
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
                            label: item.tag,
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
                        .foregroundColor(Theme.ink2)
                        .frame(width: 34, height: 34)
                        .background(Circle().fill(Color.white.opacity(0.8)))
                        .overlay(Circle().stroke(Theme.outline, lineWidth: 1))
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
                        .font(Theme.ui(22, .light))
                        .foregroundColor(Theme.ink)
                    Spacer()
                    Button(action: onClose) {
                        Image(systemName: "chevron.up")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(Theme.ink2)
                            .frame(width: 34, height: 34)
                            .background(Circle().fill(Color.white.opacity(0.8)))
                            .overlay(Circle().stroke(Theme.outline, lineWidth: 1))
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
                                label: item.tag,
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

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Text(label)
                    .font(Theme.ui(14, isSelected ? .semibold : .medium))
                    .foregroundColor(isSelected ? Theme.ink : Theme.ink2)
                if let count {
                    Text("\(count)")
                        .font(Theme.ui(12, .semibold))
                        .foregroundColor(Theme.ink3)
                }
            }
            .padding(.horizontal, 13)
            .frame(height: 34)
            // 选中 = 最淡的金色底 + 一圈棕色的线(和发帖页选中的标签同一个样子);
            // 没选中是白底加一圈很淡的棕色线。线永远是棕色的,金色只做底。
            .background(Capsule().fill(isSelected ? Theme.selectedFill : Color.white.opacity(0.8)))
            .overlay(Capsule().stroke(isSelected ? Theme.line : Theme.outline, lineWidth: 1))
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
    let onReportPost: (_ post: Post, _ reasons: [String], _ details: String) -> Void
    let onBlockUser: (Post) -> Void

    @State private var likeScale = 1.0
    /// 私聊按钮的金色:哑光,从上到下,不反光。就是未读小圆点的那个金(Theme.matteGold)。
    ///
    /// **定了(老板 2026-11-25 18:32):"我纠结了很久…看了这么多遍之后,我还是决定用三,二可以删掉了。" 不要再动。**
    /// 经过:她 2026-11-23 17:08 选了金色("B1"),一分钟后说第一档(#EFDBA5 → #E3C77A)"颜色有一点太深了,
    /// 这个金色做的有点太显眼了";给了她三档。第一档当天就不要了;2(#F4E5BB → #E9D190,更显眼)和 3(更淡)
    /// 她留了两天,在手机上反复看,最后选了 3。1 和 2 的代码都删了。
    private var chatGold: LinearGradient { Theme.matteGold }
    /// 顶上挡住帖子的那一段有多高:状态栏 + 标签那一排(50)+ 一点空隙(6)。
    /// 这一页铺到了状态栏下面,所以这里的安全区要去问窗口,不能问这一页自己。
    private static var topBarHeight: CGFloat {
        let scene = UIApplication.shared.connectedScenes.first { $0 is UIWindowScene } as? UIWindowScene
        return (scene?.keyWindow?.safeAreaInsets.top ?? 47) + 56
    }
    /// 下面那一排按钮连同它的留白有多高(上 20 + 按钮 44 + 下 93)
    private static let actionRowHeight: CGFloat = 157
    /// 帖子在这一页上放多高:中线在"标签栏下沿到按钮上沿"这一块的 7/16 处,比这一块的正中高一点。
    /// **她 2026-11-23 19:14 在手机上定的(三种里的 A:"我觉得 A 挺好的")。不要再动,除非她说要重开。**
    /// 怎么走到这里的:她 17:37 问"怎么帖子比较靠上而不是居中?是我的错觉吗"。不是错觉:原来的写法是
    /// `.frame(minHeight: 屏幕高 - 230, alignment: .center)`,在"屏幕顶到离底 230"这一段里居中,
    /// 把状态栏和标签那一排也算了进去,中线落在那一块的 38% 处,比正中高约 85pt。
    /// 给了她三种:原来的 / A 往下挪一半(就是现在这个)/ B 那一块的正中。我建议的是 B,她选了 A。
    /// 长帖子从标签栏下面开始,不再钻到它底下。
    /// 返回:帖子上面留多少,帖子在多高的一段里居中。
    private func placement(pageHeight: CGFloat) -> (top: CGFloat, height: CGFloat) {
        let bar = Self.topBarHeight
        let free = max(0, pageHeight - Self.actionRowHeight - bar)
        return (bar, free * 0.875)
    }
    @State private var showReport = false
    @State private var showBlockConfirm = false
    @State private var selectedImageURL: String? = nil
    @State private var optimisticLiked: Bool? = nil
    @State private var showBurstHeart = false

    private var liked: Bool { optimisticLiked ?? post.likedBy.contains(uid) }
    private var displayCount: Int {
        guard let optimistic = optimisticLiked else { return post.likeCount }
        let serverLiked = post.likedBy.contains(uid)
        guard optimistic != serverLiked else { return post.likeCount }
        return max(0, post.likeCount + (optimistic ? 1 : -1))
    }

    var body: some View {
        GeometryReader { geo in
            ZStack {
                VStack(spacing: 0) {
                    ScrollView(.vertical, showsIndicators: false) {
                        VStack(alignment: .leading, spacing: 14) {
                            // 顺序:标签 → 标题 → 正文。不显示还剩多久。
                            if !post.tags.filter(\.isEmojiOnly).isEmpty {
                                ScrollView(.horizontal, showsIndicators: false) {
                                    HStack(spacing: 6) {
                                        ForEach(post.tags.filter(\.isEmojiOnly), id: \.self) { tag in
                                            Text(tag)
                                                .font(.system(size: 15))
                                                .padding(.horizontal, 10)
                                                .frame(height: 30)
                                                .background(Capsule().fill(Color.white.opacity(0.85)))
                                                .overlay(Capsule().stroke(Theme.outline, lineWidth: 1))
                                        }
                                    }
                                    .padding(.vertical, 1)
                                }
                            }

                            // 中等粗细:她 2026-11-23 17:37 在手机上定的(四种里的 B)。原来是细体,
                            // 苹果的规范建议不用细体。聊天页点开原帖那一张(SourcePostSheet)的标题和这里是同一种。
                            // 字号:标题 28,正文 17,所有帖子一样。定了(她 2026-11-23 23:05)。
                            // 试过、她没要的(不要再提):很短的帖子用大一号的字(只有一句标题的 → 34;
                            // 正文很短的 → 20)。她的话:"不管 A 还是 B 都太大了…保持现在是最好的。"
                            Text(post.title)
                                .font(Theme.ui(28, .medium))
                                .foregroundColor(Theme.ink)

                            if !post.bodyText.isEmpty {
                                Text(post.bodyText)
                                    .font(Theme.ui(17))
                                    .foregroundColor(Theme.ink2)
                                    .lineSpacing(7)
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
                        // 放多高:见上面的 placement
                        .frame(minHeight: placement(pageHeight: geo.size.height).height, alignment: .center)
                        .padding(.top, placement(pageHeight: geo.size.height).top)
                    }

                    // 这一排的间距(12 和 14)是她 2026-11-23 在手机上看着定下来的样子,不要挪。
                    // 14 比"图标和数字之间"的 12 大一点:数字跟着自己的图标走,不是跟着旁边的按钮走(邻近)
                    HStack(spacing: 14) {
                        Button {
                            let currentLiked = liked
                            optimisticLiked = !currentLiked
                            onToggleLike(post, currentLiked)
                            if !currentLiked {
                                popLikeButton()
                            }
                        } label: {
                            // "here"(我在):logo 里两个牵手的小人,金色。没点是一个人 + 一个空位,点了两个人都亮。
                            // 她 2026-11-23 定的,来龙去脉见 HereIcon。
                            // 底栏中间的爱心是发帖,这里不再用爱心,免得一个图标两个意思。
                            HStack(spacing: 12) {
                                HereIcon(on: liked)
                                    .scaleEffect(likeScale)
                                Text("\(displayCount) here")
                                    .font(Theme.ui(15, .medium))
                                    .monospacedDigit()
                                    .foregroundColor(Theme.ink2)
                            }
                            .frame(height: 44)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(Text(verbatim: liked ? "You are here. \(displayCount) here" : "I am here. \(displayCount) here"))

                        // Chat button — hidden on own posts
                        if post.authorUID != uid {
                            Button {
                                onStartChat(post)
                            } label: {
                                // 私聊是这一页最想让人做的事,所以它是这一页唯一一个实心的按钮
                                // (HIG:最可能做的那个动作用实心的样式;一屏一到两个)。
                                // 实心的金色 + 深棕的字:她 2026-11-23 17:08 在手机上选的("B1" 里的 1;
                                // 另一种是实心的深棕,没选,删了)。金色有多深还在和她定,见上面的 chatGold。
                                // 走到这里之前(都是她在真机上说的,2026-11-23):
                                // - 85% 的白:"为什么是纯白色…跟背景一点都连不上"。
                                // - 40% 的白 + 一圈淡线:"颜色是更统一了…但我们一定要引导他点击私聊…
                                //   让人有去点击、去互动的欲望"。太安静了。
                                HStack(spacing: 8) {
                                    Image(systemName: "bubble.left")
                                        .font(.system(size: 15, weight: .medium))
                                    Text("Chat privately")
                                        .font(Theme.ui(15, .semibold))
                                }
                                .foregroundColor(Theme.ink)
                                .padding(.horizontal, 18)
                                .frame(height: 44)
                                .background(Capsule().fill(chatGold))
                            }
                            .buttonStyle(.plain)
                        }

                        Spacer()

                        Menu {
                            Button(role: .destructive) {
                                showReport = true
                            } label: {
                                Label("Report Post", systemImage: "flag")
                            }
                            if post.authorUID != uid {
                                Button(role: .destructive) {
                                    showBlockConfirm = true
                                } label: {
                                    Label("Block her", systemImage: "hand.raised")
                                }
                            }
                        } label: {
                            Image(systemName: "ellipsis")
                                .font(.system(size: 18, weight: .regular))
                                .foregroundColor(Theme.ink3)
                                .frame(width: 44, height: 44)
                                .contentShape(Rectangle())
                        }
                    }
                    .padding(.leading, 24)
                    .padding(.trailing, 14)
                    .padding(.top, 20)
                    // Keeps the action row above the floating glass tab bar
                    // 底栏顶边离屏幕底 77pt(21 + 56),再留 16pt 间距
                    .padding(.bottom, 93)
                }

                if showBurstHeart {
                    // 双击 = "我在":logo 放大出现一下(和下面的 here 是同一张图,没有描边)
                    HereLogo(width: 112)
                        .shadow(color: Theme.ink.opacity(0.12), radius: 12, y: 4)
                        .transition(.scale(scale: 0.4).combined(with: .opacity))
                        .allowsHitTesting(false)
                }
            }
            // Buttons and image tiles consume their own taps, so this only fires
            // on the post's background/text — double-tap there likes (never unlikes)
            .onTapGesture(count: 2) { doubleTapLike() }
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
        .alert("Block her?", isPresented: $showBlockConfirm) {
            Button("Block", role: .destructive) { onBlockUser(post) }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("You won't see her posts or messages anymore. She won't be notified.")
        }
        .sheet(isPresented: $showReport) {
            ReportSheet(
                title: "Why are you reporting this post?",
                message: "Your report is anonymous, and you won't see this post again."
            ) { reasons, details in
                onReportPost(post, reasons, details)
            }
        }
    }

    // MARK: Like helpers

    private func popLikeButton() {
        UIImpactFeedbackGenerator(style: .soft).impactOccurred()
        withAnimation(.spring(response: 0.3, dampingFraction: 0.4)) {
            likeScale = 1.4
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
                likeScale = 1.0
            }
        }
    }

    private func doubleTapLike() {
        // Like-only: double-tapping an already-liked post just replays the burst
        if !liked {
            optimisticLiked = true
            onToggleLike(post, false)
            popLikeButton()
        }
        withAnimation(.spring(response: 0.3, dampingFraction: 0.55)) {
            showBurstHeart = true
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.55) {
            withAnimation(.easeOut(duration: 0.25)) {
                showBurstHeart = false
            }
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
                                // Placeholders are a tint of the ink, not a neutral grey
                                Theme.ink.opacity(0.06)
                                    .frame(width: 160, height: 160)
                                    .clipShape(RoundedRectangle(cornerRadius: 16))
                                    .overlay(
                                        Image(systemName: "photo")
                                            .font(.system(size: 40, weight: .light))
                                            .foregroundColor(Theme.tabOff)
                                    )
                            case .loading:
                                Theme.ink.opacity(0.06)
                                    .frame(width: 160, height: 160)
                                    .clipShape(RoundedRectangle(cornerRadius: 16))
                                    .overlay(ProgressView().tint(Theme.tabOff))
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
    /// 已经在手机里的图(聊天里的照片)。有它就直接看这张,不去网上取。
    var localImage: UIImage? = nil
    let onDismiss: () -> Void

    private static let minScale: CGFloat = 1
    private static let maxScale: CGFloat = 4
    private static let doubleTapScale: CGFloat = 2.5

    @State private var scale: CGFloat = 1
    @State private var lastScale: CGFloat = 1
    @State private var offset: CGSize = .zero
    @State private var lastOffset: CGSize = .zero

    var body: some View {
        ZStack {
            // Behind a full-screen photo: the darkest brown of the palette, not black
            Theme.photoBackdrop.ignoresSafeArea()

            if let localImage {
                zoomable(Image(uiImage: localImage))
            } else if let url = URL(string: imageURL) {
                // 2048px so the image stays sharp when zoomed in
                RemoteImageView(url: url, maxPixelSize: 2048) { phase in
                    switch phase {
                    case .success(let image):
                        zoomable(image)
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

    /// The picture itself: fits the screen, pinch to zoom, drag to pan, double-tap to zoom.
    private func zoomable(_ image: Image) -> some View {
        GeometryReader { geo in
            image
                .resizable()
                .scaledToFit()
                .frame(width: geo.size.width, height: geo.size.height)
                .scaleEffect(scale)
                .offset(offset)
                .gesture(zoomAndPan(in: geo.size))
                .onTapGesture(count: 2) { toggleZoom() }
        }
    }

    // MARK: Zoom gestures

    private func zoomAndPan(in viewport: CGSize) -> some Gesture {
        let pinch = MagnificationGesture()
            .onChanged { value in
                scale = min(max(lastScale * value, 0.7), Self.maxScale)
            }
            .onEnded { _ in
                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                    if scale < Self.minScale {
                        scale = Self.minScale
                        offset = .zero
                    }
                    offset = clampedOffset(offset, in: viewport)
                }
                lastScale = scale
                lastOffset = offset
            }

        let pan = DragGesture()
            .onChanged { value in
                if scale > Self.minScale {
                    offset = CGSize(
                        width: lastOffset.width + value.translation.width,
                        height: lastOffset.height + value.translation.height
                    )
                } else {
                    // At 1x, follow downward drags so a swipe down can close the viewer
                    offset = CGSize(width: 0, height: max(0, value.translation.height))
                }
            }
            .onEnded { value in
                if scale > Self.minScale {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                        offset = clampedOffset(offset, in: viewport)
                    }
                    lastOffset = clampedOffset(offset, in: viewport)
                } else {
                    // Dismiss on a decent pull or a quick flick; otherwise settle back
                    if value.translation.height > 120 || value.predictedEndTranslation.height > 250 {
                        onDismiss()
                    } else {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                            offset = .zero
                        }
                        lastOffset = .zero
                    }
                }
            }

        return pinch.simultaneously(with: pan)
    }

    private func toggleZoom() {
        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
            if scale > Self.minScale {
                scale = Self.minScale
                offset = .zero
            } else {
                scale = Self.doubleTapScale
            }
        }
        lastScale = scale
        lastOffset = offset
    }

    /// Keeps the zoomed image from being dragged fully offscreen.
    private func clampedOffset(_ proposed: CGSize, in viewport: CGSize) -> CGSize {
        let maxX = max(0, (viewport.width * scale - viewport.width) / 2)
        let maxY = max(0, (viewport.height * scale - viewport.height) / 2)
        return CGSize(
            width: min(max(proposed.width, -maxX), maxX),
            height: min(max(proposed.height, -maxY), maxY)
        )
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
        onToggleLike: { _, _ in },
        onReportPost: { _, _, _ in },
        onBlockUser: { _ in }
    )
}
