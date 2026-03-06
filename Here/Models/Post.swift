//
//  Post.swift
//  Here
//
//  Created by Aaron Lee on 2/10/26.
//

import FirebaseFirestore
import Foundation

struct Post: Identifiable, Codable {
    @DocumentID var id: String?
    let title: String
    let bodyText: String
    let imageURLs: [String]
    let authorUID: String
    let createdAt: Date
    let expiresAt: Date
    var likeCount: Int

    init(
        id: String? = nil,
        title: String,
        bodyText: String = "",
        imageURLs: [String] = [],
        authorUID: String,
        createdAt: Date = Date(),
        likeCount: Int = 0
    ) {
        self.id = id
        self.title = title
        self.bodyText = bodyText
        self.imageURLs = imageURLs
        self.authorUID = authorUID
        self.createdAt = createdAt
        self.expiresAt = createdAt.addingTimeInterval(24 * 60 * 60)
        self.likeCount = likeCount
    }
    /// A post is valid if it has a title and at least some description content (text or images)
//    var hasContent: Bool {
//        !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
//            && (!bodyText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !images.isEmpty)
//    }
}
