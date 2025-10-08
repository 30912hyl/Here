//
//  WaitingRoomView.swift
//  Here
//
//  Created by Aaron Lee on 8/30/25.
//

import SwiftUI

struct WaitingRoomView: View {
    let selectedCategory: String
    @Binding var isCallActive: Bool
    @Binding var showingWaitingRoom: Bool
    @EnvironmentObject var agoraManager: AgoraAudioManager
    @State private var estimatedWaitTime = "2-3 min"
    @State private var connectionStatus: ConnectionStatus = .searching
    @State private var username = "Bala"
    @State private var rotationAngle: Double = 0
    //temporary testing
    @State private var autoPassTimer: Timer?
    @State private var timeRemaining = 5
    
    enum ConnectionStatus {
        case searching
        case connecting
        case connected
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Drag indicator
            RoundedRectangle(cornerRadius: 2)
                .fill(Color.gray.opacity(0.4))
                .frame(width: 40, height: 4)
                .padding(.top, 12)
            
            ScrollView {
                VStack(spacing: 24) {
                    // Header section
                    VStack(spacing: 8) {
                        Text(selectedCategory)
                            .font(.title2)
                            .fontWeight(.bold)
                            .foregroundColor(.white)
                        
                        Text("Waiting Room")
                            .font(.subheadline)
                            .foregroundColor(.gray)
                    }
                    .padding(.top, 16)
                    
                    // Status section with animation
                    VStack(spacing: 16) {
                        // Animated indicator
                        ZStack {
                            Circle()
                                .stroke(Color.gray.opacity(0.3), lineWidth: 3)
                                .frame(width: 80, height: 80)
                            
                            Circle()
                                .trim(from: 0.0, to: connectionStatus == .searching ? 0.3 : 1.0)
                                .stroke(
                                    connectionStatus == .connected ? Color.green : Color.blue,
                                    style: StrokeStyle(lineWidth: 3, lineCap: .round)
                                )
                                .frame(width: 80, height: 80)
                                .rotationEffect(.degrees(rotationAngle))
                                .animation(.easeInOut(duration: 0.5), value: connectionStatus)
                                .onAppear {
                                    if connectionStatus == .searching {
                                        withAnimation(.linear(duration: 2).repeatForever(autoreverses: false)) {
                                            rotationAngle = 360
                                        }
                                    }
                                }
                                .onChange(of: connectionStatus) { _, newStatus in
                                    if newStatus == .searching {
                                        withAnimation(.linear(duration: 2).repeatForever(autoreverses: false)) {
                                            rotationAngle = 360
                                        }
                                    } else {
                                        // Stop rotation immediately without animation
                                        rotationAngle = 0
                                    }
                                }
                            
                            Image(systemName: statusIcon)
                                .font(.system(size: 24, weight: .medium))
                                .foregroundColor(.white)
                        }
                        
                        // Status text
                        VStack(spacing: 8) {
                            Text(statusTitle)
                                .font(.title3)
                                .fontWeight(.semibold)
                                .foregroundColor(.white)
                                .multilineTextAlignment(.center)
                            
                            Text(statusSubtitle)
                                .font(.subheadline)
                                .foregroundColor(.gray)
                                .multilineTextAlignment(.center)
                                .lineLimit(nil)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .padding(.horizontal, 20)
                    }
                    
                    // Controls section
                    VStack(spacing: 16) {
                        // Mic test button (only when searching)
                        if connectionStatus == .searching {
                            Button(action: testMicrophone) {
                                HStack(spacing: 10) {
                                    Image(systemName: agoraManager.isMuted ? "mic.slash.fill" : "mic.fill")
                                        .font(.system(size: 16))
                                    Text(agoraManager.isMuted ? "Unmute Mic" : "Test Mic")
                                        .font(.body)
                                        .fontWeight(.medium)
                                }
                                .foregroundColor(.white)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 14)
                                .background(
                                    RoundedRectangle(cornerRadius: 12)
                                        .fill(agoraManager.isMuted ? Color.orange : Color.blue)
                                )
                            }
                            .buttonStyle(PlainButtonStyle())
                        }
                        // Show connection status for connecting/connected states
                        if connectionStatus == .connecting || connectionStatus == .connected {
                            HStack {
                                Circle()
                                    .fill(connectionStatus == .connected ? Color.green : Color.blue)
                                    .frame(width: 8, height: 8)
                                Text(connectionStatus == .connected ? "Connected!" : "Connecting...")
                                    .font(.subheadline)
                                    .foregroundColor(.white)
                            }
                            .padding(.vertical, 8)
                        }
                        // Leave button
                        Button(action: leaveWaitingRoom) {
                            Text("Leave Waiting Room")
                                .font(.body)
                                .fontWeight(.medium)
                                .foregroundColor(.white)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 14)
                                .background(
                                    RoundedRectangle(cornerRadius: 12)
                                        .fill(Color.red)
                                )
                        }
                        .buttonStyle(PlainButtonStyle())
                        .opacity(connectionStatus == .searching ? 1.0 : 0.0)
                        .disabled(connectionStatus != .searching)
                    }
                    .padding(.horizontal, 24)
                }
                .padding(.bottom, 32)
            }
        }
        .background(
            Color(red: 0.08, green: 0.08, blue: 0.12)
        )
        .presentationDetents([.height(400), .medium]) // Increased height with fallback
        .presentationDragIndicator(.hidden)
        .onAppear {
            loadUsername()
            startSearching()
            //temporary testing
            startAutoPassTimer()
        }
        .onDisappear {
            if connectionStatus == .searching {
                agoraManager.leaveChannel()
            }
            //temporary testing
            stopAutoPassTimer()
        }
        .onChange(of: agoraManager.remoteUserJoined) { _, joined in
            if joined {
                // Person found! Start connection process
                connectionStatus = .connecting
                //temporary testing
                stopAutoPassTimer()
                // Add haptic feedback for successful match
                let successFeedback = UINotificationFeedbackGenerator()
                successFeedback.notificationOccurred(.success)
                
                // Show connecting state briefly
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                    connectionStatus = .connected
                    
                    // Show connected state briefly, then transition to live call
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                        withAnimation(.easeInOut(duration: 0.3)) {
                            showingWaitingRoom = false
                            isCallActive = true
                        }
                    }
                }
            } else {
                /*// Remote user left while in waiting room, go back to searching
                connectionStatus = .searching*/
                // temporary testing BEGIN
                if connectionStatus == .searching {
                    startAutoPassTimer()
                } else {
                    connectionStatus = .searching
                    startAutoPassTimer()
                }
                // temporary testing END
            }
        }
        .onChange(of: agoraManager.isConnected) { _, connected in
            if !connected && connectionStatus != .searching {
                // Lost connection, go back to searching
                connectionStatus = .searching
                //temporary testing
                startAutoPassTimer()
            }
        }
    }
    
    // MARK: - Computed Properties
    
    private var statusIcon: String {
        switch connectionStatus {
        case .searching:
            return "magnifyingglass"
        case .connecting:
            return "antenna.radiowaves.left.and.right"
        case .connected:
            return "checkmark"
        }
    }
    
    private var statusTitle: String {
        switch connectionStatus {
        case .searching:
            return "Looking for someone..."
        case .connecting:
            return "Connecting..."
        case .connected:
            return "Connected!"
        }
    }
    
    private var statusSubtitle: String {
        switch connectionStatus {
        case .searching:
            return "Est. wait: \(estimatedWaitTime)\nWe're finding someone who shares your vibe"
        case .connecting:
            return "Found \(agoraManager.remoteUsername)!\nSetting up your conversation..."
        case .connected:
            return "Ready to talk with \(agoraManager.remoteUsername)!\nStarting call now..."
        }
    }
    
    // MARK: - Private Methods
    
    private func loadUsername() {
        if let savedUsername = UserDefaults.standard.string(forKey: "username"), !savedUsername.isEmpty {
            username = savedUsername
        }
    }
    
    private func startSearching() {
        connectionStatus = .searching
        agoraManager.joinChannel(with: username)
    }
    
    private func testMicrophone() {
        agoraManager.toggleMute()
        
        // Add haptic feedback
        let impactFeedback = UIImpactFeedbackGenerator(style: .light)
        impactFeedback.impactOccurred()
    }
    
    private func leaveWaitingRoom() {
        //temporary testing
        stopAutoPassTimer()
        
        agoraManager.leaveChannel()
        showingWaitingRoom = false
        
        // Add haptic feedback
        let impactFeedback = UIImpactFeedbackGenerator(style: .medium)
        impactFeedback.impactOccurred()
    }
    
    //temporary testing START
    private func startAutoPassTimer() {
        stopAutoPassTimer() // Clear any existing timer
        timeRemaining = 10
        
        autoPassTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
            if timeRemaining > 0 {
                timeRemaining -= 1
            } else {
                // Time's up! Auto-pass to live call
                autoPassToLiveCall()
            }
        }
    }
    
    private func stopAutoPassTimer() {
        autoPassTimer?.invalidate()
        autoPassTimer = nil
    }
    
    private func autoPassToLiveCall() {
        stopAutoPassTimer()
        
        // Simulate finding someone for the auto-pass
        connectionStatus = .connecting
        
        // Add subtle haptic feedback
        let impactFeedback = UIImpactFeedbackGenerator(style: .light)
        impactFeedback.impactOccurred()
        
        // Show connecting state briefly
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            connectionStatus = .connected
            
            // Show connected state briefly, then transition to live call
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                withAnimation(.easeInOut(duration: 0.3)) {
                    showingWaitingRoom = false
                    isCallActive = true
                }
            }
        }
    }
    //temporary testing END
}

#Preview {
    WaitingRoomView(
        selectedCategory: "Positive",
        isCallActive: .constant(false),
        showingWaitingRoom: .constant(true)
    )
    .environmentObject(AgoraAudioManager())
}
