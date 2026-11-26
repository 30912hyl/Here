import SwiftUI

/// Phone-number verification: enter number → enter SMS code. Presented the
/// first time someone tries to post, chat or join voice, and from Profile.
///
/// 样子是 2026-11-25 的草稿(等她看):和举报、确认条款那两张用同一套零件(SheetParts.swift)。
/// 每一句英文和流程都没有动。
struct PhoneSignInSheet: View {
    @EnvironmentObject private var auth: AuthService
    @Environment(\.dismiss) private var dismiss

    /// Why we're asking — shown under the title so the gate never feels arbitrary.
    var reason: String = "Posting and chatting need a verified phone number. It's never shown to anyone."
    var onVerified: (() -> Void)? = nil
    /// true = 只是从检查面板打开看样子:Send code 只是翻到"输入验证码"那一步,Verify 只是关掉。
    /// 不发短信、不登录、不记录任何东西。
    var preview = false

    private enum Step { case phone, code }
    @State private var step: Step = .phone
    @State private var countryCode = "+1"
    @State private var localNumber = ""
    @State private var code = ""
    @State private var verificationID: String?
    @State private var busy = false
    @State private var errorText: String?
    @State private var agreed = false
    @FocusState private var focused: Bool

    private var e164: String {
        countryCode + localNumber.filter(\.isNumber)
    }
    private var phoneLooksValid: Bool {
        localNumber.filter(\.isNumber).count >= 7 && countryCode.hasPrefix("+")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            SheetHeader(
                title: step == .phone ? "Verify your phone" : "Enter the code",
                message: step == .phone ? reason : "We sent a 6-digit code to \(e164)."
            )

            if step == .phone {
                phoneFields
                SheetAgreement(agreed: $agreed)
            } else {
                codeField
            }

            if let errorText {
                // 出错的那一句:原来那个偏红的棕色留着(这是整个 app 里唯一一处"出错了"的字,颜色还没和她定过)
                Text(errorText)
                    .font(Theme.ui(14, .medium))
                    .foregroundColor(Color(hex: "#B3543E"))
                    .fixedSize(horizontal: false, vertical: true)
            }

            VStack(spacing: 6) {
                SheetPrimaryButton(title: step == .phone ? "Send code" : "Verify",
                                   enabled: primaryEnabled, busy: busy, action: primaryAction)

                if step == .code {
                    SheetQuietButton(title: "Use a different number") {
                        step = .phone
                        code = ""
                        errorText = nil
                    }
                }
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 20)
        .padding(.top, 30)
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .presentationBackground(Theme.paper)
        .onAppear { focused = true }
    }

    private var phoneFields: some View {
        HStack(spacing: 10) {
            TextField("", text: $countryCode, prompt: Text("+1").foregroundColor(Theme.ink3))
                .keyboardType(.phonePad)
                .frame(width: 68)
                .multilineTextAlignment(.center)
                .frame(height: 52)
                .background(SheetFieldBackground())
            TextField("", text: $localNumber, prompt: Text("Phone number").foregroundColor(Theme.ink3))
                .keyboardType(.phonePad)
                .textContentType(.telephoneNumber)
                .focused($focused)
                .padding(.horizontal, 16)
                .frame(height: 52)
                .background(SheetFieldBackground())
        }
        .font(Theme.ui(17))
        .foregroundColor(Theme.ink)
        .tint(Theme.ink)
    }

    private var codeField: some View {
        TextField("", text: $code, prompt: Text("123456").foregroundColor(Theme.tabOff))
            .keyboardType(.numberPad)
            .textContentType(.oneTimeCode)
            .focused($focused)
            .font(Theme.ui(24, .medium))
            .tracking(6)
            .foregroundColor(Theme.ink)
            .tint(Theme.ink)
            .multilineTextAlignment(.center)
            .frame(height: 60)
            .background(SheetFieldBackground())
            .onChange(of: code) {
                code = String(code.filter(\.isNumber).prefix(6))
                if code.count == 6 { primaryAction() }
            }
    }

    private var primaryEnabled: Bool {
        step == .phone ? phoneLooksValid && agreed : code.count == 6
    }

    private func primaryAction() {
        guard !busy else { return }
        if preview {
            // 只看样子:不发短信、不登录
            if step == .phone { code = ""; step = .code } else { dismiss() }
            return
        }
        errorText = nil
        busy = true
        Task {
            defer { busy = false }
            do {
                switch step {
                case .phone:
                    verificationID = try await auth.startPhoneVerification(e164)
                    code = ""
                    step = .code
                case .code:
                    guard let verificationID else { return }
                    auth.isVerifyingPhone = true
                    defer { auth.isVerifyingPhone = false }
                    try await auth.confirmCode(verificationID: verificationID, code: code)
                    await auth.recordTermsAcceptance()
                    dismiss()
                    onVerified?()
                }
            } catch {
                errorText = friendly(error)
            }
        }
    }

    private func friendly(_ error: Error) -> String {
        let ns = error as NSError
        switch ns.code {
        case 17042: return "That code isn't right. Check it and try again."          // invalidVerificationCode
        case 17051: return "That code has expired. Send a new one."                   // sessionExpired
        case 17010: return "Too many attempts. Please wait a while and try again."    // tooManyRequests
        case 17020: return "You're offline. Check your connection and try again."     // networkError
        case 17041: return "That doesn't look like a valid phone number."             // invalidPhoneNumber
        default:
            #if targetEnvironment(simulator)
            // 只在模拟器里：把真正的错误写出来，方便查。真机上还是下面那一句。
            let name = ns.userInfo["FIRAuthErrorUserInfoNameKey"] as? String ?? ns.domain
            print("phone sign-in failed:", ns)
            return "Something went wrong. Please try again. [\(ns.code) \(name)]"
            #else
            return "Something went wrong. Please try again."
            #endif
        }
    }
}

#Preview {
    Theme.paper.sheet(isPresented: .constant(true)) {
        PhoneSignInSheet().environmentObject(AuthService())
    }
}
