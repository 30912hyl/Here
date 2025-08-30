//
//  ViewController.swift
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
    
    func joinChannel() {
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
}

extension AgoraAudioManager: AgoraRtcEngineDelegate {
    func rtcEngine(_ engine: AgoraRtcEngineKit, didJoinChannel channel: String, withUid uid: UInt, elapsed: Int) {
        DispatchQueue.main.async {
            self.isConnected = true
            self.localUserId = uid
            self.statusText = "Connected (You: \(uid)) - Waiting for other users"
            print("Successfully joined channel: \(channel) with UID: \(uid)")
        }
    }
    
    func rtcEngine(_ engine: AgoraRtcEngineKit, didJoinedOfUid uid: UInt, elapsed: Int) {
        DispatchQueue.main.async {
            self.remoteUserJoined = true
            self.remoteUserId = uid
            self.statusText = "Connected: You(\(self.localUserId)) ↔ Other(\(uid))"
            print("User \(uid) joined after \(elapsed) milliseconds")
        }
    }
    
    func rtcEngine(_ engine: AgoraRtcEngineKit, didOfflineOfUid uid: UInt, reason: AgoraUserOfflineReason) {
        DispatchQueue.main.async {
            if uid == self.remoteUserId {
                self.remoteUserJoined = false
                self.remoteUserId = 0
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
}
