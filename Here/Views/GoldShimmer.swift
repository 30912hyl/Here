import SwiftUI

// MARK: - 渐变金边
// 角向渐变让金边有明暗起伏(静态,不做动画,避免喧宾夺主)。

enum GoldShimmer {
    /// 首尾同色,衔接无缝。用于黄色背景区(如 tag bar)。
    static let colors: [Color] = [
        Color(hex: "#C9A55E"),
        Color(hex: "#F5E7B8"),
        Color(hex: "#D8B76A"),
        Color(hex: "#F9EFD2"),
        Color(hex: "#C9A55E")
    ]

    /// 更浅的一套,用于白色背景区(Chat privately、爱心),避免太抢眼。
    static let softColors: [Color] = [
        Color(hex: "#E2CD97"),
        Color(hex: "#F8EFD3"),
        Color(hex: "#EAD8A6"),
        Color(hex: "#FBF4E1"),
        Color(hex: "#E2CD97")
    ]

    /// 乳白内里
    static let milk = Color(hex: "#FEFAF0")
}

/// 乳白底 + 渐变金边的胶囊背景
struct GoldShimmerCapsule: View {
    var lineWidth: CGFloat = 3
    /// 渐变的固定朝向,亮部落在左上
    var angle: Double = 210
    var colors: [Color] = GoldShimmer.colors

    var body: some View {
        ZStack {
            Capsule().fill(GoldShimmer.milk)
            Capsule().strokeBorder(
                AngularGradient(
                    gradient: Gradient(colors: colors),
                    center: .center,
                    angle: .degrees(angle)
                ),
                lineWidth: lineWidth
            )
        }
    }
}
