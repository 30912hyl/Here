//
//  Post.swift
//  Here
//
//  Created by Aaron Lee on 2/10/26.
//

import UIKit

struct Post: Identifiable {
    let id: UUID
    let title: String
    let bodyText: String
    let images: [UIImage]
    let createdAt: Date

    init(
        title: String,
        bodyText: String = "",
        images: [UIImage] = [],
        createdAt: Date = Date()
    ) {
        self.id = UUID()
        self.title = title
        self.bodyText = bodyText
        self.images = images
        self.createdAt = createdAt
    }

    /// A post is valid if it has a title and at least some description content (text or images)
    var hasContent: Bool {
        !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && (!bodyText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !images.isEmpty)
    }
}
