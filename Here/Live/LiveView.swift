//
//  LiveView.swift
//  Here
//
//  Created by Aaron Lee on 8/1/25.
//

import SwiftUI

struct LiveView: View {
    @Binding var isCallActive: Bool
    @StateObject private var agoraManager = AgoraAudioManager()
    @State private var callDuration: TimeInterval = 0
    @State private var timer: Timer?
    @State private var showingCategories = false
    @State private var username = "Bala"

    var currentUser: User {
        User(name: username, profileImage: "person.circle.fill", themeColor: Color.white)
    }

    var otherUser: User {
        User(name: agoraManager.remoteUsername, profileImage: "person.circle.fill", themeColor: Color.white)
    }
    
    var body: some View {
        NavigationStack {
            GeometryReader { geometry in
                ZStack {
                    // Static pink gradient background
                    LinearGradient(
                        gradient: Gradient(colors: [
                            Color(red: 0.95, green: 0.81, blue: 0.77),  // #F3CEC4
                            Color.white
                        ]),
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .ignoresSafeArea()
                    
                    if agoraManager.isCallActive {
                        VStack(spacing: 20) {
                            Spacer()
                            
                            // Other user profile
                            VStack(spacing: 0) {
                                ZStack {
                                    // Speaking indicator glow
                                    if agoraManager.remoteUserJoined {
                                        Circle()
                                            .fill(
                                                RadialGradient(
                                                    gradient: Gradient(colors: [
                                                        Color(red: 0.95, green: 0.75, blue: 0.85).opacity(0.6),
                                                        Color(red: 0.95, green: 0.75, blue: 0.85).opacity(0.3),
                                                        Color.clear
                                                    ]),
                                                    center: .center,
                                                    startRadius: 60,
                                                    endRadius: 100
                                                )
                                            )
                                            .frame(width: 200, height: 200)
                                            .blur(radius: 20)
                                            .scaleEffect(agoraManager.remoteUserJoined ? 1.05 : 1.0)
                                            .animation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true), value: agoraManager.remoteUserJoined)
                                    }
                                    
                                    // Profile image
                                    Circle()
                                        .fill(Color.white)
                                        .frame(width: 130, height: 130)
                                        .shadow(color: Color(red: 0.95, green: 0.75, blue: 0.85).opacity(0.3), radius: 20, x: 0, y: 10)
                                    
                                    Image(systemName: otherUser.profileImage)
                                        .font(.system(size: 80, weight: .light))
                                        .foregroundColor(Color(red: 0.85, green: 0.65, blue: 0.75))
                                }
                            }
                            
                            VStack(spacing: 8) {
                                Text(agoraManager.remoteUserJoined ?
                                     agoraManager.remoteUsername:
                                     "等待连接中...")
                                    .font(.title)
                                    .fontWeight(.semibold)
                                    .foregroundColor(Color(red: 0.5, green: 0.4, blue: 0.45))
                                
                                // Connection status
                                HStack(spacing: 6) {
                                    Circle()
                                        .fill(agoraManager.isConnected ?
                                              (agoraManager.remoteUserJoined ? Color(red: 0.9, green: 0.6, blue: 0.7) : Color(red: 1.0, green: 0.8, blue: 0.85)) :
                                              Color(red: 0.95, green: 0.75, blue: 0.8))
                                        .frame(width: 8, height: 8)
                                    Text(agoraManager.statusText)
                                        .font(.subheadline)
                                        .foregroundColor(Color(red: 0.6, green: 0.5, blue: 0.55))
                                }
                                
                                // Call duration
                                Text(formatDuration(callDuration))
                                    .font(.title3)
                                    .foregroundColor(Color(red: 0.7, green: 0.6, blue: 0.65))
                                    .padding(.top, 4)
                            }
                            
                            Spacer()
                            
                            // Control buttons
                            HStack(spacing: 30) {
                                // Mute button
                                AudioControlButton(
                                    systemImage: agoraManager.isMuted ? "mic.slash.fill" : "mic.fill",
                                    isActive: !agoraManager.isMuted,
                                    backgroundColor: agoraManager.isMuted ? Color(red: 0.95, green: 0.75, blue: 0.8) : Color(red: 0.9, green: 0.9, blue: 0.92)
                                ) {
                                    agoraManager.toggleMute()
                                }
                                
                                // End call button
                                AudioControlButton(
                                    systemImage: "phone.down.fill",
                                    isActive: false,
                                    backgroundColor: Color(red: 0.95, green: 0.75, blue: 0.8),
                                    size: 60
                                ) {
                                    endCall()
                                }
                                
                                // Speaker button
                                AudioControlButton(
                                    systemImage: agoraManager.isSpeakerOn ? "speaker.wave.3.fill" : "speaker.wave.1.fill",
                                    isActive: agoraManager.isSpeakerOn,
                                    backgroundColor: agoraManager.isSpeakerOn ? Color(red: 0.9, green: 0.6, blue: 0.7) : Color(red: 0.9, green: 0.9, blue: 0.92)
                                ) {
                                    agoraManager.toggleSpeaker()
                                }
                            }
                            .padding(.bottom, 40)
                        }
                        .padding(.horizontal, 30)
                    }
                }
            }
            .toolbar(agoraManager.isCallActive ? .hidden : .visible, for: .tabBar)
            .navigationDestination(isPresented: $showingCategories) {
                CategoryView(isCallActive: $isCallActive)
            }
            .onAppear {
                if isCallActive && !agoraManager.isCallActive {
                    startNewCall()
                }
                loadUsername()
            }
            .onDisappear {
                // Don't automatically leave channel when view disappears
                // User should explicitly end call
            }
            .onChange(of: isCallActive) { _, newValue in
                if newValue && !agoraManager.isCallActive {
                    startNewCall()
                    showingCategories = false
                } else if !newValue && agoraManager.isCallActive {
                    agoraManager.leaveChannel()
                    stopCallTimer()
                } else if newValue && agoraManager.isCallActive && agoraManager.inWaitingRoom {
                    agoraManager.transitionToLiveCall()
                    startCallTimer()
                }
            }
            .onChange(of: agoraManager.startTimer) { _, shouldStart in
                if shouldStart && timer == nil {
                    startCallTimer()
                }
            }
        }
    }
    
    private func loadUsername() {
        if let savedUsername = UserDefaults.standard.string(forKey: "username"), !savedUsername.isEmpty {
            username = savedUsername
        }
    }
    
    private func startNewCall() {
        loadUsername()
        agoraManager.joinChannel(with: username)
    }
    
    private func startCallTimer() {
        callDuration = 0
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
            callDuration += 1
        }
    }
    
    private func stopCallTimer() {
        timer?.invalidate()
        timer = nil
    }
    
    private func endCall() {
        isCallActive = false
        agoraManager.leaveChannel()
        stopCallTimer()
        callDuration = 0
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            showingCategories = true
        }
    }
    
    private func formatDuration(_ duration: TimeInterval) -> String {
        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }
}

struct AudioControlButton: View {
    let systemImage: String
    let isActive: Bool
    let backgroundColor: Color
    var size: CGFloat = 50
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: size * 0.4, weight: .medium))
                .foregroundColor(.white)
                .frame(width: size, height: size)
                .background(
                    Circle()
                        .fill(backgroundColor)
                        .shadow(color: backgroundColor.opacity(0.4), radius: 8, x: 0, y: 4)
                )
                .scaleEffect(isActive ? 1.0 : 0.95)
                .animation(.easeInOut(duration: 0.1), value: isActive)
        }
        .buttonStyle(PlainButtonStyle())
    }
}

struct User {
    let name: String
    let profileImage: String
    let themeColor: Color
    
    init(name: String, profileImage: String, themeColor: Color = .blue) {
        self.name = name
        self.profileImage = profileImage
        self.themeColor = themeColor
    }
}

#Preview {
    @Previewable @State var isCallActive = true
    return LiveView(isCallActive: .constant(true))
}
