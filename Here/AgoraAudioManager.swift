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
    let token = "007eJxTYGC82bV2736Fg1Xd/Y0NgjMORfIoPBf48+eAd21luYSKIrcCg6mppWWKaWKaeZp5iompWXKisamxWaJlmoFpYmKyuWGKTOymjIZARoY9JacYGRkgEMRnZihOTGFgAAAEXB5y"
    
    var agoraKit: AgoraRtcEngineKit!
    
    @Published var isCallActive = false
    @Published var isMuted = false
    @Published var isSpeakerOn = false
    @Published var isConnected = false
    @Published var remoteUserJoined = false
    @Published var remoteUserId: UInt = 0
    @Published var localUserId: UInt = 0
    @Published var statusText = "Initializing..."
    @Published var remoteUsername = "A a"
    // Dictionary to store user ID to username mapping
    private var userIdToUsername: [UInt: String] = [:]
    private var dataStreamId: Int = 0
    
    // Send username to all users in the channel
    private func sendUsername(_ username: String) {
        guard dataStreamId != 0 else {
            print("Data stream not ready, cannot send username")
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
        statusText = "Ready to connect"
    }
    
    func joinChannel(with username: String = "Bala") {
        let options = AgoraRtcChannelMediaOptions()
        options.channelProfile = .communication
        options.clientRoleType = .broadcaster
        options.publishMicrophoneTrack = true
        options.autoSubscribeAudio = true
        
        
        let result = agoraKit.joinChannel(
            byToken: token,
            channelId: channelName,
            uid: 0,
            mediaOptions: options
        )
        
        if result == 0 {
            isCallActive = true
            statusText = "Connecting..."
            
            // Create data stream for username exchange after joining
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                let dataStreamConfig = AgoraDataStreamConfig()
                dataStreamConfig.ordered = true
                dataStreamConfig.syncWithAudio = false
                
                var streamId: Int = 0
                let result = self.agoraKit.createDataStream(&streamId, config: dataStreamConfig)
                if result == 0 {
                    self.dataStreamId = streamId
                    self.sendUsername(username)
                }
            }
        } else {
            statusText = "Failed to join channel"
        }
    }
    
    func leaveChannel() {
        agoraKit.leaveChannel(nil)
        isCallActive = false
        isConnected = false
        remoteUserJoined = false
        remoteUserId = 0
        remoteUsername = "A a"
        userIdToUsername.removeAll()
        
        statusText = "Disconnected"
    }
    
    func toggleMute() {
        isMuted.toggle()
        agoraKit.muteLocalAudioStream(isMuted)
    }
    
    func toggleSpeaker() {
        isSpeakerOn.toggle()
        agoraKit.setEnableSpeakerphone(isSpeakerOn)
    }
    
    
    // Function to simulate receiving username from remote user
    // In a real implementation, you'd use Agora's data stream or custom signaling
    private func updateRemoteUsername(for uid: UInt) {
        // This is a placeholder - in a real app you'd:
        // 1. Use Agora's data stream to exchange usernames
        // 2. Use a backend service to map UIDs to usernames
        // 3. Use custom signaling
        userIdToUsername[uid] = "A a"
        remoteUsername = "A a"
    }
}

extension AgoraAudioManager: AgoraRtcEngineDelegate {
    func rtcEngine(_ engine: AgoraRtcEngineKit, didJoinChannel channel: String, withUid uid: UInt, elapsed: Int) {
        DispatchQueue.main.async {
            self.isConnected = true
            self.localUserId = uid
            self.statusText = "Connected - Waiting for other users"
            print("Successfully joined channel: \(channel) with UID: \(uid)")
        }
    }
    
    func rtcEngine(_ engine: AgoraRtcEngineKit, didJoinedOfUid uid: UInt, elapsed: Int) {
        DispatchQueue.main.async {
            self.remoteUserJoined = true
            self.remoteUserId = uid
            self.updateRemoteUsername(for: uid)
            self.statusText = "Connected with \(self.remoteUsername)"
            print("User \(uid) joined after \(elapsed) milliseconds")
            
            // Send our username again when someone new joins
            if let currentUsername = UserDefaults.standard.string(forKey: "username"), !currentUsername.isEmpty {
                self.sendUsername(currentUsername)
            } else {
                self.sendUsername("Bala")
            }
        }
    }
    
    func rtcEngine(_ engine: AgoraRtcEngineKit, didOfflineOfUid uid: UInt, reason: AgoraUserOfflineReason) {
        DispatchQueue.main.async {
            if uid == self.remoteUserId {
                self.remoteUserJoined = false
                self.remoteUserId = 0
                self.remoteUsername = "Anonymous"
                self.userIdToUsername.removeValue(forKey: uid)
                self.statusText = "User left - Waiting for other users"
            }
            print("User \(uid) left: Reason -> \(reason)")
        }
    }
    
    func rtcEngine(_ engine: AgoraRtcEngineKit, didOccurError errorCode: AgoraErrorCode) {
        DispatchQueue.main.async {
            self.statusText = "Connection error occurred"
            print("Agora error occurred: \(errorCode.rawValue)")
        }
    }
    
    // Handle incoming data stream messages (usernames)
    func rtcEngine(_ engine: AgoraRtcEngineKit, receiveStreamMessageFromUid uid: UInt, streamId: Int, data: Data) {
        if let username = String(data: data, encoding: .utf8) {
            DispatchQueue.main.async {
                self.userIdToUsername[uid] = username
                if uid == self.remoteUserId {
                    self.remoteUsername = username
                    self.statusText = "Connected with \(username)"
                }
                print("Received username '\(username)' from user \(uid)")
            }
        }
    }
    
    // Handle data stream creation
    func rtcEngine(_ engine: AgoraRtcEngineKit, didCreateDataStream streamId: Int) {
        dataStreamId = streamId
        print("Data stream created with ID: \(streamId)")
        // Send username immediately after data stream is created
        if let currentUsername = UserDefaults.standard.string(forKey: "username"), !currentUsername.isEmpty {
            sendUsername(currentUsername)
        } else {
            sendUsername("Bala")
        }
    }
}
