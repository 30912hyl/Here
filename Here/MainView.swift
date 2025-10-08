//
//  MainView.swift
//  Here
//
//  Created by Aaron Lee on 7/30/25.
//

import SwiftUI
import CoreData

struct PostView: View {
    var body: some View {
        Text("Posts")
            .font(.largeTitle)
            .padding()
    }
}

struct MessageView: View {
    var body: some View {
        Text("Messages")
            .font(.largeTitle)
            .padding()
    }
}

struct MainView: View {
    @StateObject private var agoraManager = AgoraAudioManager()
    @State private var cameraStarted = false
    @State private var selectedTab = 0
    
    var body: some View {
        TabView(selection: $selectedTab) {
            CategoryView(isCallActive: $cameraStarted)
                .environmentObject(agoraManager)
                .tabItem {
                    Label("Live", systemImage: "video.circle")
                }
                .tag(0)
            
            PostView()
                .tabItem {
                    Label("Posts", systemImage: "house")
                }
                .tag(1)

            MessageView()
                .tabItem {
                    Label("Messages", systemImage: "bubble.left.and.bubble.right")
                }
                .tag(2)

            ProfileView()
                .tabItem {
                    Label("Profile", systemImage: "person")
                }
                .tag(3)
        }
        .fullScreenCover(isPresented: $cameraStarted) {
            LiveView(isCallActive: $cameraStarted)
                .environmentObject(agoraManager)
        }
        .onChange(of: selectedTab) { oldTab, newTab in
            if newTab != 0 {
                // Stop call when not in Live tab
                cameraStarted = false
            }
        }
    }
}

#Preview {
    MainView()
}



