import SwiftUI

// MARK: - 小弹窗共用的零件
// 举报、验证手机号、确认条款,这三张从底下升上来的小页用同一套零件。
// 它们原来是最早的样子(白底、系统细字、金色按钮上写白字),和后来定下的 Profile、聊天页不是同一个 app。
// 这里只换"长什么样":纸色的底、圆体字、棕色的字和线。每一句英文都没有动,流程也没有动。
// (2026-11-25 草稿,等她看。)
//
// 依据:
//   - 颜色和字全部用 Theme 里定好的(纸色、ink / ink2 / ink3、hairline / outline / line、圆体字)。
//   - "能读的、能点的都是棕色;金色只给品牌、光和回应帖子"(Theme.swift 顶上那段)。
//     所以原来的金色按钮、金色的勾、金色的链接都换成棕色。原来金底白字约 2:1,读不清。
//   - 白色的卡片 + 极淡的线,和 Profile 的卡片同一个做法(圆角 20)。
//   - 可点的地方至少 44pt(Apple HIG)。

/// 最上面的两行:一句标题,一句说明。
struct SheetHeader: View {
    let title: String
    let message: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(Theme.ui(22, .semibold))
                .foregroundColor(Theme.ink)
                .fixedSize(horizontal: false, vertical: true)
            Text(message)
                .font(Theme.ui(15))
                .foregroundColor(Theme.ink2)
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// 这一页最主要的那个按钮:Submit report、Send code、Verify、Continue。
///
/// **定了(老板 2026-11-25 19:18:"我同意选 A")。不要再动,除非她说要重开。**
/// 能点的时候是实心深棕、米白的字,和聊天页的发送键同一个做法:它是这一页最显眼的东西。
/// 还不能点的时候是淡的线、浅棕的字。
/// 她看过、没要的 B:能点的时候也是白底、一圈棕线(和 Profile 的小按钮同一个做法)。代码已经删了。
/// 记一笔:第一次给她看的时候她看不出 A、B 的区别——没勾理由时按钮是灰的,两种一样。
/// 以后请她比较按钮,要先告诉她怎么让按钮亮起来。
struct SheetPrimaryButton: View {
    let title: String
    var enabled: Bool = true
    var busy: Bool = false
    let action: () -> Void

    private var foreground: Color { enabled ? Theme.paper : Theme.tabOff }
    private var fill: Color { enabled ? Theme.ink : Color.white.opacity(0.6) }
    private var stroke: Color { enabled ? Color.clear : Theme.outline }

    var body: some View {
        Button(action: action) {
            ZStack {
                Text(title).opacity(busy ? 0 : 1)
                if busy { ProgressView().tint(foreground) }
            }
            .font(Theme.ui(17, .semibold))
            .foregroundColor(foreground)
            .frame(maxWidth: .infinity)
            .frame(height: 52)
            .background(Capsule().fill(fill))
            .overlay(Capsule().strokeBorder(stroke, lineWidth: 1))
            .contentShape(Capsule())
        }
        .buttonStyle(PressFade())
        .disabled(!enabled || busy)
        .animation(.easeInOut(duration: 0.15), value: enabled)
    }
}

/// 主按钮下面那一行安静的字:Use a different number、Sign out instead。
struct SheetQuietButton: View {
    let title: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(Theme.ui(15, .medium))
                .foregroundColor(Theme.ink)
                .frame(maxWidth: .infinity)
                .frame(height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(PressFade())
    }
}

/// 输入框的底:白的,一圈淡淡的棕线。和聊天页的输入框同一个做法。
struct SheetFieldBackground: View {
    var body: some View {
        RoundedRectangle(cornerRadius: 16, style: .continuous)
            .fill(Color.white)
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(Theme.outline, lineWidth: 1)
            )
    }
}

/// 一个勾选框的样子(只管画,不管点):没勾是白底棕线的小方框,勾了是实心深棕、米白的勾。
/// 方的 = 可以勾好几个(举报理由、同意条款);圆的单选现在没有地方用了。
struct SheetCheckBox: View {
    let isOn: Bool

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(isOn ? Theme.ink : Color.white)
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .strokeBorder(isOn ? Theme.ink : Theme.line, lineWidth: 1.5)
            if isOn {
                Image(systemName: "checkmark")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(Theme.paper)
            }
        }
        .frame(width: 22, height: 22)
    }
}

/// "我是女性、满 18 岁、同意条款"那一行:一个勾选框,旁边是那句话(里面的条款能点开)。
/// 验证手机号和确认条款两张弹窗用的是同一句,所以放在一起。
struct SheetAgreement: View {
    @Binding var agreed: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Button { agreed.toggle() } label: {
                SheetCheckBox(isOn: agreed)
                    // 看上去 22pt,可点的地方 44pt
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(PressFade())
            // 多出来的可点范围不占版面:排版时它还是 22pt 的一个小方框
            .padding(-11)
            .accessibilityLabel("I'm a woman, 18 or older, and agree to the Terms and Community Guidelines")
            .accessibilityAddTraits(agreed ? .isSelected : [])

            (Text("I'm a woman, 18 or older, and agree to the ")
                + Text("[Terms & Community Guidelines](\(AppLinks.terms.absoluteString))").underline()
                + Text(". There's no tolerance for abuse or objectionable content."))
                .font(Theme.ui(14))
                .foregroundColor(Theme.ink2)
                .lineSpacing(3)
                .tint(Theme.ink)
                .fixedSize(horizontal: false, vertical: true)
                // 第一行字的中线和小方框的中线对齐
                .padding(.top, 2)
        }
    }
}
