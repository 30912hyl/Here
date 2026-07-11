//
//  CreatePostView.swift
//  Here
//
//  Created by yuchen on 1/27/26.
//
import SwiftUI
import PhotosUI

struct CreatePostView: View {
    @Environment(\.dismiss) private var dismiss
    let onSubmit: (String, String, [UIImage], [String]) async -> Void

    @State private var title = ""
    @State private var bodyText = ""
    @State private var selectedItems: [PhotosPickerItem] = []
    @State private var images: [UIImage] = []
    @State private var tags: [String] = []
    @State private var tagInput = ""
    @State private var isUploading = false

    private let presetTags = ["😄", "😢", "🥰", "😡", "😴", "🍚", "☕️", "🎮", "🎵", "✨"]
    private let maxTags = 10

    private var isValid: Bool {
        let hasTitle = !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let hasText = !bodyText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let hasImages = !images.isEmpty
        return hasTitle && (hasText || hasImages)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Title") {
                    TextField("Give your post a title", text: $title)
                }

                Section("Description") {
                    TextEditor(text: $bodyText)
                        .frame(minHeight: 120)
                }

                Section {
                    PhotosPicker(
                        selection: $selectedItems,
                        maxSelectionCount: 10,
                        matching: .images
                    ) {
                        Label("Add Photos", systemImage: "photo.on.rectangle.angled")
                    }

                    if !images.isEmpty {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 10) {
                                ForEach(images.indices, id: \.self) { idx in
                                    ZStack(alignment: .topTrailing) {
                                        Image(uiImage: images[idx])
                                            .resizable()
                                            .scaledToFill()
                                            .frame(width: 100, height: 100)
                                            .clipShape(RoundedRectangle(cornerRadius: 8))

                                        Button {
                                            images.remove(at: idx)
                                            selectedItems.remove(at: idx)
                                        } label: {
                                            Image(systemName: "xmark.circle.fill")
                                                .foregroundStyle(.white, .black.opacity(0.6))
                                        }
                                        .offset(x: 6, y: -6)
                                    }
                                }
                            }
                            .padding(.vertical, 4)
                        }
                    }
                } header: {
                    Text("Photos")
                } footer: {
                    Text("Add text, photos, or both. At least one is required along with a title.")
                }

                Section {
                    if !tags.isEmpty {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                ForEach(tags, id: \.self) { tag in
                                    HStack(spacing: 4) {
                                        Text("#\(tag)")
                                            .font(.system(size: 16))
                                        Button {
                                            tags.removeAll { $0 == tag }
                                        } label: {
                                            Image(systemName: "xmark.circle.fill")
                                                .font(.system(size: 13))
                                                .foregroundStyle(Color(hex: "#C9A84C").opacity(0.6))
                                        }
                                        .buttonStyle(.borderless)
                                    }
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 6)
                                    .background(Capsule().fill(Color(hex: "#F7E7CE").opacity(0.6)))
                                    .overlay(Capsule().stroke(Color(hex: "#E8CC7A"), lineWidth: 1))
                                }
                            }
                            .padding(.vertical, 2)
                        }
                    }

                    HStack {
                        TextField("😄👌 emoji only", text: $tagInput)
                            .onChange(of: tagInput) { _, newValue in
                                let filtered = newValue.emojiOnly
                                if filtered != newValue { tagInput = filtered }
                            }
                            .onSubmit { commitTagInput() }
                        Button("Add") { commitTagInput() }
                            .buttonStyle(.borderless)
                            .disabled(tagInput.isEmpty || tags.count >= maxTags)
                    }

                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 10) {
                            ForEach(presetTags, id: \.self) { emoji in
                                Button {
                                    toggleTag(emoji)
                                } label: {
                                    Text(emoji)
                                        .font(.system(size: 24))
                                        .padding(7)
                                        .background(
                                            Circle().fill(
                                                tags.contains(emoji)
                                                ? Color(hex: "#F2DFAF")
                                                : Color(.systemGray6)
                                            )
                                        )
                                        .overlay(
                                            Circle().stroke(
                                                tags.contains(emoji) ? Color(hex: "#C9A84C") : .clear,
                                                lineWidth: 1.5
                                            )
                                        )
                                }
                                .buttonStyle(.borderless)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                } header: {
                    Text("Tags")
                } footer: {
                    Text("Tags are emoji only (up to \(maxTags)) — a tag can be one emoji or a little string of them, like 😄 or 🍚🥄. They show on your post as #😄#🍚.")
                }

                Section {
                    Text("This post will disappear from the feed after 24 hours.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("New Post")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .disabled(isUploading)
                }
                ToolbarItem(placement: .confirmationAction) {
                    if isUploading {
                        ProgressView()
                    } else {
                        Button("Post") {
                            Task { await submitPost() }
                        }
                        .disabled(!isValid)
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
    }

    private func commitTagInput() {
        addTag(tagInput)
        tagInput = ""
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

    private func submitPost() async {
        isUploading = true
        await onSubmit(
            title.trimmingCharacters(in: .whitespacesAndNewlines),
            bodyText.trimmingCharacters(in: .whitespacesAndNewlines),
            images,
            tags
        )
        isUploading = false
        dismiss()
    }
}

#Preview {
    CreatePostView(onSubmit: { _, _, _, _ in })
}
