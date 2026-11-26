import SwiftUI
import CoreText

// MARK: - Theme
// One place for the app's colours and type, so a screen never invents its own.
//
// The palette, settled on the phone on 2026-11-21 (see claude/here-design-process.md).
// It is decided as a set and it is locked: change it only when she asks to reopen it.
//
//   Gold is the brand, the light, and the two ways of answering a post. Nothing else.
//     - the brand: the logo, and the name under it
//     - the light: the glow behind the pages, and the fill of something lit
//       (a selected chip, the unread badge)
//     - answering a post. She reopened "no gold on controls" herself on 2026-11-23 ("we have
//       to lead people to tap private chat... it could be gold... make them want to tap")
//       and picked both on the phone the same day ("B1"):
//         "here" is the logo's two figures in gold: one solid with a faint place beside her,
//         both solid once tapped (HereIcon).
//         "Chat privately" is a solid matte-gold capsule with deep-brown text (FeedView).
//         How deep that gold is, is still being settled with her: the first one was
//         "a little too deep, too conspicuous".
//   Everything else you read or press is brown: text, icons, and every line.
//     - the create button is one solid heart in the deep brown of the selected tab icon,
//       with nothing around it (locked 2026-11-22: "the one with the most presence").
//       No gold in it and no ring: every version with either was turned down on the phone.
//     - a selected chip is a pale fill with a brown line, not a gold line
//   Nothing the app draws is pure black.
//
// What was tried and failed on the phone, so nobody tries it again:
// under a post: the figures drawn with a brown outline ("eerie"), the figures in the pale
// brown of the resting tab icons ("grey... not the slightest wish to tap"), a white
// "Chat privately" ("doesn't connect with the background") and a see-through one with a
// faint line ("more unified", but nothing invites a tap).
// a gold fill on the create button (a slab of yellow), gold lines on controls (weak, or "too gold"), a brown
// name under the gold logo ("doesn't belong"), a mid tone between brown and gold for the
// name ("still too dark"), and for the create button: a mid-brown ring around a gold heart
// ("doesn't match"), ring and heart both in a brown-gold ("too gold"), both in the pale
// brown of the resting tab icons ("too light"), both in the deep brown ("still ugly").
// A heart inside a ring failed nine times over: the drawing was the problem, not the colour.
// The brand colours are the ones she set herself with sliders and called pleasing. I moved
// both a step deeper once "for safety"; she saw it at once ("a bit deep again"). Don't.
//
// Day palette only for now; the night palette comes once the day pages are settled.
enum Theme {
    // Paper and ink
    static let paper = Color(hex: "#FDFAF4")
    static let ink = Color(hex: "#5C3A1E")      // main text
    static let ink2 = Color(hex: "#7A6350")     // secondary text, small icons
    static let ink3 = Color(hex: "#87705B")     // quiet text
    static let tabOff = Color(hex: "#A69584")   // tab bar, resting
    static let photoBackdrop = Color(hex: "#16120F")  // behind a full-screen photo (the night page colour)

    // Gold: the brand
    /// The name under the logo. Locked 2026-11-21.
    static let brandGold = Color(hex: "#D4B368")
    /// The logo, top to bottom. As pale as it goes: "the lighter the better". Locked 2026-11-21.
    static var logoGold: LinearGradient {
        LinearGradient(colors: [Color(hex: "#F8EABC"), Color(hex: "#E0C068")], startPoint: .top, endPoint: .bottom)
    }

    // Gold: the light
    /// The glow. (#F7E5BC before: a shade too orange, it read as slightly red on the phone.)
    static let champagne = Color(hex: "#F7EBB9")
    static let goldFillTop = Color(hex: "#F8EED0")      // the unread badge, top to bottom
    static let goldFillBottom = Color(hex: "#EFDBA5")
    static let hereFill = Color(hex: "#EBD493")         // the top of the gold of the "here" figures

    // Lines: the ink, very thin
    static let hairline = Color(hex: "#5C3A1E").opacity(0.09)
    static let outline = Color(hex: "#5C3A1E").opacity(0.16)
    static let dash = Color(hex: "#5C3A1E").opacity(0.32)       // dashed outline of an "add" tile
    /// Every solid line: around a button (Send, Yes, No), around a selected chip. The secondary brown.
    static let line = Color(hex: "#7A6350")

    /// Inside a selected chip (a tag, a filter): the palest gold, with a brown line around it
    static let selectedFill = Color(hex: "#FBF5E4")

    /// `ink` for the places SwiftUI colours can't reach (navigation bar titles).
    static let inkUIColor = UIColor(red: 0x5C / 255.0, green: 0x3A / 255.0, blue: 0x1E / 255.0, alpha: 1)

    /// Fill of something small and lit (the unread badge): matte, top to bottom, no shine.
    static var matteGold: LinearGradient {
        LinearGradient(colors: [goldFillTop, goldFillBottom], startPoint: .top, endPoint: .bottom)
    }

    /// The interface face: SF Pro Rounded.
    static func ui(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        Font.system(size: size, weight: weight, design: .rounded)
    }

    /// The face of the name and of the app's own voice: Baloo 2 Medium.
    /// Falls back to the system face if the font file is missing.
    static func brand(_ size: CGFloat) -> Font {
        Font.custom(BrandFont.postScriptName, size: size)
    }
}

// MARK: - Pressed feedback
/// For rows and cards the app draws itself (a conversation row, the "started from" card):
/// fade a little while pressed, so a tap is felt. (HIG: a custom button needs a pressed state.)
struct PressFade: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.55 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

// MARK: - Brand font
enum BrandFont {
    static let postScriptName = "Baloo2-Medium"
    private static var registered = false

    /// The font file ships in the app bundle (Here/Fonts). Registering it here
    /// means no Info.plist entry is needed. Call once at launch.
    static func register() {
        guard !registered else { return }
        registered = true
        guard let url = Bundle.main.url(forResource: "Baloo2-Medium", withExtension: "ttf") else {
            print("Baloo2-Medium.ttf is not in the bundle; the name falls back to the system face")
            return
        }
        CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
    }
}
