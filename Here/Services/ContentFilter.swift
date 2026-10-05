import Foundation

/// On-device check that runs before a post or message is sent. Apple requires
/// UGC apps to filter objectionable material before it is posted; reports and
/// blocking cover what gets through.
///
/// Deliberately narrow: people come here to say how they feel, including dark
/// feelings, so expressing sadness or self-harm thoughts is NOT filtered. What
/// is blocked: slurs, telling someone to kill themselves, sexual solicitation,
/// and contact details / links (the community guidelines forbid sharing
/// personal information with strangers).
enum ContentFilter {
    enum Verdict: Equatable {
        case ok
        case blocked(String)
    }

    /// Posts are self-expression: people quote what was done or said to them
    /// ("he sent me a dick pic", "he told me to kill myself"), so only slurs and
    /// contact details are filtered there. Messages are directed at a stranger,
    /// so harassment and sexual solicitation are filtered too.
    enum Context { case post, message }

    /// When false, contact details and links are allowed through.
    static var blocksContactInfo = true

    static func check(_ context: Context, _ texts: String...) -> Verdict {
        let raw = texts.joined(separator: "\n")
        let normalized = normalize(raw)
        let tokens = Set(normalized.split(separator: " ").map(String.init))

        if !tokens.isDisjoint(with: slurs) {
            return .blocked("This contains language that isn't allowed here.")
        }
        if context == .message {
            let padded = " " + normalized + " "
            if harassmentPhrases.contains(where: { padded.contains(" " + $0 + " ") }) {
                return .blocked("Please be kind — that kind of message isn't allowed here.")
            }
            if sexualPhrases.contains(where: { padded.contains(" " + $0 + " ") }) {
                return .blocked("Sexual requests aren't allowed here.")
            }
        }
        if blocksContactInfo, containsContactInfo(raw) {
            return .blocked("For everyone's safety, please don't share phone numbers, emails, social handles, or links.")
        }
        return .ok
    }

    // MARK: - Lists

    private static let slurs: Set<String> = Set([
        "bmlnZ2Vy",
        "bmlnZ2E=",
        "ZmFnZ290",
        "dHJhbm55",
        "Y2hpbms=",
        "c3BpYw==",
        "a2lrZQ==",
        "d2V0YmFjaw==",
        "Z29vaw==",
        "Y29vbg==",
        "cGFraQ==",
        "cmFnaGVhZA==",
        "dG93ZWxoZWFk",
        "YmVhbmVy"
    ].compactMap { Data(base64Encoded: $0).flatMap { String(data: $0, encoding: .utf8) } })

    private static let harassmentPhrases = [
        "kill yourself", "kill urself", "kys", "go die", "you should die", "end yourself",
        "nobody would miss you", "hope you die",
    ].map(normalize)

    private static let sexualPhrases = [
        "send nudes", "send nude", "send me nudes", "send pics", "dick pic", "dickpic", "sext me",
        "show me your body", "show me your tits", "show me your boobs", "wanna fuck", "want to fuck",
        "lets fuck", "come over tonight",
    ].map(normalize)

    // MARK: - Contact details

    private static let contactPatterns: [NSRegularExpression] = [
        // email
        #"[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}"#,
        // links
        #"(https?://|www\.)\S+"#,
        #"\b[a-z0-9-]+\.(com|net|org|io|me|app|co|ly|gg|tv|xyz)\b"#,
        // phone numbers: 7+ digits, allowing spaces, dots, dashes, brackets
        #"(\+?\d[\s\-.()]*){7,}"#,
        // @handles
        #"(^|\s)@[a-z0-9._]{3,}"#,
        // "insta: name", "snap - name", "wechat：name"
        #"\b(snap(chat)?|insta(gram)?|ig|telegram|tg|whatsapp|wechat|discord|kik|line|tiktok)\s*[:：\-]\s*@?[a-z0-9._]{3,}"#,
    ].map { try! NSRegularExpression(pattern: $0, options: [.caseInsensitive]) }

    private static func containsContactInfo(_ text: String) -> Bool {
        let range = NSRange(text.startIndex..., in: text)
        return contactPatterns.contains { $0.firstMatch(in: text, range: range) != nil }
    }

    // MARK: - Normalisation

    /// Lowercase, fold accents, undo common letter substitutions, drop
    /// punctuation, and squeeze long letter runs ("sooooo" → "soo") so trivial
    /// disguises still match.
    static func normalize(_ s: String) -> String {
        let folded = s.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
        let leet: [Character: Character] = ["0": "o", "1": "i", "3": "e", "4": "a", "5": "s", "7": "t", "@": "a", "$": "s", "!": "i"]
        var out = ""
        var last: Character = " "
        var run = 0
        for ch in folded {
            var c = leet[ch] ?? ch
            if !c.isLetter { c = " " }
            if c == last {
                run += 1
                if run >= 2 && c != " " { continue }
                if c == " " { continue }
            } else {
                run = 0
            }
            out.append(c)
            last = c
        }
        return out.trimmingCharacters(in: .whitespaces)
    }
}
