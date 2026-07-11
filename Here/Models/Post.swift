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
    var tags: [String]

    init(
        id: String? = nil,
        title: String,
        bodyText: String = "",
        imageURLs: [String] = [],
        authorUID: String,
        createdAt: Date = Date(),
        likeCount: Int = 0,
        tags: [String] = []
    ) {
        self.id = id
        self.title = title
        self.bodyText = bodyText
        self.imageURLs = imageURLs
        self.authorUID = authorUID
        self.createdAt = createdAt
        self.expiresAt = createdAt.addingTimeInterval(48 * 60 * 60)
        self.likeCount = likeCount
        self.tags = tags
    }

    // Posts written before tags existed have no "tags" field in Firestore
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        _id = try container.decode(DocumentID<String>.self, forKey: .id)
        title = try container.decode(String.self, forKey: .title)
        bodyText = try container.decode(String.self, forKey: .bodyText)
        imageURLs = try container.decode([String].self, forKey: .imageURLs)
        authorUID = try container.decode(String.self, forKey: .authorUID)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        expiresAt = try container.decode(Date.self, forKey: .expiresAt)
        likeCount = try container.decode(Int.self, forKey: .likeCount)
        tags = try container.decodeIfPresent([String].self, forKey: .tags) ?? []
    }
    /// A post is valid if it has a title and at least some description content (text or images)
//    var hasContent: Bool {
//        !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
//            && (!bodyText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !images.isEmpty)
//    }
}
