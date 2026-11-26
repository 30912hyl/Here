//
//  CreatePostView.swift
//  Here
//
//  Created by yuchen on 1/27/26.
//
import SwiftUI
import PhotosUI

// MARK: - CreatePostView
// 一张信纸。从上到下：
//   ✕ / Send（能发的时候是实心深棕：发帖是这一页最想让人做的事，和别处的主按钮同一个做法）
//   dear bestie,（app 自己的口吻：名字的字体。原来是 "dear stranger bestie,"，
//     她 2026-11-25 22:45 说 “stranger 去掉吧”——苹果审核看的也包括 app 里的字，stranger 这个词不留）
//   Tags（至少选一个）
//   白色的信纸：标题、正文、照片（可选）
//   Who can read it：Everyone here / Just for me
// 背景是纸与光，不动。按钮是白底加一圈棕色的线；选中的标签是最淡的金色底加一圈棕色的线。

struct CreatePostView: View {
    @Environment(\.dismiss) private var dismiss
    /// Returns false when the post couldn't be saved; the composer then stays
    /// open with everything the user wrote, instead of silently losing it.
    let onSubmit: (String, String, [UIImage], [String], Bool) async -> Bool

    @State private var title = ""
    @State private var bodyText = ""
    @State private var selectedItems: [PhotosPickerItem] = []
    @State private var images: [UIImage] = []
    /// The picker item each entry of `images` came from (same order), so ✕
    /// removes the right one even when some photo failed to load.
    @State private var imageItems: [PhotosPickerItem] = []
    @State private var imageLoadTask: Task<Void, Never>?
    @State private var isUploading = false
    @State private var tags: [String] = []
    @State private var tagInput = ""
    @State private var showTagField = false
    @State private var onlyForMe = false
    @State private var filterMessage: String?
    @State private var postFailed = false
    @State private var confirmDiscard = false
    /// 还不能发的时候点了 Send：在按钮下面说还差什么（原来点了没有任何反应）
    @State private var showMissing = false
    @FocusState private var tagFieldFocused: Bool
    /// 标题和正文谁在输入。正文那一片点哪里都会把光标放进正文（见 sheet）。
    private enum Field { case title, body }
    @FocusState private var focus: Field?

    /// 正文空着时的那句提示。接着上面那句 "dear bestie," 的口气，全小写。
    /// 定了（老板 2026-11-25 23:37 自己想的：“我在想 here's the thing...”，23:38：“对”）。
    /// 走到这里之前：原来是 "Write freely, as much or as little as you need."（她：“我不喜欢这个 write freely”）；
    /// 我给过 What's on your mind? / Say what you can't say out loud. / Start anywhere. / How are you, really? /
    /// okay, so… / can i tell you something? / i've been wanting to say…，她都没要。
    private static let bodyPrompt = "here's the thing…"
    /// 正文至少这么高（约 13 行），写多了再往下长
    private static let bodyMinHeight: CGFloat = 312

    private let presetTags = ["😄", "😢", "🥰", "😡", "😴", "🍚", "☕️", "🎮", "🎵", "✨"]
    private let maxTags = 10

    /// A title, something to go with it (words or a photo), and at least one tag.
    private var isValid: Bool {
        let hasTitle = !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let hasText = !bodyText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let hasImages = !images.isEmpty
        return hasTitle && (hasText || hasImages) && !tags.isEmpty
    }

    /// 还差什么才能发（只说最上面的那一样）。nil = 可以发了。顺序跟着页面从上到下。英文是草稿。
    private var missing: String? {
        if tags.isEmpty { return "Pick at least one tag." }
        if title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return "Add a title." }
        if bodyText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && images.isEmpty {
            return "Write something, or add a photo."
        }
        return nil
    }

    /// Anything that would be lost by closing.
    private var hasAnything: Bool {
        !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || !bodyText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || !images.isEmpty
    }

    /// Tags the user added herself; they sit in front of the presets.
    private var customTags: [String] {
        tags.filter { !presetTags.contains($0) }
    }

    var body: some View {
        content
            .alert("Can't post this", isPresented: Binding(get: { filterMessage != nil },
                                                          set: { if !$0 { filterMessage = nil } })) {
                Button("OK", role: .cancel) { }
            } message: {
                Text(filterMessage ?? "")
            }
            .alert("Couldn't post", isPresented: $postFailed) {
                Button("OK", role: .cancel) { }
            } message: {
                Text("Your post wasn't saved. Please try again in a moment.")
            }
            // ✕ used to close at once and lose everything that was written.
            // (No destructive role on purpose: it would be the only red thing in the app.)
            .confirmationDialog("Discard this post?", isPresented: $confirmDiscard, titleVisibility: .visible) {
                Button("Discard") { dismiss() }
                Button("Keep writing", role: .cancel) { }
            }
            // A hardware keyboard's Esc must not throw the words away either
            .interactiveDismissDisabled(hasAnything)
    }

    private var content: some View {
        ZStack {
            PaperBackground()

            VStack(spacing: 0) {
                topBar

                ScrollView(.vertical, showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 0) {
                        greeting
                        tagPicker
                            .padding(.top, 14)
                        sheet
                            .padding(.top, 22)
                        audience
                            .padding(.top, 24)
                    }
                    .padding(.top, 12)
                    .padding(.bottom, 40)
                }
                .scrollDismissesKeyboard(.interactively)
            }
        }
        .onChange(of: selectedItems) {
            // One load at a time: a newer selection cancels the older load, so
            // two loads can't interleave and leave `images` out of step.
            imageLoadTask?.cancel()
            let items = selectedItems
            imageLoadTask = Task {
                var loaded: [(PhotosPickerItem, UIImage)] = []
                for item in items {
                    // Downsample at load: ten full-res 12MP picks would hold
                    // ~460MB of decoded bitmaps and get the app killed. 1600px
                    // is plenty for feed display and keeps uploads small.
                    if let data = try? await item.loadTransferable(type: Data.self),
                       let uiImage = UIImage.downsampled(data: data, maxPixelSize: 1600) {
                        loaded.append((item, uiImage))
                    }
                    if Task.isCancelled { return }
                }
                images = loaded.map { $0.1 }
                imageItems = loaded.map { $0.0 }
            }
        }
    }

    // MARK: ✕ / Send

    private var topBar: some View {
        HStack {
            Button {
                if hasAnything {
                    confirmDiscard = true
                } else {
                    dismiss()
                }
            } label: {
                // 和聊天页选图的那个圆按钮同一个画法：安静的白圆 + 一圈细线
                Image(systemName: "xmark")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundColor(Theme.ink2)
                    .frame(width: 44, height: 44)
                    .background(Circle().fill(Color.white.opacity(0.6)))
                    .overlay(Circle().strokeBorder(Theme.outline, lineWidth: 1))
                    .contentShape(Circle())
            }
            .buttonStyle(PressFade())
            .disabled(isUploading)
            .accessibilityLabel("Close")

            Spacer(minLength: 8)

            // 还差什么：就在刚点过的按钮左边，补上了就自己消失
            if showMissing, let missing, !isUploading {
                Text(missing)
                    .font(Theme.ui(13, .medium))
                    .foregroundColor(Theme.ink2)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
                    .padding(.trailing, 4)
                    .transition(.opacity)
            }

            if isUploading {
                ProgressView()
                    .tint(Theme.ink2)
                    .frame(width: 92, height: 44)
            } else {
                Button {
                    if isValid {
                        Task { await submitPost() }
                    } else {
                        withAnimation(.easeInOut(duration: 0.15)) { showMissing = true }
                    }
                } label: {
                    // 能发了：实心深棕 + 纸色的字——和小弹窗的主按钮（她选的 A）、聊天页的发送键同一个做法。
                    // 还不能发：安静的白底、淡字。它仍然点得动：点了会在它左边说还差什么。
                    Text(onlyForMe ? "Save" : "Send")
                        .font(Theme.ui(16, .semibold))
                        .foregroundColor(isValid ? Theme.paper : Theme.tabOff)
                        .frame(width: 92, height: 44)
                        .background(Capsule().fill(isValid ? Theme.ink : Color.white.opacity(0.6)))
                        .overlay(Capsule().strokeBorder(isValid ? Color.clear : Theme.outline, lineWidth: 1))
                        .contentShape(Capsule())
                }
                .buttonStyle(PressFade())
                .animation(.easeInOut(duration: 0.15), value: isValid)
                .accessibilityHint(Text(verbatim: missing ?? ""))
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 4)
        .onChange(of: isValid) { _, valid in
            if valid { showMissing = false }
        }
    }

    // MARK: dear bestie,

    private var greeting: some View {
        Text("dear bestie,")
            .font(Theme.brand(27))
            // The app's own voice. It is text, so it is brown like the rest of the text
            // (the softer brown: this face is heavy at this size). Gold stays with the logo.
            .foregroundStyle(Theme.ink2)
            // The typeface has a tall line box; take back the extra above and below
            .padding(.vertical, -7)
            .padding(.horizontal, 28)
            .accessibilityAddTraits(.isHeader)
    }

    // MARK: Tags

    private var tagPicker: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text("Tags")
                    .font(Theme.ui(15, .semibold))
                    .foregroundColor(Theme.ink)
                if tags.isEmpty {
                    Text("pick at least one")
                        .font(Theme.ui(13))
                        .foregroundColor(Theme.ink2)
                }
            }
            .padding(.horizontal, 28)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    // Add your own
                    Button {
                        withAnimation(.easeInOut(duration: 0.15)) { showTagField.toggle() }
                        tagFieldFocused = showTagField
                    } label: {
                        Image(systemName: showTagField ? "xmark" : "plus")
                            .font(.system(size: 15, weight: .medium))
                            .foregroundColor(Theme.ink2)
                            .frame(width: 44, height: 44)
                            .overlay(
                                Circle().strokeBorder(Theme.dash, style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
                            )
                            .contentShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Add your own emoji")

                    ForEach(customTags + presetTags, id: \.self) { emoji in
                        let on = tags.contains(emoji)
                        Button {
                            toggleTag(emoji)
                        } label: {
                            Text(emoji)
                                .font(.system(size: 21))
                                .padding(.horizontal, emoji.count > 1 ? 10 : 0)
                                .frame(minWidth: 44, minHeight: 44)
                                .background(Capsule().fill(on ? Theme.selectedFill : Color.white.opacity(0.9)))
                                .overlay(
                                    Capsule().strokeBorder(on ? Theme.line : Theme.outline, lineWidth: 1)
                                )
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Tag \(emoji)")
                        .accessibilityAddTraits(on ? .isSelected : [])
                        .animation(.easeInOut(duration: 0.12), value: on)
                    }
                }
                .padding(.horizontal, 28)
                .padding(.vertical, 1)
            }

            if showTagField {
                HStack(spacing: 10) {
                    TextField(
                        "",
                        text: $tagInput,
                        prompt: Text("emoji only, like 😄 or 🍚🥄").foregroundColor(Theme.tabOff)
                    )
                    .font(Theme.ui(15))
                    .foregroundColor(Theme.ink)
                    .focused($tagFieldFocused)
                    .onChange(of: tagInput) { _, newValue in
                        let filtered = newValue.emojiOnly
                        if filtered != newValue { tagInput = filtered }
                    }
                    .onSubmit { commitTagInput() }
                    .accessibilityLabel("Your own emoji tag")

                    if !tagInput.isEmpty {
                        Button("Add") { commitTagInput() }
                            .font(Theme.ui(14, .semibold))
                            .foregroundColor(Theme.ink)
                            .disabled(tags.count >= maxTags)
                    }
                }
                .padding(.horizontal, 16)
                .frame(height: 44)
                .background(Capsule().fill(Color.white.opacity(0.9)))
                .overlay(Capsule().stroke(Theme.outline, lineWidth: 1))
                .padding(.horizontal, 28)
                .transition(.opacity)
            }
        }
    }

    // MARK: The sheet of paper

    private var sheet: some View {
        VStack(alignment: .leading, spacing: 12) {
            // 标题用 medium：和 Feed 里帖子标题同一个粗细（她 2026-11-23 选的），写的时候看到的就是发出去的样子
            HStack(alignment: .center, spacing: 10) {
                TextField("", text: $title, prompt: Text("Title").foregroundColor(Theme.tabOff), axis: .vertical)
                    .font(Theme.ui(22, .medium))
                    .foregroundColor(Theme.ink)
                    .lineLimit(1...3)
                    .focused($focus, equals: .title)
                    .accessibilityLabel("Title")

                // 标题是必填的：空着的时候在右边提一句，填了就消失
                // （和 Tags 旁边那句 "pick at least one" 同一个做法。草稿：她 2026-11-25 23:18 问“title 旁边要不要写一个 required”，
                //   我建议写；她看了不喜欢就去掉。）
                if title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Text("required")
                        .font(Theme.ui(13))
                        .foregroundColor(Theme.ink2)
                }
            }
            .padding(.top, 2)
            .padding(.bottom, 12)
            .overlay(alignment: .bottom) {
                Rectangle().fill(Theme.hairline).frame(height: 1)
            }

            // 正文。和标题是同一种输入框（会自己长高的多行 TextField，不规定最少几行）——
            // 标题那一格在她手机上一直是好的。高度靠外面这一层撑到约 13 行，
            // 这一整片点哪里都会把光标放进正文。
            // 走到这里之前（都是她 2026-11-25 在 13 Pro Max 上发现的，两台模拟器上都重现不了）：
            // 1. 多行 TextField + “最少 13 行”（lineLimit(13...)）：点正文不弹键盘，点过标题以后也点不进正文。
            // 2. TextEditor + 跟着字数长高（fixedSize）：键盘出来了，但摁键没反应，卡很久。
            VStack(alignment: .leading, spacing: 0) {
                TextField(
                    "",
                    text: $bodyText,
                    prompt: Text(Self.bodyPrompt).foregroundColor(Theme.tabOff),
                    axis: .vertical
                )
                .font(Theme.ui(17))
                .foregroundColor(Theme.ink2)
                .lineSpacing(7)
                .focused($focus, equals: .body)
                .accessibilityLabel("Words")

                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, minHeight: Self.bodyMinHeight, alignment: .topLeading)
            .contentShape(Rectangle())
            .onTapGesture { focus = .body }

            photos
        }
        .padding(.horizontal, 20)
        .padding(.top, 20)
        .padding(.bottom, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .fill(Color.white)
                .shadow(color: Theme.ink.opacity(0.06), radius: 15, y: 10)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .stroke(Theme.ink.opacity(0.07), lineWidth: 1)
        )
        .padding(.horizontal, 16)
    }

    @ViewBuilder
    private var photos: some View {
        if images.isEmpty {
            PhotosPicker(selection: $selectedItems, maxSelectionCount: 10, matching: .images) {
                HStack(spacing: 8) {
                    Image(systemName: "photo")
                        .font(.system(size: 18, weight: .regular))
                        .foregroundColor(Theme.ink2)
                    Text("Add photos")
                        .font(Theme.ui(15, .semibold))
                        .foregroundColor(Theme.ink)
                    Text("optional")
                        .font(Theme.ui(13))
                        .foregroundColor(Theme.ink3)
                }
                .frame(height: 44)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        } else {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(images.indices, id: \.self) { idx in
                        ZStack(alignment: .topTrailing) {
                            Image(uiImage: images[idx])
                                .resizable()
                                .scaledToFill()
                                .frame(width: 56, height: 56)
                                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                            Button {
                                guard idx < images.count else { return }
                                let item = idx < imageItems.count ? imageItems[idx] : nil
                                images.remove(at: idx)
                                if idx < imageItems.count { imageItems.remove(at: idx) }
                                if let item { selectedItems.removeAll { $0 == item } }
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundStyle(Color.white, Theme.ink.opacity(0.55))
                                    .font(.system(size: 18))
                                    .frame(width: 28, height: 28)
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .offset(x: 10, y: -10)
                            .accessibilityLabel("Remove photo")
                        }
                    }

                    PhotosPicker(selection: $selectedItems, maxSelectionCount: 10, matching: .images) {
                        Image(systemName: "plus")
                            .font(.system(size: 15, weight: .medium))
                            .foregroundColor(Theme.ink2)
                            .frame(width: 56, height: 56)
                            .overlay(
                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .strokeBorder(Theme.dash, style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
                            )
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Add another photo")
                }
                // Room for the ✕ that sticks out of each photo's corner
                .padding(.top, 10)
                .padding(.trailing, 10)
            }
        }
    }

    // MARK: Who can read it

    private var audience: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Who can read it")
                .font(Theme.ui(15, .semibold))
                .foregroundColor(Theme.ink)
                .padding(.horizontal, 4)

            HStack(spacing: 4) {
                segment("Everyone here", selected: !onlyForMe) { onlyForMe = false }
                segment("Just for me", selected: onlyForMe) { onlyForMe = true }
            }
            .padding(4)
            .background(Capsule().fill(Theme.ink.opacity(0.06)))

            Text(onlyForMe ? "Only you will ever see this." : "Leaves the feed after 48 hours.")
                .font(Theme.ui(13))
                .foregroundColor(Theme.ink2)
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.top, 2)
        }
        .padding(.horizontal, 24)
    }

    private func segment(_ label: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button {
            withAnimation(.easeInOut(duration: 0.15)) { action() }
        } label: {
            Text(label)
                .font(Theme.ui(15, selected ? .semibold : .medium))
                .foregroundColor(selected ? Theme.ink : Theme.ink2)
                .frame(maxWidth: .infinity)
                .frame(height: 44)
                .background {
                    if selected {
                        Capsule()
                            .fill(Color.white)
                            .shadow(color: Theme.ink.opacity(0.12), radius: 2, y: 1)
                    }
                }
                .overlay {
                    if selected {
                        Capsule().stroke(Theme.outline, lineWidth: 1)
                    }
                }
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    // MARK: Actions

    private func submitPost() async {
        if case .blocked(let reason) = ContentFilter.check(.post, title, bodyText, tags.joined(separator: " ")) {
            filterMessage = reason
            return
        }
        isUploading = true
        let saved = await onSubmit(
            title.trimmingCharacters(in: .whitespacesAndNewlines),
            bodyText.trimmingCharacters(in: .whitespacesAndNewlines),
            images,
            tags,
            onlyForMe
        )
        isUploading = false
        if saved {
            dismiss()
        } else {
            postFailed = true
        }
    }

    private func commitTagInput() {
        addTag(tagInput)
        tagInput = ""
        withAnimation(.easeInOut(duration: 0.15)) { showTagField = false }
    }

    private func addTag(_ raw: String) {
        let tag = raw.emojiOnly
        guard !tag.isEmpty, !tags.contains(tag), tags.count < maxTags else { return }
        tags.append(tag)
    }

    private func toggleTag(_ emoji: String) {
        if let idx = tags.firstIndex(of: emoji) {
            tags.remove(at: idx)
        } else {
            addTag(emoji)
        }
    }
}

// MARK: - Preview

#Preview {
    CreatePostView(onSubmit: { _, _, _, _, _ in true })
}
