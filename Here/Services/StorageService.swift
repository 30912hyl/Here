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
            _ = try await ref.putDataAsync(data)
            let url = try await ref.downloadURL()
            urls.append(url.absoluteString)
        }

        return urls
    }
}




































