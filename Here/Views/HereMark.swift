import SwiftUI

// MARK: - "here"：两个牵手的小人
/// 帖子下面的 "here"（我在）：就是 logo 里那两个牵手的小人，同一张图，实心，金色，没有描边。
/// 没点：左边的小人亮着，右边是一个淡淡的空位。点了：空位亮起来，两个人牵着手。
///
/// **她 2026-11-23 17:08 在手机上定的（“B1” 里的 B）。不要再动，除非她说要重开。**
///
/// 怎么走到这里的（都是她在真机上说的，2026-11-23）：
/// 1. 我照着 logo 另画了一个几何轮廓，用棕色的线勾出来 —— “看起来非常的诡异”，
///    “要不就是直接用我们本身的图标，不要拿线来勾出来”。那个画法已经删了。
/// 2. 换成 logo 那张图，没点的时候是浅棕 —— “能不能不要做成灰色？让人看着一点点的欲望都没有。”
/// 3. 给了她两种：A 是深棕的实心小人（点了，身后亮起一块金色），B 就是现在这个。我建议的是 A
///    （和背景的对比约 9:1；金色只有约 1.6:1）。她选了 B：她要的是暖的、是我们自己的金色，
///    不是最高的对比。A 的代码已经删了。
struct HereIcon: View {
    var on: Bool
    var size: CGFloat = 26

    /// 小人的金色：从“点亮的 here”那个金到 logo 最深的那个金。
    /// （不直接用 logo 的整段渐变：它最浅的那头在这么小的图标上、在底部发暖的背景上几乎看不见。）
    private static let gold = LinearGradient(
        colors: [Theme.hereFill, Color(hex: "#E0C068")],
        startPoint: .top,
        endPoint: .bottom
    )

    var body: some View {
        Self.gold
            .mask {
                Image("HereFigures")
                    .resizable()
                    .scaledToFit()
                    // 这张图左右对称，正中间是牵着的手：左半边一直是实的；右半边没点的时候只有 40%
                    .mask {
                        HStack(spacing: 0) {
                            Color.black
                            Color.black.opacity(on ? 1 : 0.4)
                        }
                    }
            }
            .frame(width: size, height: size)
            // 这张图左右各有一截空白，不算进宽度，不然和旁边的字离得太远
            .frame(width: size * 0.7)
            .animation(.spring(response: 0.32, dampingFraction: 0.62), value: on)
            .accessibilityHidden(true)
    }
}

// MARK: - Logo 和名字
/// Logo：两个牵手的人形，用 logo 的金色。
struct HereLogo: View {
    var width: CGFloat = 144

    var body: some View {
        Theme.logoGold
            .mask {
                Image("HereFigures")
                    .resizable()
                    .scaledToFit()
            }
            .frame(width: width, height: width)
            .accessibilityHidden(true)
    }
}

/// 品牌页的全部内容：logo 和名字，别的什么都没有。
/// 在整块屏幕的正中（不是安全区的正中）。名字那一行字的行框下面留白比上面多，
/// 所以把这一组居中以后，看得见的部分会比几何中心高 13pt 左右——正好是眼睛觉得"居中"的位置。
struct BrandMark: View {
    // 名字是金色的，比小人最深的地方再深一档：两个是一家，从上到下由浅到深。
    // （试过深棕、浅棕、棕和金之间的颜色，在真机上都"和 logo 格格不入"或"太深"。）
    var body: some View {
        VStack(spacing: 0) {
            HereLogo()
            Text("Here")
                .font(Theme.brand(66))
                .foregroundStyle(Theme.brandGold)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .ignoresSafeArea()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Here")
    }
}

/// 打开 app 时先出现的品牌页：背后是会动的光。
struct BrandScreen: View {
    var body: some View {
        ZStack {
            LiquidLightBackground(focusY: 0.42)
            BrandMark()
        }
    }
}
