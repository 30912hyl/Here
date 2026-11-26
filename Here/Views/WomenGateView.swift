import SwiftUI

/// First screens anyone sees. The name on its own for a moment, then the one
/// question: Here is for women only, so we ask once.
/// "Yes" opens the app (remembered on this phone). "No" ends there — the app
/// can't be browsed or used. The answer is self-declared; what backs it up is
/// that posting and chatting need a verified phone number, and a number
/// reported and confirmed as not belonging to a woman is banned (bannedPhones).
/// The small print on the question says so.
///
/// The words are plain on purpose: a statement, a question, the consequence.
/// The two answers are the same size and the same style, so the page doesn't
/// steer anyone toward "Yes".
///
/// To let people who answer "No" browse read-only instead, show the main app
/// for `.declined` and gate actions in ContentView.requirePhone.
struct WomenGateView: View {
    enum Answer: String {
        case unanswered = ""
        case confirmed
        case declined
    }

    @Binding var answer: String

    /// The name shows first, alone; the question follows on the same light.
    @State private var showQuestion: Bool

    /// `startAtQuestion` skips the name and opens straight on the question.
    init(answer: Binding<String>, startAtQuestion: Bool = false) {
        _answer = answer
        _showQuestion = State(initialValue: startAtQuestion)
    }

    var body: some View {
        ZStack {
            // One light behind all three states, so nothing jumps between them
            LiquidLightBackground(focusY: 0.42)

            if answer == Answer.declined.rawValue {
                declined
                    .transition(.opacity)
            } else if showQuestion {
                question
                    .transition(.opacity)
            } else {
                BrandMark()
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.6), value: showQuestion)
        .animation(.easeInOut(duration: 0.25), value: answer)
        .task {
            try? await Task.sleep(nanoseconds: 1_800_000_000)
            showQuestion = true
        }
    }

    private var question: some View {
        GeometryReader { geo in
            ZStack(alignment: .bottom) {
                VStack(spacing: 14) {
                    // One line on every phone: wrapped, "only." would sit alone on a second line
                    Text("Here is for women only.")
                        .font(Theme.ui(30, .light))
                        .foregroundColor(Theme.ink)
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)

                    Text("Are you a woman aged 18 or older?")
                        .font(Theme.ui(17))
                        .foregroundColor(Theme.ink2)
                        .multilineTextAlignment(.center)
                }
                .padding(.horizontal, 36)
                .frame(maxWidth: .infinity)
                .padding(.top, geo.size.height * 0.34)
                .frame(maxHeight: .infinity, alignment: .top)

                VStack(spacing: 18) {
                    // What happens if the answer isn't true. Read just before answering.
                    // Two lines on every phone (a longer wording left one word alone on a third).
                    Text("If your answer turns out to be false, your phone number will be permanently banned from signing up again.")
                        .font(Theme.ui(13))
                        .foregroundColor(Theme.ink2)
                        .multilineTextAlignment(.center)
                        .lineSpacing(3)
                        .lineLimit(2)
                        .minimumScaleFactor(0.8)
                        .padding(.horizontal, 8)

                    // Two equal answers, side by side
                    HStack(spacing: 12) {
                        answerButton("Yes", .confirmed)
                        answerButton("No", .declined)
                    }
                }
                .padding(.horizontal, 32)
                .padding(.bottom, 52)
            }
        }
    }

    /// One answer. Both look the same: a brown line, and a fill that lets the
    /// light behind it through rather than cutting a white shape out of it.
    private func answerButton(_ title: String, _ value: Answer) -> some View {
        Button {
            answer = value.rawValue
        } label: {
            Text(title)
                .font(Theme.ui(17, .medium))
                .foregroundColor(Theme.ink)
                .frame(maxWidth: .infinity)
                .frame(height: 52)
                .background(Capsule().fill(Color.white.opacity(0.6)))
                .overlay(Capsule().strokeBorder(Theme.line, lineWidth: 1))
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    private var declined: some View {
        VStack(spacing: 14) {
            Spacer()
            Text("Here is for women only.")
                .font(Theme.ui(22, .light))
                .foregroundColor(Theme.ink)
                .multilineTextAlignment(.center)
            Text("Sorry, you can't use the app.")
                .font(Theme.ui(15))
                .foregroundColor(Theme.ink2)
                .multilineTextAlignment(.center)
            Spacer()
            Button("I chose the wrong answer") {
                answer = Answer.unanswered.rawValue
            }
            .font(Theme.ui(15, .medium))
            .foregroundColor(Theme.ink)
            .frame(height: 44)
            .padding(.bottom, 36)
        }
        .padding(.horizontal, 36)
    }
}

#Preview {
    WomenGateView(answer: .constant(""))
}
