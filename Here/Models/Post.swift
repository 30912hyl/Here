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
    var isPrivate: Bool
    var likedBy: [String]

    init(
        id: String? = nil,
        title: String,
        bodyText: String = "",
        imageURLs: [String] = [],
        authorUID: String,
        createdAt: Date = Date(),
        likeCount: Int = 0,
        tags: [String] = [],
        isPrivate: Bool = false
        likedBy: [String] = []
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
        self.isPrivate = isPrivate
        self.likedBy = likedBy
    }
    // Custom Codable decoder so that Firestore documents created before the `tags`
    // field was added can still decode successfully (falls back to an empty array).
    // `id` is omitted from CodingKeys — Firestore injects @DocumentID automatically.
    enum CodingKeys: String, CodingKey {
        case title, bodyText, imageURLs, authorUID, createdAt, expiresAt, likeCount, tags, isPrivate
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        _id       = try c.decode(DocumentID<String>.self, forKey: .id)
        title     = try c.decode(String.self, forKey: .title)
        bodyText  = try c.decodeIfPresent(String.self, forKey: .bodyText) ?? ""
        imageURLs = try c.decodeIfPresent([String].self, forKey: .imageURLs) ?? []
        authorUID = try c.decode(String.self, forKey: .authorUID)
        createdAt = try c.decode(Date.self, forKey: .createdAt)
        expiresAt = try c.decode(Date.self, forKey: .expiresAt)
        likeCount = try c.decodeIfPresent(Int.self, forKey: .likeCount) ?? 0
        tags      = try c.decodeIfPresent([String].self, forKey: .tags) ?? []
        isPrivate = try c.decodeIfPresent(Bool.self, forKey: .isPrivate) ?? false
        likedBy   = try c.decodeIfPresent([String].self, forKey: .likedBy) ?? []
    }
}
