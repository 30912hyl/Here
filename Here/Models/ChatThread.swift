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
    /// 这条消息带的照片在 Storage 里的路径:chats/{对话}/{发送人}/{名字}.jpg。没有照片就是 nil(也就不会写进文档)。
    /// 只有对话里的两个人能取到这个文件(storage.rules)。
    let imagePath: String?
    /// 服务器检查过这张照片以后打的记号(functions/lib/handlers.js)。手机不能写它(firestore.rules)。
    /// 对方发来的照片只在它是 true 的时候才显示;自己发的不用等。
    let imageOK: Bool?
    /// 这张照片没通过检查:服务器把图删了、消息留着,打了这个记号(functions: checkChatPhoto)。手机不能写它。
    /// 两个人看到的是同一句话(她 2026-11-25 19:55 定的)。
    let imageRemoved: Bool?
    /// founder 的欢迎语:服务器在对话一创建时写进来的,不是谁打的字。手机不能写它。
    let auto: Bool?

    init(id: String? = nil, text: String, senderUID: String, createdAt: Date = Date(), imagePath: String? = nil) {
        self.id = id
        self.text = text
        self.senderUID = senderUID
        self.createdAt = createdAt
        self.imagePath = imagePath
        self.imageOK = nil
        self.imageRemoved = nil
        self.auto = nil
    }

    /// 这张照片现在能不能给 `uid` 看:没通过检查的谁也看不了;自己发的随时能看,对方发的要等服务器检查过。
    func photoIsViewable(by uid: String) -> Bool {
        imagePath != nil && imageRemoved != true && (senderUID == uid || imageOK == true)
    }

    /// 带照片的消息现在是哪一种样子(聊天页据此画:照片 / "Checking photo…" / "Photo didn't pass the check")。
    enum PhotoState { case none, viewable, checking, rejected }
    func photoState(for uid: String) -> PhotoState {
        guard imagePath != nil else { return .none }
        if imageRemoved == true { return .rejected }
        return photoIsViewable(by: uid) ? .viewable : .checking
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
    var lastRead: [String: Date]  // [uid: last time that user opened this thread]
    /// "founder" = 和 founder 的那一段对话:不是从帖子开始的,没有 48 小时。别的对话没有这个字段。
    let kind: String?
    /// Written by the server only (functions: onRetentionSweep), never by the app:
    /// the day this conversation is deleted for good, with its messages and photos.
    /// Only a conversation that is over has it. The chat page reads it to say
    /// "It disappears in N days." (Photos live exactly as long as their conversation.)
    var deleteAfter: Date?

    static let founderKind = "founder"
    /// "永不过期"写成的那个固定日期:2100-01-01 00:00:00 UTC。firestore.rules 认的就是这一个值。
    static let never = Date(timeIntervalSince1970: 4_102_444_800)

    var isFounder: Bool { kind == Self.founderKind }

    /// "system" = Here 自己跟她说话的那一段(举报"收到了""处理了")。服务器建的(functions: addSystemNotice),
    /// id 是 system_<她的 uid>,不会结束;手机不能建、不能往里写,只能标成已读(firestore.rules)。
    static let systemKind = "system"
    var isSystem: Bool { kind == Self.systemKind }

    init(
        id: String? = nil,
        postId: String? = nil,
        postTitle: String,
        participants: [String],
        createdAt: Date = Date(),
        ttlSeconds: TimeInterval = 48 * 60 * 60,
        nickname: String = ChatThread.generateNickname(),
        kind: String? = nil,
        expiresAt: Date? = nil
    ) {
        self.id = id
        self.postId = postId
        self.postTitle = postTitle
        self.participants = participants
        self.createdAt = createdAt
        self.expiresAt = expiresAt ?? createdAt.addingTimeInterval(ttlSeconds)
        self.isManuallyFrozen = false
        self.hasExtendedOnce = false
        self.nickname = nickname
        self.lastRead = [:]
        self.kind = kind
        self.deleteAfter = nil
        var choices: [String: String] = [:]
        for uid in participants {
            choices[uid] = ContinueChoice.undecided.rawValue
        }
        self.continueChoices = choices
    }

    static func generateNickname(seed: String? = nil) -> String {
        let adjectives = [
            "gentle", "quiet", "golden", "soft", "silver", "wandering",
            "tender", "warm", "still", "amber", "velvet", "calm",
            "bright", "wild", "dawn", "misty", "rosy", "early", "faint"
        ]
        let nouns = [
            "moon", "rain", "river", "spark", "echo", "bloom",
            "mist", "light", "cloud", "ember", "tide", "rose",
            "leaf", "song", "sky", "field", "flame", "shore"
        ]
        if let seed, !seed.isEmpty {
            // Stable hash so legacy threads with no stored nickname keep the
            // same name across fetches and for both participants.
            var hash: UInt64 = 5381
            for byte in seed.utf8 { hash = hash &* 33 &+ UInt64(byte) }
            let adj  = adjectives[Int(hash % UInt64(adjectives.count))]
            let noun = nouns[Int((hash >> 8) % UInt64(nouns.count))]
            return "\(adj) \(noun)"
        }
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

    // MARK: 到时间以后:24 小时内决定要不要再聊 48 小时
    //
    // 48 小时到了,对话先停住,两个人各自回答"要不要再聊 48 小时"。
    // 这个决定只开放 24 小时(2026-11-22 她定的):从到时间那一刻算起,两个人看到的是同一个钟。
    // 过了 24 小时还没有两个 Yes,对话就结束,不再问。
    // 依据:不知道要等多久的等待,比知道还要等多久的等待难熬(Maister,《等待的心理学》);
    // Here 里别的东西都有期限(帖子 48 小时、对话 48 小时),这里原来是唯一没有尽头的状态。
    static let decisionWindow: TimeInterval = 24 * 60 * 60

    /// 最晚到什么时候还能决定
    var decisionDeadline: Date { expiresAt.addingTimeInterval(Self.decisionWindow) }

    /// 现在是不是正在"等两个人决定"的那 24 小时里
    func isAwaitingDecision(now: Date = Date()) -> Bool {
        !isManuallyFrozen && !hasExtendedOnce && isExpired(now: now) && now < decisionDeadline
    }

    // Custom decoder so old Firestore documents without `nickname`/`postId` still decode.
    enum CodingKeys: String, CodingKey {
        case id, postId, postTitle, participants, createdAt, expiresAt
        case isManuallyFrozen, hasExtendedOnce, continueChoices, nickname, lastRead
        case kind, deleteAfter
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let docId        = try  c.decode(DocumentID<String>.self,  forKey: .id)
        _id              = docId
        postId           = try? c.decode(String.self,              forKey: .postId)
        postTitle        = try  c.decode(String.self,              forKey: .postTitle)
        participants     = try  c.decode([String].self,            forKey: .participants)
        createdAt        = try  c.decode(Date.self,                forKey: .createdAt)
        expiresAt        = try  c.decode(Date.self,                forKey: .expiresAt)
        isManuallyFrozen = (try? c.decode(Bool.self,              forKey: .isManuallyFrozen)) ?? false
        hasExtendedOnce  = (try? c.decode(Bool.self,              forKey: .hasExtendedOnce))  ?? false
        continueChoices  = (try? c.decode([String: String].self,  forKey: .continueChoices))  ?? [:]
        nickname         = (try? c.decode(String.self,            forKey: .nickname))          ?? ChatThread.generateNickname(seed: docId.wrappedValue)
        lastRead         = (try? c.decode([String: Date].self,    forKey: .lastRead))          ?? [:]
        kind             = try? c.decode(String.self,              forKey: .kind)
        deleteAfter      = try? c.decode(Date.self,                forKey: .deleteAfter)
    }
}




































