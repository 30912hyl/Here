import SwiftUI

/// Asks why something is being reported: pick one reason, optionally add
/// details. Shared by post reports and chat reports.
struct ReportSheet: View {
    let title: String
    let message: String
    let onSubmit: (_ reason: String, _ details: String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var selectedReason: String?
    @State private var details = ""

    static let reasons = [
        "Harassment or bullying",
        "Hate speech",
        "Sexual content",
        "Self-harm or safety concern",
        "Spam or scam",
        "Something else"
    ]

    private static let detailsLimit = 500

    private let gold = Color(hex: "#D9AE52")
    private let hairline = Color(hex: "#EFE6CF")

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(title)
                        .font(.system(size: 20, weight: .regular))
                        .foregroundColor(Color(hex: "#3A3324"))
                    Text(message)
                        .font(.system(size: 13, weight: .light))
                        .foregroundColor(Color(hex: "#8E8672"))
                }

                VStack(spacing: 0) {
                    ForEach(Self.reasons, id: \.self) { reason in
                        reasonRow(reason)
                        if reason != Self.reasons.last {
                            Rectangle().fill(hairline).frame(height: 0.5)
                        }
                    }
                }

                TextField("Add details (optional)", text: $details, axis: .vertical)
                    .font(.system(size: 15, weight: .light))
                    .lineLimit(3...6)
                    .padding(12)
                    .background(RoundedRectangle(cornerRadius: 12).fill(Color(hex: "#FDFAF2")))
                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(hairline, lineWidth: 1))
                    .onChange(of: details) {
                        if details.count > Self.detailsLimit {
                            details = String(details.prefix(Self.detailsLimit))
                        }
                    }

                Button {
                    guard let reason = selectedReason else { return }
                    let trimmed = details.trimmingCharacters(in: .whitespacesAndNewlines)
                    dismiss()
                    // Reporting a post removes it from the feed, and with it the view
                    // presenting this sheet — let the sheet finish sliding away first
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                        onSubmit(reason, trimmed)
                    }
                } label: {
                    Text("Submit report")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(Capsule().fill(selectedReason == nil ? Color(hex: "#EADFC2") : gold))
                }
                .disabled(selectedReason == nil)
            }
            .padding(.horizontal, 24)
            .padding(.top, 28)
            .padding(.bottom, 16)
        }
        .scrollDismissesKeyboard(.interactively)
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .presentationBackground(.white)
    }

    private func reasonRow(_ reason: String) -> some View {
        let isSelected = selectedReason == reason
        return Button {
            selectedReason = reason
        } label: {
            HStack {
                Text(reason)
                    .font(.system(size: 16, weight: isSelected ? .regular : .light))
                    .foregroundColor(Color(hex: "#3A3324"))
                Spacer()
                ZStack {
                    Circle()
                        .stroke(isSelected ? gold : Color(hex: "#DDD2B4"), lineWidth: 1)
                        .frame(width: 20, height: 20)
                    if isSelected {
                        Circle().fill(gold).frame(width: 11, height: 11)
                    }
                }
            }
            .padding(.vertical, 14)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    Color.white.sheet(isPresented: .constant(true)) {
        ReportSheet(
            title: "Why are you reporting this post?",
            message: "Your report is anonymous, and you won't see this post again."
        ) { _, _ in }
    }
}
