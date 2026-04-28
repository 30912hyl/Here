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

struct ChatThread: Identifiable, Codable, Equatable {
    @DocumentID var id: String?
    let postId: String?
    let postTitle: String
    let participants: [String]       // [uid1, uid2]
    let createdAt: Date
    var expiresAt: Date
    var isManuallyFrozen: Bool
    var hasExtendedOnce: Bool
    var continueChoices: [String: String]  // [uid: "undecided"/"yes"/"no"]
    var nickname: String

    init(
        id: String? = nil,
        postId: String? = nil,
        postTitle: String,
        participants: [String],
        createdAt: Date = Date(),
        ttlSeconds: TimeInterval = 24 * 60 * 60,
        nickname: String = ChatThread.generateNickname()
    ) {
        self.id = id
        self.postId = postId
        self.postTitle = postTitle
        self.participants = participants
        self.createdAt = createdAt
        self.expiresAt = createdAt.addingTimeInterval(ttlSeconds)
        self.isManuallyFrozen = false
        self.hasExtendedOnce = false
        self.nickname = nickname
        var choices: [String: String] = [:]
        for uid in participants {
            choices[uid] = ContinueChoice.undecided.rawValue
        }
        self.continueChoices = choices
    }

    static func generateNickname() -> String {
        let adjectives = [
            "gentle", "quiet", "golden", "soft", "silver", "wandering",
            "tender", "warm", "still", "amber", "velvet", "calm",
            "bright", "wild", "dawn", "misty", "warm", "rosy", "early"
        ]
        let nouns = [
            "moon", "rain", "river", "spark", "echo", "bloom",
            "mist", "light", "cloud", "ember", "tide", "rose",
            "leaf", "song", "sky", "field", "flame", "shore"
        ]
        let adj  = adjectives.randomElement() ?? "quiet"
        let noun = nouns.randomElement()      ?? "moon"
        return "\(adj) \(noun)"
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

    // Custom decoder so old Firestore documents without `nickname` still decode.
    enum CodingKeys: String, CodingKey {
        case postTitle, participants, createdAt, expiresAt
        case isManuallyFrozen, hasExtendedOnce, continueChoices, nickname
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        postTitle        = try  c.decode(String.self,             forKey: .postTitle)
        participants     = try  c.decode([String].self,           forKey: .participants)
        createdAt        = try  c.decode(Date.self,               forKey: .createdAt)
        expiresAt        = try  c.decode(Date.self,               forKey: .expiresAt)
        isManuallyFrozen = (try? c.decode(Bool.self,             forKey: .isManuallyFrozen)) ?? false
        hasExtendedOnce  = (try? c.decode(Bool.self,             forKey: .hasExtendedOnce))  ?? false
        continueChoices  = (try? c.decode([String: String].self, forKey: .continueChoices))  ?? [:]
        nickname         = (try? c.decode(String.self,           forKey: .nickname))          ?? ChatThread.generateNickname()
    }
}




































