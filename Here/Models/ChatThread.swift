//
//  ChatThread.swift
//  Here
//
//  Created by Aaron Lee on 2/10/26.
//
import FirebaseFirestore
import Foundation

struct ChatMessage: Identifiable, Codable {
    @DocumentID var id: String?
    let text: String
    let senderUID: String
    let createdAt: Date

    init(id: String? = nil, text: String, senderUID: String, createdAt: Date = Date()) {
        self.id = id
        self.text = text
        self.senderUID = senderUID
        self.createdAt = createdAt
    }

    /// Helper to check if the current user sent this message
    func isMe(uid: String) -> Bool {
        senderUID == uid
    }
}

enum ContinueChoice: String, Codable {
    case undecided
    case yes
    case no
}

struct ChatThread: Identifiable, Codable {
    @DocumentID var id: String?
    let postTitle: String
    let participants: [String]       // [uid1, uid2]
    let createdAt: Date
    var expiresAt: Date
    var isManuallyFrozen: Bool
    var hasExtendedOnce: Bool
    var continueChoices: [String: String]  // [uid: "undecided"/"yes"/"no"]

    init(
        id: String? = nil,
        postTitle: String,
        participants: [String],
        createdAt: Date = Date(),
        ttlSeconds: TimeInterval = 24 * 60 * 60
    ) {
        self.id = id
        self.postTitle = postTitle
        self.participants = participants
        self.createdAt = createdAt
        self.expiresAt = createdAt.addingTimeInterval(ttlSeconds)
        self.isManuallyFrozen = false
        self.hasExtendedOnce = false
        // Both start undecided
        var choices: [String: String] = [:]
        for uid in participants {
            choices[uid] = ContinueChoice.undecided.rawValue
        }
        self.continueChoices = choices
    }
    
    func isExpired(now: Date = Date()) -> Bool {
        now >= expiresAt
    }

    func isFrozen(now: Date = Date()) -> Bool {
        isManuallyFrozen || isExpired(now: now)
    }

    func myContinueChoice(uid: String) -> ContinueChoice {
        ContinueChoice(rawValue: continueChoices[uid] ?? "undecided") ?? .undecided
    }

    func otherContinueChoice(uid: String) -> ContinueChoice {
        let otherUID = participants.first(where: { $0 != uid }) ?? ""
        return ContinueChoice(rawValue: continueChoices[otherUID] ?? "undecided") ?? .undecided
    }

    var bothSaidYes: Bool {
        continueChoices.values.allSatisfy { $0 == ContinueChoice.yes.rawValue }
    }
}




































