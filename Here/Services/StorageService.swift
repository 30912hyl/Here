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
}
