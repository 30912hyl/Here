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
    @State private var username = "Bala" // This should come from your profile data

    // Mock user data - replace with actual user data

    var currentUser: User {
        User(name: username, profileImage: "person.circle.fill", themeColor: Color.purple.opacity(0.8))
    }

    var otherUser: User {
        User(name: agoraManager.remoteUsername, profileImage: "person.circle.fill", themeColor: Color.red.opacity(0.8))
    }
    
    var body: some View {
        NavigationStack {
            GeometryReader { geometry in
                ZStack {
                    // Background gradient
                    LinearGradient(
                        gradient: Gradient(colors: [
                            Color(red: 0.1, green: 0.1, blue: 0.15),
                            Color(red: 0.05, green: 0.05, blue: 0.1)
                        ]),
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                    .ignoresSafeArea()
                    
                    if agoraManager.isCallActive {
                        VStack(spacing: 10) {
                            // Connection status
                            HStack {
                                Circle()
                                    .fill(agoraManager.isConnected ?
                                          (agoraManager.remoteUserJoined ? Color.green : Color.orange) :
                                            
                                          Color.red)
                                    .frame(width: 8, height: 8)
                                Text(agoraManager.statusText)
                                    .font(.caption)
                                    .foregroundColor(.gray)
                            }
                            .padding(.top, 5)
                            
                            // Call duration
                            Text(formatDuration(callDuration))
                                .font(.caption)
                                .foregroundColor(.gray)
                            
                            // Other user profile (top)
                            LiveUserView(
                                user: otherUser,
                                profileSize: 100,
                                posX: 0,
                                posY: 30,
                                isCurrentUser: false,
                                isSpeaking: agoraManager.remoteUserJoined
                            )
                            
                            Text(agoraManager.remoteUserJoined ?
                                 agoraManager.remoteUsername:
                                 "Waiting for someone...")
                                .font(.title2)
                                .fontWeight(.medium)
                                .foregroundColor(.white)
                                .padding(.top, 10)
                            
                            Spacer().frame(height: 20)
                            
                            // Current user profile (bottom)
                            LiveUserView(
                                user: currentUser,
                                profileSize: 100,
                                posX: 0,
                                posY: 30,
                                isCurrentUser: true,
                                isSpeaking: !agoraManager.isMuted && agoraManager.isConnected
                            )
                            
                            Text("You (\(username))")
                                .font(.title3)
                                .fontWeight(.medium)
                                .foregroundColor(.white.opacity(0.8))
                                .padding(.top, 10)
                            
                            Spacer()
                            
                            // Control buttons
                            HStack(spacing: 30) {
                                // Mute button
                                AudioControlButton(
                                    systemImage: agoraManager.isMuted ? "mic.slash.fill" : "mic.fill",
                                    isActive: !agoraManager.isMuted,
                                    backgroundColor: agoraManager.isMuted ? .red : .gray.opacity(0.3)
                                ) {
                                    agoraManager.toggleMute()
                                }
                                
                                // End call button
                                AudioControlButton(
                                    systemImage: "phone.down.fill",
                                    isActive: false,
                                    backgroundColor: .red,
                                    size: 60
                                ) {
                                    endCall()
                                }
                                
                                // Speaker button
                                AudioControlButton(
                                    systemImage: agoraManager.isSpeakerOn ? "speaker.wave.3.fill" : "speaker.wave.1.fill",
                                    isActive: agoraManager.isSpeakerOn,
                                    backgroundColor: agoraManager.isSpeakerOn ? .blue : .gray.opacity(0.3)
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
                
                // Load username from UserDefaults or ProfileManager
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
                    // Transition from waiting room to live call
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
        // Load username from UserDefaults (or your preferred storage method)
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
        // Add your end call logic here
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

struct LiveUserView: View {
    let user: User
    let profileSize: CGFloat // Profile picture size
    let posX: CGFloat // X position offset for entire box from center
    let posY: CGFloat // Y position offset for entire box from center
    let isCurrentUser: Bool
    let isSpeaking: Bool
    
    private let size: CGFloat = 100 // Fixed rectangle size
    
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // Background box with adjustable position
                RoundedRectangle(cornerRadius: 16)
                    .fill(user.themeColor)
                    .frame(width: geometry.size.width+20, height: size + 200)
                    .position(x: geometry.size.width / 2 + posX, y: geometry.size.height / 2 + posY)
                
                // Speaking indicator border
                if isSpeaking {
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(Color.green, lineWidth: 3)
                        .frame(width: geometry.size.width+25, height: size + 205)
                        .position(x: geometry.size.width / 2 + posX, y: geometry.size.height / 2 + posY)
                        .scaleEffect(isSpeaking ? 1.02 : 1.0)
                        .animation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true), value: isSpeaking)
                }
                
                // Profile image centered in the box
                Image(systemName: user.profileImage)
                    .font(.system(size: profileSize, weight: .medium))
                    .foregroundColor(.white)
                    .frame(width: profileSize + 10, height: profileSize + 10)
                    .clipShape(Circle())
                    .position(x: geometry.size.width / 2 + posX, y: geometry.size.height / 2 + posY)
            }
        }
        .frame(height: size + 140) // Match rectangle height for proper spacing
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
