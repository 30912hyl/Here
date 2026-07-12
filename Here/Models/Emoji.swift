//
//  Emoji.swift
//  Here
//
//  Emoji-only validation for post tags.
//

import Foundation

extension Character {
    /// True when this character renders as an emoji, including multi-scalar
    /// sequences like 1️⃣, ❤️, 🇭🇴, 👨‍👩‍👧 and letter emoji like 🅰.
    /// Plain digits/letters/symbols (which carry the Unicode `isEmoji`
    /// property but render as text) are excluded.
    var isEmoji: Bool {
        guard let first = unicodeScalars.first else { return false }
        if first.properties.isEmojiPresentation { return true }
        if unicodeScalars.count > 1 && first.properties.isEmoji { return true }
        // Single-scalar emoji without default emoji presentation, e.g. 🅾 🅿 ‼ ▶.
        // The value floor excludes plain ASCII like 0-9, #, * that also carry isEmoji.
        if first.properties.isEmoji && first.value > 0x238C { return true }
        return unicodeScalars.contains { $0.properties.isEmojiPresentation }
    }
}

extension String {
    /// The string with every non-emoji character removed.
    var emojiOnly: String { String(filter(\.isEmoji)) }

    /// True when non-empty and made up entirely of emoji.
    var isEmojiOnly: Bool { !isEmpty && allSatisfy(\.isEmoji) }
}
