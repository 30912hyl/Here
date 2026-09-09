//
//  VoiceView.swift
//  Here
//
//  Created by yuchen on 1/27/26.
//
import SwiftUI

// MARK: - Palette (matches ProfileView)

private let voiceGoldGradient = LinearGradient(
    colors: [Color(hex: "#F8EFD6"), Color(hex: "#F2DFAF"), Color(hex: "#E8C97A")],
    startPoint: .topLeading,
    endPoint: .bottomTrailing
)
private let voiceBrownText = Color(hex: "#5C3A1E")
private let voiceMutedGold = Color(hex: "#D8C898")
private let voiceGoldAccent = Color(hex: "#E6C35C")
private let voiceBackground = Color(hex: "#FAF8F4")
private let voiceCardBorder = Color(hex: "#E8E0CC")

// MARK: - VoiceView
//
// Presence only, no calling yet: an "open to connect" toggle and how many
// others have it on right now. Matching + the actual call come once this
// number is regularly above zero.

struct VoiceView: View {
    @ObservedObject var voice: VoicePresenceService

    var body: some View {
        NavigationStack {
            ZStack {
                voiceBackground.ignoresSafeArea()

                VStack(spacing: 24) {
                    Text("voice")
                        .font(.system(size: 32, weight: .light))
                        .foregroundColor(voiceBrownText)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 28)

                    toggleCard
                    presenceCard

                    Spacer()
                }
                .padding(.top, 36)
                .padding(.bottom, 110)
            }
        }
    }

    // MARK: - Toggle

    private var toggleCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 14) {
                Image(systemName: voice.isAvailable ? "waveform" : "waveform.slash")
                    .font(.system(size: 16, weight: .light))
                    .foregroundStyle(voiceGoldGradient)
                    .frame(width: 24)

                VStack(alignment: .leading, spacing: 4) {
                    Text("OPEN TO CONNECT")
                        .font(.system(size: 10, weight: .medium))
                        .tracking(1.5)
                        .foregroundColor(voiceMutedGold)
                    Text(voice.isAvailable ? "You're open right now" : "Not right now")
                        .font(.system(size: 15, weight: .regular))
                        .foregroundColor(voiceBrownText)
                }

                Spacer()

                Toggle("", isOn: Binding(
                    get: { voice.isAvailable },
                    set: { voice.setAvailable($0) }
                ))
                .labelsHidden()
                .tint(voiceGoldAccent)
            }

            Text("Keep browsing — we'll let you know if someone else is open. Turns off by itself when you leave the app.")
                .font(.system(size: 12, weight: .light))
                .foregroundColor(voiceMutedGold)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(20)
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(voiceCardBorder, lineWidth: 1)
        )
        .padding(.horizontal, 20)
    }

    // MARK: - Presence count

    private var presenceCard: some View {
        HStack(spacing: 14) {
            Circle()
                .fill(voice.othersAvailable > 0 ? voiceGoldAccent : voiceMutedGold)
                .frame(width: 8, height: 8)

            Text(presenceText)
                .font(.system(size: 14, weight: .light))
                .foregroundColor(voiceBrownText)

            Spacer()
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(voiceCardBorder, lineWidth: 1)
        )
        .padding(.horizontal, 20)
    }

    private var presenceText: String {
        switch voice.othersAvailable {
        case 0:  return "No one else is open right now"
        case 1:  return "1 other person is open right now"
        default: return "\(voice.othersAvailable) others are open right now"
        }
    }
}

#Preview {
    VoiceView(voice: VoicePresenceService())
}
