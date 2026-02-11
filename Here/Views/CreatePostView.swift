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
    @State private var title = ""
    @State private var bodyText = ""
    @State private var selectedItems: [PhotosPickerItem] = []
    @State private var images: [UIImage] = []

    let onPost: (Post) -> Void

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

                // MARK: Description text
                Section("Description") {
                    TextEditor(text: $bodyText)
                        .frame(minHeight: 120)
                }

                // MARK: Images
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
                    Text("This post will disappear from the feed after 24 hours.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("New Post")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Post") {
                        let post = Post(
                            title: title.trimmingCharacters(in: .whitespacesAndNewlines),
                            bodyText: bodyText.trimmingCharacters(in: .whitespacesAndNewlines),
                            images: images
                        )
                        onPost(post)
                        dismiss()
                    }
                    .disabled(!isValid)
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
}

#Preview {
    CreatePostView { _ in }
}
