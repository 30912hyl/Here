import UIKit

struct Post: Identifiable {
    let id: UUID
    let title: String
    let bodyText: String
    let images: [UIImage]
    let createdAt: Date
    var likeCount: Int

    init(
        title: String,
        bodyText: String = "",
        images: [UIImage] = [],
        createdAt: Date = Date(),
        likeCount: Int = 0
    ) {
        self.id = UUID()
        self.title = title
        self.bodyText = bodyText
        self.images = images
        self.createdAt = createdAt
        self.likeCount = likeCount
    }

    var hasContent: Bool {
        !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && (!bodyText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !images.isEmpty)
    }
}
