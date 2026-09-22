import SwiftUI

/// Phone-number verification: enter number → enter SMS code. Presented the
/// first time someone tries to post, chat or join voice, and from Profile.
struct PhoneSignInSheet: View {
    @EnvironmentObject private var auth: AuthService
    @Environment(\.dismiss) private var dismiss

    /// Why we're asking — shown under the title so the gate never feels arbitrary.
    var reason: String = "Posting and chatting need a verified phone number. It's never shown to anyone."
    var onVerified: (() -> Void)? = nil

    private enum Step { case phone, code }
    @State private var step: Step = .phone
    @State private var countryCode = "+1"
    @State private var localNumber = ""
    @State private var code = ""
    @State private var verificationID: String?
    @State private var busy = false
    @State private var errorText: String?
    @FocusState private var focused: Bool

    private let gold = Color(hex: "#D9AE52")
    private let hairline = Color(hex: "#EFE6CF")
    private let ink = Color(hex: "#3A3324")
    private let muted = Color(hex: "#8E8672")

    private var e164: String {
        countryCode + localNumber.filter(\.isNumber)
    }
    private var phoneLooksValid: Bool {
        localNumber.filter(\.isNumber).count >= 7 && countryCode.hasPrefix("+")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            VStack(alignment: .leading, spacing: 6) {
                Text(step == .phone ? "Verify your phone" : "Enter the code")
                    .font(.system(size: 20, weight: .regular))
                    .foregroundColor(ink)
                Text(step == .phone ? reason : "We sent a 6-digit code to \(e164).")
                    .font(.system(size: 13, weight: .light))
                    .foregroundColor(muted)
            }

            if step == .phone { phoneFields } else { codeField }

            if let errorText {
                Text(errorText)
                    .font(.system(size: 13, weight: .light))
                    .foregroundColor(Color(hex: "#B3543E"))
            }

            Button(action: primaryAction) {
                ZStack {
                    Text(step == .phone ? "Send code" : "Verify")
                        .opacity(busy ? 0 : 1)
                    if busy { ProgressView().tint(.white) }
                }
                .font(.system(size: 16, weight: .medium))
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(Capsule().fill(primaryEnabled ? gold : Color(hex: "#EADFC2")))
            }
            .disabled(!primaryEnabled || busy)

            if step == .code {
                Button("Use a different number") {
                    step = .phone
                    code = ""
                    errorText = nil
                }
                .font(.system(size: 13, weight: .light))
                .foregroundColor(muted)
                .frame(maxWidth: .infinity)
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 24)
        .padding(.top, 28)
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .presentationBackground(.white)
        .onAppear { focused = true }
    }

    private var phoneFields: some View {
        HStack(spacing: 10) {
            TextField("+1", text: $countryCode)
                .keyboardType(.phonePad)
                .frame(width: 64)
                .multilineTextAlignment(.center)
                .padding(.vertical, 12)
                .background(fieldBackground)
            TextField("Phone number", text: $localNumber)
                .keyboardType(.phonePad)
                .textContentType(.telephoneNumber)
                .focused($focused)
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .background(fieldBackground)
        }
        .font(.system(size: 17, weight: .light))
    }

    private var codeField: some View {
        TextField("123456", text: $code)
            .keyboardType(.numberPad)
            .textContentType(.oneTimeCode)
            .focused($focused)
            .font(.system(size: 24, weight: .light))
            .tracking(6)
            .multilineTextAlignment(.center)
            .padding(.vertical, 12)
            .background(fieldBackground)
            .onChange(of: code) {
                code = String(code.filter(\.isNumber).prefix(6))
                if code.count == 6 { primaryAction() }
            }
    }

    private var fieldBackground: some View {
        RoundedRectangle(cornerRadius: 12)
            .fill(Color(hex: "#FDFAF2"))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(hairline, lineWidth: 1))
    }

    private var primaryEnabled: Bool {
        step == .phone ? phoneLooksValid : code.count == 6
    }

    private func primaryAction() {
        guard !busy else { return }
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
                    try await auth.confirmCode(verificationID: verificationID, code: code)
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
        default:    return "Something went wrong. Please try again."
        }
    }
}

#Preview {
    Color.white.sheet(isPresented: .constant(true)) {
        PhoneSignInSheet().environmentObject(AuthService())
    }
}
