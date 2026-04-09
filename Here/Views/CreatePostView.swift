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
    @ObservedObject var app: AppState
    
    @State private var title = ""
    @State private var bodyText = ""
    @State private var selectedItems: [PhotosPickerItem] = []
    @State private var images: [UIImage] = []
    @State private var isUploading = false
    @State private var selectedTags: [String] = []
    @State private var customTagInput = ""

    private let presetTags = ["sad", "happy", "anxious", "grateful", "lonely", "excited", "vent", "advice", "confused", "proud"]

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
                
                // MARK: Tags
                Section {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(presetTags, id: \.self) { tag in
                                let on = selectedTags.contains(tag)
                                Button { toggleTag(tag) } label: {
                                    Text("#\(tag)")
                                        .font(.system(size: 13, weight: .medium))
                                        .foregroundStyle(on ? Color.white : Color(hex: "#E6C35C"))
                                        .padding(.horizontal, 12)
                                        .padding(.vertical, 6)
                                        .background {
                                            if on {
                                                Capsule().fill(LinearGradient(
                                                    colors: [Color(hex: "#F8EFD6"), Color(hex: "#F2DFAF"), Color(hex: "#E8C97A")],
                                                    startPoint: .topLeading, endPoint: .bottomTrailing
                                                ))
                                            } else {
                                                Capsule().fill(Color.white)
                                                    .overlay(Capsule().strokeBorder(Color(hex: "#E6C35C"), lineWidth: 1))
                                            }
                                        }
                                }
                                .buttonStyle(.plain)
                                .animation(.easeInOut(duration: 0.12), value: on)
                            }
                        }
                        .padding(.vertical, 4)
                    }

                    HStack(spacing: 8) {
                        Image(systemName: "plus.circle")
                            .foregroundStyle(Color(hex: "#E6C35C"))
                        TextField("Add your own tag", text: $customTagInput)
                            .font(.system(size: 14))
                            .autocorrectionDisabled()
                            .textInputAutocapitalization(.never)
                            .onSubmit { addCustomTag() }
                        if !customTagInput.trimmingCharacters(in: .whitespaces).isEmpty {
                            Button("Add") { addCustomTag() }
                                .font(.system(size: 13))
                                .foregroundStyle(Color(hex: "#E6C35C"))
                        }
                    }

                    if !selectedTags.isEmpty {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 6) {
                                ForEach(selectedTags, id: \.self) { tag in
                                    HStack(spacing: 4) {
                                        Text("#\(tag)")
                                            .font(.system(size: 12, weight: .medium))
                                        Button {
                                            selectedTags.removeAll { $0 == tag }
                                        } label: {
                                            Image(systemName: "xmark")
                                                .font(.system(size: 9, weight: .bold))
                                        }
                                    }
                                    .foregroundStyle(Color(hex: "#8A7A55"))
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 5)
                                    .background(Color(hex: "#F8EFD6"))
                                    .clipShape(Capsule())
                                }
                            }
                            .padding(.vertical, 2)
                        }
                    }
                } header: {
                    Text("Tags (optional)")
                } footer: {
                    Text("Tags help others find your post. Tap a preset or add your own.")
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

    private func submitPost() async {
        isUploading = true
        await app.addPost(
            title: title.trimmingCharacters(in: .whitespacesAndNewlines),
            bodyText: bodyText.trimmingCharacters(in: .whitespacesAndNewlines),
            images: images,
            tags: selectedTags
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

#Preview {
    CreatePostView(app: AppState(authService: AuthService()))
}
