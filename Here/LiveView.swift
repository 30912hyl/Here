//
//  LiveView.swift
//  Here
//
//  Created by Aaron Lee on 8/1/25.
//

import SwiftUI

struct LiveView: View {
    @Binding var isCallActive: Bool
    @State private var isMuted = false
    @State private var isSpeakerOn = false
    @State private var callDuration: TimeInterval = 0
    @State private var timer: Timer?
    @State private var internalCallActive = true // Internal state for call UI
    @State private var showingCategories = false
    
    // Mock user data - replace with actual user data
    let currentUser = User(name: "Bala", profileImage: "person.circle.fill", themeColor: Color.purple.opacity(0.8))
    let otherUser = User(name: "A a", profileImage: "person.circle.fill", themeColor: Color.red.opacity(0.8))
        
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
                    
                    if internalCallActive {
                        VStack(spacing: 10) { // Reduced from 40 to bring rectangles closer
                            // Call duration
                            Text(formatDuration(callDuration))
                                .font(.caption)
                                .foregroundColor(.gray)
                                .padding(.top, 5)
                            
                            // Other user profile (top)
                            LiveUserView(
                                user: otherUser,
                                profileSize: 100, // Adjustable profile picture size
                                posX: 0, // X offset from center
                                posY: 30, // Y offset from center
                                isCurrentUser: false,
                                isSpeaking: false
                            )
                            
                            Text(otherUser.name)
                                .font(.title2)
                                .fontWeight(.medium)
                                .foregroundColor(.white)
                                .padding(.top, 10)
                            
                            Spacer().frame(height: 20) // Small spacer between rectangles
                            
                            // Current user profile (bottom)
                            LiveUserView(
                                user: currentUser,
                                profileSize: 100, // Different profile size for current user
                                posX: 0, // X offset from center
                                posY: 30, // Y offset from center
                                isCurrentUser: true,
                                isSpeaking: !isMuted
                            )
                            
                            Text(currentUser.name)
                                .font(.title3)
                                .fontWeight(.medium)
                                .foregroundColor(.white.opacity(0.8))
                                .padding(.top, 10)
                            
                            Spacer()
                            
                            // Control buttons
                            HStack(spacing: 30) {
                                // Mute button
                                AudioControlButton(
                                    systemImage: isMuted ? "mic.slash.fill" : "mic.fill",
                                    isActive: !isMuted,
                                    backgroundColor: isMuted ? .red : .gray.opacity(0.3)
                                ) {
                                    isMuted.toggle()
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
                                    systemImage: isSpeakerOn ? "speaker.wave.3.fill" : "speaker.wave.1.fill",
                                    isActive: isSpeakerOn,
                                    backgroundColor: isSpeakerOn ? .blue : .gray.opacity(0.3)
                                ) {
                                    isSpeakerOn.toggle()
                                }
                            }
                            .padding(.bottom, 40)
                        }
                        .padding(.horizontal, 30)
                    }
                }
            }
            .toolbar(internalCallActive ? .hidden : .visible, for: .tabBar)
            .navigationDestination(isPresented: $showingCategories) {
                CategoryView(isCallActive: $isCallActive)
            }
            .onAppear {
                if isCallActive {
                    startCallTimer()
                }
            }
            .onDisappear {
                stopCallTimer()
            }
            .onChange(of: isCallActive) { _, newValue in
                if newValue {
                    // Starting a new call
                    internalCallActive = true
                    startCallTimer()
                    showingCategories = false
                } else {
                    // Call ended
                    stopCallTimer()
                }
            }
        }
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
        internalCallActive = false
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
    @State var isCallActive = true
    return LiveView(isCallActive: .constant(true))
}
