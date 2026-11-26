import SwiftUI

/// Shown once to phone-verified accounts whose accepted terms are older than
/// AuthService.termsVersion — e.g. people who verified before the "I'm a
/// woman" confirmation existed. Can't be swiped away; the alternative to
/// agreeing is signing out (reading stays possible, writing doesn't).
///
/// 样子是 2026-11-25 的草稿(等她看):和举报、验证手机号那两张用同一套零件(SheetParts.swift)。
/// 每一句英文和流程都没有动。
struct TermsUpdateSheet: View {
    @EnvironmentObject private var auth: AuthService
    @Environment(\.dismiss) private var dismiss
    @State private var agreed = false
    @State private var busy = false

    /// true = 只是从检查面板打开看样子:Continue 和 Sign out instead 都只是关掉,不记录、不退出登录。
    var preview = false

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            SheetHeader(
                title: "Please confirm",
                message: "Our terms have been updated. Here is a space for women, and we ask everyone to confirm this once."
            )

            SheetAgreement(agreed: $agreed)

            VStack(spacing: 6) {
                SheetPrimaryButton(title: "Continue", enabled: agreed, busy: busy) {
                    guard !busy else { return }
                    if preview { dismiss(); return }
                    busy = true
                    Task {
                        await auth.recordTermsAcceptance()
                        busy = false
                    }
                }

                SheetQuietButton(title: "Sign out instead") {
                    if preview { dismiss(); return }
                    Task { await auth.signOut() }
                }
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 20)
        .padding(.top, 30)
        .presentationDetents([.medium])
        .presentationDragIndicator(.hidden)
        .presentationBackground(Theme.paper)
        .interactiveDismissDisabled()
    }
}
