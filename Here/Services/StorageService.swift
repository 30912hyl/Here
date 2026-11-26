//
//  StorageService.swift
//  Here
//
//  Created by Aaron Lee on 2/28/26.
//


import FirebaseStorage
import UIKit

struct StorageService {
    private static let storage: Storage = {
        let storage = Storage.storage()
        // Give up on an upload after 30s without a connection (default is
        // 10 minutes), so the composer reports it instead of spinning.
        storage.maxUploadRetryTime = 30
        return storage
    }()

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

    // MARK: - 聊天里的照片
    //
    // 存在 chats/{对话}/{发送人}/{名字}.jpg。消息里记的是这个路径,不是网址:
    // 只有对话里的两个人能取(storage.rules 每次都会去看这段对话是谁的)。

    /// 上传一张聊天照片,返回它在 Storage 里的路径(写进消息的 imagePath)。
    /// 名字是一个新的 UUID:同一个路径不能传第二次(传了就不能覆盖)。
    static func uploadChatPhoto(_ image: UIImage, threadId: String, uid: String) async throws -> String {
        guard let data = image.jpegData(compressionQuality: 0.7) else {
            throw NSError(domain: "StorageService", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "Could not read that photo."])
        }
        let path = "chats/\(threadId)/\(uid)/\(UUID().uuidString).jpg"
        let metadata = StorageMetadata()
        metadata.contentType = "image/jpeg"
        _ = try await storage.reference().child(path).putDataAsync(data, metadata: metadata)
        return path
    }

    /// 看过的聊天照片留在内存里,回到对话时不用再下载一遍。
    private static let chatPhotoCache: NSCache<NSString, UIImage> = {
        let cache = NSCache<NSString, UIImage>()
        cache.countLimit = 60
        return cache
    }()

    /// 自己刚发的那张:直接放进内存,不用等上传完再下载回来。
    static func rememberChatPhoto(_ image: UIImage, path: String) {
        chatPhotoCache.setObject(image, forKey: path as NSString)
    }

    /// 取一张聊天照片。取不到(对话结束后照片已经删了、没有网)就是 nil。
    static func chatPhoto(path: String) async -> UIImage? {
        if let cached = chatPhotoCache.object(forKey: path as NSString) { return cached }
        // 上传的上限是 10MB(storage.rules),这里留一点余量
        guard let data = try? await storage.reference().child(path).data(maxSize: 12 * 1024 * 1024),
              let image = UIImage(data: data) else { return nil }
        chatPhotoCache.setObject(image, forKey: path as NSString)
        return image
    }

    /// 消息没发出去时,把已经传上去的那张拿回来(只有发的人自己能删)。
    static func deleteChatPhoto(path: String) async {
        try? await storage.reference().child(path).delete()
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
