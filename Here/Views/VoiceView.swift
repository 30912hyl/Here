//
//  VoiceView.swift
//  Here
//
//  Created by yuchen on 1/27/26.
//
import SwiftUI

struct VoiceView: View {
    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 12) {
                Text("Voice (later)")
                    .font(.title2).bold()
                Text("We'll open voice during scheduled hours once you have enough users.")
                    .foregroundStyle(.secondary)
                Spacer()
            }
            .padding()
            .navigationTitle("Voice")
        }
    }
}

#Preview {
    VoiceView()
}
