//
//  StorageService.swift
//  Here
//
//  Created by Aaron Lee on 2/28/26.
//


import FirebaseStorage
import UIKit

struct StorageService {
    private static let storage = Storage.storage()

    /// Uploads an array of UIImages and returns their download URLs
    static func uploadImages(_ images: [UIImage], path: String) async throws -> [String] {
        var urls: [String] = []

        for (index, image) in images.enumerated() {
            guard let data = image.jpegData(compressionQuality: 0.7) else { continue }

            let ref = storage.reference().child("\(path)/\(index)_\(UUID().uuidString).jpg")
            // putData does not infer a content type from the object name, and
            // storage.rules only accepts image/* — without this the upload is
            // rejected and the whole post silently fails (issue #2).
            let metadata = StorageMetadata()
            metadata.contentType = "image/jpeg"
            _ = try await ref.putDataAsync(data, metadata: metadata)
            let url = try await ref.downloadURL()
            urls.append(url.absoluteString)
        }

        return urls
    }

    /// Deletes every photo under posts/{uid}/ (one folder per post).
    static func deleteAllImages(forUser uid: String) async {
        let root = storage.reference().child("posts/\(uid)")
        guard let folders = try? await root.listAll() else { return }
        for item in folders.items { try? await item.delete() }
        for folder in folders.prefixes {
            guard let files = try? await folder.listAll() else { continue }
            for item in files.items { try? await item.delete() }
        }
    }
}
