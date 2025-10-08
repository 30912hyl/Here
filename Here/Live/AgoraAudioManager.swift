//
//  AgoraAudioManager.swift
//  Here
//
//  Created by Aaron Lee on 8/28/25.
//

import UIKit
import Foundation
import AgoraRtcKit
import AVFoundation

class AgoraAudioManager: NSObject, ObservableObject {
    let appId = "5599d5af7f7d456ca3536a9f05aac71d"
    let channelName = "sad"
    let token = "007eJxTYChSeuAjqfiWrTRiRsGSGKO9fKYL62J2Mj3edXfHnCnty44rMJiaWlqmmCammaeZp5iYmiUnGpsamyVaphmYJiYmmxumJP5/mtEQyMgg+piLlZEBAkF8ZobixBQGBgAXyB9W"
    
    var agoraKit: AgoraRtcEngineKit!
    
    @Published var isCallActive = false
    @Published var isMuted = false
    @Published var isSpeakerOn = false
    @Published var isConnected = false
    @Published var remoteUserJoined = false
    @Published var remoteUserId: UInt = 0
    @Published var localUserId: UInt = 0
    @Published var statusText = "Initializing..."
    @Published var remoteUsername = "Unknown"
    @Published var startTimer = false
    @Published var inWaitingRoom = false
    
    // Dictionary to store user ID to username mapping
    private var userIdToUsername: [UInt: String] = [:]
    private var dataStreamId: Int = 0
    private var currentUsername: String = "Bala"
    
    // Send username to all users in the channel
    private func sendUsername(_ username: String) {
        guard dataStreamId != 0 else {
            print("Data stream not ready, queuing username send")
            // Queue the username to send once stream is ready
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                self.sendUsername(username)
            }
            return
        }
        
        let usernameData = username.data(using: .utf8) ?? Data()
        let result = agoraKit.sendStreamMessage(dataStreamId, data: usernameData)
        if result == 0 {
            print("Successfully sent username: \(username)")
        } else {
            print("Failed to send username: \(username), error: \(result)")
        }
    }
    
    override init() {
        super.init()
        initializeAgoraVoiceSDK()
    }
    
    deinit {
        leaveChannel()
        AgoraRtcEngineKit.destroy()
    }
    
    func initializeAgoraVoiceSDK() {
        agoraKit = AgoraRtcEngineKit.sharedEngine(withAppId: appId, delegate: self)
        agoraKit.enableAudioVolumeIndication(250, smooth: 3, reportVad: true)
        statusText = "Ready to connect"
    }
    
    func joinChannel(with username: String = "Bala") {
        currentUsername = username
        let options = AgoraRtcChannelMediaOptions()
        options.channelProfile = .communication
        options.clientRoleType = .broadcaster
        options.publishMicrophoneTrack = true
        options.autoSubscribeAudio = true
        
        // Create data stream configuration
        let dataStreamConfig = AgoraDataStreamConfig()
        dataStreamConfig.ordered = true
        dataStreamConfig.syncWithAudio = false

        // Create data stream before joining
        var streamId: Int = 0
        let streamResult = agoraKit.createDataStream(&streamId, config: dataStreamConfig)
        if streamResult == 0 {
            dataStreamId = streamId
            print("Data stream created successfully with ID: \(streamId)")
        }
        
        let result = agoraKit.joinChannel(
            byToken: token,
            channelId: channelName,
            uid: 0,
            mediaOptions: options
        )
        
        if result == 0 {
            isCallActive = true
            inWaitingRoom = true
            statusText = "Connecting..."
            print("Joining channel with username: \(username)")
        } else {
            statusText = "Failed to join channel"
            print("Failed to join channel, error: \(result)")
        }
    }
    
    func transitionToLiveCall() {
        // This is called when transitioning from waiting room to live call
        inWaitingRoom = false
        startTimer = true
        statusText = "In call with \(remoteUsername)"
        print("Transitioned to live call with \(remoteUsername)")
    }
    
    func leaveChannel() {
        agoraKit.leaveChannel(nil)
        resetState()
    }

    private func resetState() {
        isCallActive = false
        isConnected = false
        remoteUserJoined = false
        remoteUserId = 0
        remoteUsername = "Unknown"
        userIdToUsername.removeAll()
        startTimer = false
        inWaitingRoom = false
        dataStreamId = 0
        statusText = "Disconnected"
    }
    
    func toggleMute() {
        isMuted.toggle()
        agoraKit.muteLocalAudioStream(isMuted)
        // Send updated status if we have remote users
        if remoteUserJoined {
            statusText = isMuted ? "Muted in call with \(remoteUsername)" : "In call with \(remoteUsername)"
        }
    }
    
    func toggleSpeaker() {
        isSpeakerOn.toggle()
        agoraKit.setEnableSpeakerphone(isSpeakerOn)
    }
    
    
    // Function to get display name for remote user
    private func getDisplayName(for uid: UInt) -> String {
        return userIdToUsername[uid] ?? "User \(uid)"
    }
}

extension AgoraAudioManager: AgoraRtcEngineDelegate {
    
    // Handle when user joins channel
    func rtcEngine(_ engine: AgoraRtcEngineKit, didJoinChannel channel: String, withUid uid: UInt, elapsed: Int) {
        DispatchQueue.main.async {
            self.isConnected = true
            self.localUserId = uid
            self.statusText = self.inWaitingRoom ? "Connected - Looking for someone..." : "Connected"
            print("Successfully joined channel: \(channel) with UID: \(uid)")
            // Send username after a brief delay to ensure data stream is ready
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                self.sendUsername(self.currentUsername)
            }
        }
    }
    
    // Handle when user2 joins channel
    func rtcEngine(_ engine: AgoraRtcEngineKit, didJoinedOfUid uid: UInt, elapsed: Int) {
        DispatchQueue.main.async {
            // If this is the first remote user and we're in waiting room
            if !self.remoteUserJoined {
                self.remoteUserJoined = true
                self.remoteUserId = uid
                
                // Set initial display name
                self.remoteUsername = self.getDisplayName(for: uid)
                
                if self.inWaitingRoom {
                    self.statusText = "Found someone! Connecting..."
                } else {
                    self.statusText = "Connected with \(self.remoteUsername)"
                    self.startTimer = true
                }
                
                // Send our username to the new user
                self.sendUsername(self.currentUsername)
            }
            
            print("Remote user joined: \(uid), username: \(self.getDisplayName(for: uid))")

        }
    }
    
    // Handle when user2 leaves channel
    func rtcEngine(_ engine: AgoraRtcEngineKit, didOfflineOfUid uid: UInt, reason: AgoraUserOfflineReason) {
        DispatchQueue.main.async {
            print("User \(uid) left: Reason -> \(reason)")
            
            if uid == self.remoteUserId {
                // Primary remote user left
                self.remoteUserJoined = false
                self.remoteUserId = 0
                self.remoteUsername = "Unknown"
                self.userIdToUsername.removeValue(forKey: uid)
                self.startTimer = false
                
                if self.inWaitingRoom {
                    self.statusText = "User left - Looking for someone..."
                } else {
                    self.statusText = "Call ended - User left"
                }
            } else {
                // Remove from username mapping
                self.userIdToUsername.removeValue(forKey: uid)
            }
        }
    }
    
    // Handle any error occurences
    func rtcEngine(_ engine: AgoraRtcEngineKit, didOccurError errorCode: AgoraErrorCode) {
        DispatchQueue.main.async {
            if errorCode.rawValue == 109 || errorCode.rawValue == 110 {
                // Token expired error
                self.statusText = "Token invalid/expired - Check README"
                print("Agora error \(errorCode.rawValue): \(self.statusText)")
                self.leaveChannel()
            } else {
                self.statusText = "Connection error occurred"
                print("Agora error \(errorCode.rawValue): \(self.statusText)")
            }
        }
    }
    
    // Handle incoming data stream messages (usernames)
    func rtcEngine(_ engine: AgoraRtcEngineKit, receiveStreamMessageFromUid uid: UInt, streamId: Int, data: Data) {
        if let username = String(data: data, encoding: .utf8), !username.isEmpty {
            DispatchQueue.main.async {
                print("Received username '\(username)' from user \(uid)")
                
                // Store the username mapping
                self.userIdToUsername[uid] = username
                
                // If this is our current remote user, update the display
                if uid == self.remoteUserId {
                    self.remoteUsername = username
                    
                    if self.inWaitingRoom {
                        self.statusText = "Found \(username)! Connecting..."
                    } else {
                        self.statusText = "In call with \(username)"
                    }
                }
            }
        }
    }
    
    // Handle data stream errors
    func rtcEngine(_ engine: AgoraRtcEngineKit, didOccurStreamMessageErrorFromUid uid: UInt, streamId: Int, error: Int, missed: Int, cached: Int) {
        print("Stream message error from \(uid): \(error), missed: \(missed), cached: \(cached)")
    }
}
