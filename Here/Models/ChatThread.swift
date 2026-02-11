//
//  ChatThread.swift
//  Here
//
//  Created by Aaron Lee on 2/10/26.
//
import Foundation

struct ChatMessage: Identifiable {
    let id = UUID()
    let text: String
    let isMe: Bool
    let createdAt = Date()
}

enum ContinueChoice: String, Codable {
    case undecided
    case yes
    case no
}

struct ChatThread: Identifiable {
    let id: UUID
    let title: String
    var messages: [ChatMessage]

    // Manual freeze (for demo / admin)
    var isManuallyFrozen: Bool

    // Lifecycle
    let createdAt: Date
    var expiresAt: Date

    // Continue flow
    var hasExtendedOnce: Bool
    var myContinueChoice: ContinueChoice
    var otherContinueChoice: ContinueChoice

    init(
        title: String,
        messages: [ChatMessage] = [],
        createdAt: Date = Date(),
        ttlSeconds: TimeInterval,
        isManuallyFrozen: Bool = false
    ) {
        self.id = UUID()
        self.title = title
        self.messages = messages
        self.isManuallyFrozen = isManuallyFrozen
        self.createdAt = createdAt
        self.expiresAt = createdAt.addingTimeInterval(ttlSeconds)

        self.hasExtendedOnce = false
        self.myContinueChoice = .undecided
        self.otherContinueChoice = .undecided
    }
}

