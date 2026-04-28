//
//  CreatePostView.swift
//  Here
//
//  Created by yuchen on 1/27/26.
//
import SwiftUI
import PhotosUI

// MARK: - Palette (mirrors ProfileView / FeedView)

private let cpGoldColors: [Color] = [
    Color(hex: "#F8EFD6"),
    Color(hex: "#F2DFAF"),
    Color(hex: "#E8C97A")
]
private let cpGoldAccent   = Color(hex: "#E6C35C")
private let cpBrownText    = Color(hex: "#5C3A1E")
private let cpMutedGold    = Color(hex: "#D8C898")
private let cpWarmBG       = Color(hex: "#FAF8F4")
private let cpGoldGradient = LinearGradient(
    colors: cpGoldColors,
    startPoint: .topLeading,
    endPoint: .bottomTrailing
)

// MARK: - CreatePostView

struct CreatePostView: View {
    @Environment(\.dismiss) private var dismiss
    let onSubmit: (String, String, [UIImage], [String], Bool) async -> Void     

    @State private var title = ""
    @State private var bodyText = ""
    @State private var selectedItems: [PhotosPickerItem] = []
    @State private var images: [UIImage] = []
    @State private var isUploading = false
    @State private var selectedTags: [String] = []
    @State private var customTagInput = ""
    @State private var onlyForMe = false

    // warm/positive tags first, heavier ones further back
    private let presetTags = [
        "happy", "grateful", "excited", "proud",
        "hopeful", "lonely", "anxious", "confused",
        "sad", "vent", "advice"
    ]

    private var isValid: Bool {
        let t = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let b = bodyText.trimmingCharacters(in: .whitespacesAndNewlines)
        return !t.isEmpty && !b.isEmpty
    }

    var body: some View {
        ZStack {
            cpWarmBG.ignoresSafeArea()

            VStack(spacing: 0) {

                // ── Nav bar ─────────────────────────────────────────────
                HStack {
                    Button { dismiss() } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 16, weight: .light))
                            .foregroundColor(cpBrownText.opacity(0.4))
                            .frame(width: 40, height: 40)
                    }
                    .buttonStyle(.plain)

                    Spacer()

                    if isUploading {
                        ProgressView().tint(cpGoldAccent)
                    } else {
                        Button {
                            Task { await submitPost() }
                        } label: {
                            Text(onlyForMe ? "Save" : "Share")
                                .font(.system(size: 15, weight: .medium))
                                .foregroundColor(isValid ? .white : cpMutedGold)
                                .padding(.horizontal, 22)
                                .padding(.vertical, 10)
                                .background {
                                    if isValid {
                                        Capsule().fill(cpGoldGradient)
                                    } else {
                                        Capsule()
                                            .fill(Color.clear)
                                            .overlay(Capsule().strokeBorder(cpMutedGold.opacity(0.4), lineWidth: 1))
                                    }
                                }
                        }
                        .disabled(!isValid)
                        .buttonStyle(.plain)
                        .animation(.easeInOut(duration: 0.15), value: isValid)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 16)
                .padding(.bottom, 20)

                // ── Scrollable content ───────────────────────────────────
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 14) {

                        // Prompt
                        Text("dear stranger bestie,")
                            .font(.system(size: 28, weight: .thin))
                            .foregroundColor(cpBrownText)
                            .padding(.horizontal, 26)
                            .padding(.bottom, 6)

                        // ── Title card ───────────────────────────────────
                        VStack(alignment: .leading, spacing: 10) {
                            Text("TITLE")
                                .font(.system(size: 11, weight: .medium))
                                .tracking(1.8)
                                .foregroundColor(cpMutedGold)

                            TextField("give it a name", text: $title)
                                .font(.system(size: 18, weight: .regular))
                                .foregroundColor(cpBrownText)
                                .tint(cpGoldAccent)
                        }
                        .padding(.horizontal, 22)
                        .padding(.vertical, 20)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(
                            RoundedRectangle(cornerRadius: 20, style: .continuous)
                                .fill(Color.white)
                                .shadow(color: cpGoldAccent.opacity(0.09), radius: 10, y: 3)
                        )
                        .padding(.horizontal, 24)

                        // ── Words card ───────────────────────────────────
                        VStack(alignment: .leading, spacing: 10) {
                            Text("WORDS")
                                .font(.system(size: 11, weight: .medium))
                                .tracking(1.8)
                                .foregroundColor(cpMutedGold)

                            ZStack(alignment: .topLeading) {
                                if bodyText.isEmpty {
                                    Text("write freely — as much or as little as you need")
                                        .font(.system(size: 16, weight: .light))
                                        .foregroundColor(cpMutedGold.opacity(0.65))
                                        .allowsHitTesting(false)
                                        .padding(.top, 8)
                                        .padding(.leading, 5)
                                }
                                TextEditor(text: $bodyText)
                                    .font(.system(size: 16, weight: .regular))
                                    .foregroundColor(cpBrownText)
                                    .tint(cpGoldAccent)
                                    .frame(minHeight: 150)
                                    .scrollContentBackground(.hidden)
                                    .background(Color.clear)
                            }
                        }
                        .padding(.horizontal, 22)
                        .padding(.vertical, 20)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(
                            RoundedRectangle(cornerRadius: 20, style: .continuous)
                                .fill(Color.white)
                                .shadow(color: cpGoldAccent.opacity(0.09), radius: 10, y: 3)
                        )
                        .padding(.horizontal, 24)

                        // ── Photos card (optional) ───────────────────────
                        VStack(alignment: .leading, spacing: 14) {
                            HStack(alignment: .center) {
                                Text("PHOTOS")
                                    .font(.system(size: 11, weight: .medium))
                                    .tracking(1.8)
                                    .foregroundColor(cpMutedGold)
                                OptionalBadge()
                                Spacer()
                                PhotosPicker(
                                    selection: $selectedItems,
                                    maxSelectionCount: 10,
                                    matching: .images
                                ) {
                                    Image(systemName: "photo.on.rectangle.angled")
                                        .font(.system(size: 22, weight: .light))
                                        .foregroundStyle(cpGoldGradient)
                                }
                                .buttonStyle(.plain)
                            }

                            if images.isEmpty {
                                Text("add moments that go with your words")
                                    .font(.system(size: 14, weight: .light))
                                    .foregroundColor(cpBrownText.opacity(0.35))
                            } else {
                                ScrollView(.horizontal, showsIndicators: false) {
                                    HStack(spacing: 10) {
                                        ForEach(images.indices, id: \.self) { idx in
                                            ZStack(alignment: .topTrailing) {
                                                Image(uiImage: images[idx])
                                                    .resizable()
                                                    .scaledToFill()
                                                    .frame(width: 90, height: 90)
                                                    .clipShape(RoundedRectangle(cornerRadius: 12))
                                                Button {
                                                    images.remove(at: idx)
                                                    selectedItems.remove(at: idx)
                                                } label: {
                                                    Image(systemName: "xmark.circle.fill")
                                                        .foregroundStyle(Color.white, Color.black.opacity(0.5))
                                                        .font(.system(size: 18))
                                                }
                                                .offset(x: 6, y: -6)
                                            }
                                        }
                                    }
                                }
                            }
                        }
                        .padding(.horizontal, 22)
                        .padding(.vertical, 20)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(
                            RoundedRectangle(cornerRadius: 20, style: .continuous)
                                .fill(Color.white)
                                .shadow(color: cpGoldAccent.opacity(0.09), radius: 10, y: 3)
                        )
                        .padding(.horizontal, 24)

                        // ── Tags card (optional) ─────────────────────────
                        VStack(alignment: .leading, spacing: 14) {
                            HStack {
                                Text("TAGS")
                                    .font(.system(size: 11, weight: .medium))
                                    .tracking(1.8)
                                    .foregroundColor(cpMutedGold)
                                OptionalBadge()
                            }

                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 8) {
                                    ForEach(presetTags, id: \.self) { tag in
                                        let on = selectedTags.contains(tag)
                                        Button { toggleTag(tag) } label: {
                                            Text("#\(tag)")
                                                .font(.system(size: 13, weight: .medium))
                                                .foregroundStyle(on ? Color.white : cpGoldAccent)
                                                .padding(.horizontal, 13)
                                                .padding(.vertical, 7)
                                                .background {
                                                    if on {
                                                        Capsule().fill(cpGoldGradient)
                                                    } else {
                                                        Capsule().fill(Color.white)
                                                            .overlay(Capsule().strokeBorder(cpGoldAccent, lineWidth: 1))
                                                    }
                                                }
                                        }
                                        .buttonStyle(.plain)
                                        .animation(.easeInOut(duration: 0.12), value: on)
                                    }
                                }
                                .padding(.vertical, 2)
                            }

                            HStack(spacing: 10) {
                                Image(systemName: "plus.circle")
                                    .foregroundStyle(cpGoldAccent)
                                    .font(.system(size: 16))
                                TextField("add your own tag", text: $customTagInput)
                                    .font(.system(size: 15))
                                    .foregroundColor(cpBrownText)
                                    .tint(cpGoldAccent)
                                    .autocorrectionDisabled()
                                    .textInputAutocapitalization(.never)
                                    .onSubmit { addCustomTag() }
                                if !customTagInput.trimmingCharacters(in: .whitespaces).isEmpty {
                                    Button("Add") { addCustomTag() }
                                        .font(.system(size: 14))
                                        .foregroundStyle(cpGoldAccent)
                                }
                            }

                            if !selectedTags.isEmpty {
                                ScrollView(.horizontal, showsIndicators: false) {
                                    HStack(spacing: 6) {
                                        ForEach(selectedTags, id: \.self) { tag in
                                            HStack(spacing: 4) {
                                                Text("#\(tag)")
                                                    .font(.system(size: 13, weight: .medium))
                                                Button {
                                                    selectedTags.removeAll { $0 == tag }
                                                } label: {
                                                    Image(systemName: "xmark")
                                                        .font(.system(size: 10, weight: .bold))
                                                }
                                            }
                                            .foregroundStyle(Color(hex: "#8A7A55"))
                                            .padding(.horizontal, 11)
                                            .padding(.vertical, 6)
                                            .background(Color(hex: "#F8EFD6"))
                                            .clipShape(Capsule())
                                        }
                                    }
                                }
                            }
                        }
                        .padding(.horizontal, 22)
                        .padding(.vertical, 20)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(
                            RoundedRectangle(cornerRadius: 20, style: .continuous)
                                .fill(Color.white)
                                .shadow(color: cpGoldAccent.opacity(0.09), radius: 10, y: 3)
                        )
                        .padding(.horizontal, 24)

                        // ── Just for me toggle ───────────────────────────
                        HStack(spacing: 14) {
                            Image(systemName: onlyForMe ? "lock.fill" : "lock")
                                .font(.system(size: 17, weight: .light))
                                .foregroundStyle(cpGoldGradient)
                                .frame(width: 24)
                                .animation(.easeInOut(duration: 0.15), value: onlyForMe)

                            VStack(alignment: .leading, spacing: 4) {
                                Text("just for me")
                                    .font(.system(size: 15, weight: .regular))
                                    .foregroundColor(cpBrownText)
                                Text(onlyForMe ? "only you will see this" : "share with everyone here")
                                    .font(.system(size: 13, weight: .light))
                                    .foregroundColor(cpMutedGold)
                                    .animation(.easeInOut(duration: 0.15), value: onlyForMe)
                            }

                            Spacer()

                            Toggle("", isOn: $onlyForMe)
                                .tint(cpGoldAccent)
                                .labelsHidden()
                                .scaleEffect(0.9)
                        }
                        .padding(.horizontal, 22)
                        .padding(.vertical, 18)
                        .background(
                            RoundedRectangle(cornerRadius: 20, style: .continuous)
                                .fill(Color.white)
                                .shadow(color: cpGoldAccent.opacity(0.09), radius: 10, y: 3)
                        )
                        .padding(.horizontal, 24)

                        // ── Footer note ──────────────────────────────────
                        Text(onlyForMe
                            ? "this stays safe with you — no one else will ever see it"
                            : "this post will automatically be archived after 48 hours"
                        )
                        .font(.system(size: 13, weight: .light))
                        .foregroundColor(cpMutedGold.opacity(0.85))
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.horizontal, 24)
                        .padding(.top, 4)
                        .animation(.easeInOut(duration: 0.2), value: onlyForMe)

                        Spacer(minLength: 40)
                    }
                    .padding(.top, 4)
                }
            }
        }
        .onChange(of: selectedItems) {
            Task {
                images = []
                for item in selectedItems {
                    if let data = try? await item.loadTransferable(type: Data.self),
                       let uiImage = UIImage(data: data) {
                        images.append(uiImage)
                    }
                }
            }
        }
    }

    private func submitPost() async {
        isUploading = true
        await onSubmit( // title, bodyText, images, tags, isPrivate
            title.trimmingCharacters(in: .whitespacesAndNewlines),
            bodyText.trimmingCharacters(in: .whitespacesAndNewlines),
            images,
            selectedTags,
            onlyForMe
        )
        isUploading = false
        dismiss()
    }

    private func toggleTag(_ tag: String) {
        if selectedTags.contains(tag) {
            selectedTags.removeAll { $0 == tag }
        } else {
            selectedTags.append(tag)
        }
    }

    private func addCustomTag() {
        let tag = customTagInput
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: "#", with: "")
            .replacingOccurrences(of: " ", with: "")
        customTagInput = ""
        guard !tag.isEmpty, !selectedTags.contains(tag) else { return }
        selectedTags.append(tag)
    }
}

// MARK: - Optional Badge

private struct OptionalBadge: View {
    var body: some View {
        Text("optional")
            .font(.system(size: 11, weight: .medium))
            .tracking(0.3)
            .foregroundColor(cpGoldAccent)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(Capsule().fill(cpGoldAccent.opacity(0.12)))
    }
}

// MARK: - Preview

#Preview {
    CreatePostView(onSubmit: { _, _, _ in })
}
