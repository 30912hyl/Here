import SwiftUI

/// Asks why something is being reported: pick one or more reasons, optionally
/// add details. Shared by post reports and chat reports.
///
/// 样子是 2026-11-25 的草稿(等她看):纸色的底、圆体字、七个理由放在一张白卡片里、
/// 选中的那个是一个实心的棕色圆点。每一句英文和提交的流程都没有动。零件在 SheetParts.swift。
struct ReportSheet: View {
    let title: String
    let message: String
    /// 选中的理由按列表里的顺序交出去,至少一条。
    let onSubmit: (_ reasons: [String], _ details: String) -> Void

    @Environment(\.dismiss) private var dismiss
    /// 可以选好几条,全选也行(老板 2026-11-25 19:05:"一定要做成它可以选多项的…万一这几项都有呢")。
    @State private var selected: Set<String> = []
    @State private var details = ""

    private var chosen: [String] { Self.reasons.filter(selected.contains) }

    /// 举报的理由。**老板 2026-11-25 18:54 定的这 8 条("我觉得这样分类是 OK 的,没什么问题")。**
    ///
    /// 怎么来的(过程在 claude/here-backend-2026-11-25.md 第 8 节):
    ///   - 第一条是"可能不是女生":她认为这是最可能的原因,而且拿不准也应该先举报。
    ///   - 都是短标签,写法统一(她定的)。"不用确定"放在标题下面那句里,对每一条都管用。
    ///   - "未成年"和"别人的隐私或照片"是对照别的 app 以后补的,她"坚决同意"。
    ///   - 最后一条是"说不清,就是不对劲":这类举报不算进"3 个人举报就自动藏帖",10 个不同的人才藏
    ///     (functions/lib/handlers.js 的 SOFT_REASON 认的就是这几个字,**两边要一起改**)。
    ///   - 谈政治、谈敏感话题不是举报理由:她定的,"不应该让另一方销声匿迹"。
    /// 对照过 Instagram、TikTok、Snapchat、Reddit、Yik Yak、Bumble、Tinder 七个的举报列表;
    /// 别人有而这里故意没有的:卖违禁品、假消息、冒充、版权、极端组织、app 外的事(原因见文档)。
    static let reasons = [
        "May not be a woman",
        "Seems under 18",
        "Harassment, threats or hate",
        "Sexual or violent content",
        "Spam, ads or scam",
        "Someone's private info or photos",
        "Self-harm or safety concern",
        feelsOff
    ]

    /// 说不清、就是不对劲。服务器按这几个字认这一类举报。
    static let feelsOff = "Something feels off"

    /// 标题下面的第一行。她 2026-11-25 19:05 说的原话:"第一行可以写 Please select one or more reasons,
    /// 然后写 You don't have to be sure,然后第二行再写 report is anonymous、你不会再看到这个 post。"
    /// 第二行是各处传进来的那一句(帖子和对话不一样)。标题("Why are you reporting…")我没有动。
    /// 两句话各占一行:连在一起写的话,一行放不下,"be sure." 会孤零零掉到下一行(2026-11-25 在模拟器里看到的)。
    private static let firstLine = "Please select one or more reasons.\nYou don't have to be sure."

    private static let detailsLimit = 500

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                SheetHeader(title: title, message: Self.firstLine + "\n" + message)

                // 七个理由:一张白卡片,和 Profile 的卡片同一个做法
                VStack(spacing: 0) {
                    ForEach(Self.reasons, id: \.self) { reason in
                        reasonRow(reason)
                        if reason != Self.reasons.last {
                            Rectangle().fill(Theme.hairline).frame(height: 1).padding(.leading, 18)
                        }
                    }
                }
                .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(Color.white.opacity(0.9)))
                .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(Theme.hairline, lineWidth: 1))

                TextField("", text: $details,
                          prompt: Text("Add details (optional)").foregroundColor(Theme.ink3),
                          axis: .vertical)
                    .font(Theme.ui(16))
                    .foregroundColor(Theme.ink)
                    .tint(Theme.ink)
                    .lineLimit(3...6)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 14)
                    .background(SheetFieldBackground())
                    .onChange(of: details) {
                        if details.count > Self.detailsLimit {
                            details = String(details.prefix(Self.detailsLimit))
                        }
                    }

                SheetPrimaryButton(title: "Submit report", enabled: !selected.isEmpty) {
                    let reasons = chosen
                    guard !reasons.isEmpty else { return }
                    let trimmed = details.trimmingCharacters(in: .whitespacesAndNewlines)
                    dismiss()
                    // Reporting a post removes it from the feed, and with it the view
                    // presenting this sheet — let the sheet finish sliding away first
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                        onSubmit(reasons, trimmed)
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 30)
            .padding(.bottom, 16)
        }
        .scrollDismissesKeyboard(.interactively)
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .presentationBackground(Theme.paper)
    }

    private func reasonRow(_ reason: String) -> some View {
        let isSelected = selected.contains(reason)
        return Button {
            // 再点一下就取消
            if isSelected { selected.remove(reason) } else { selected.insert(reason) }
        } label: {
            HStack(spacing: 12) {
                Text(reason)
                    .font(Theme.ui(16, isSelected ? .semibold : .regular))
                    .foregroundColor(Theme.ink)
                Spacer(minLength: 8)
                // 方的勾选框:能勾好几个。(原来是圆的单选,一次只能选一条。)
                SheetCheckBox(isOn: isSelected)
            }
            .padding(.horizontal, 18)
            .frame(minHeight: 52)
            .contentShape(Rectangle())
        }
        .buttonStyle(PressFade())
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

#Preview {
    Theme.paper.sheet(isPresented: .constant(true)) {
        ReportSheet(
            title: "Why are you reporting this post?",
            message: "Your report is anonymous, and you won't see this post again."
        ) { _, _ in }
    }
}
