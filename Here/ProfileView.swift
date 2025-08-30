//
//  ProfileView.swift
//  Here
//
//  Created by Aaron Lee on 8/29/25.
//
import SwiftUI

struct ProfileView: View {
    @State private var username = "Bala"
    @State private var isEditingUsername = false
    @State private var showingImagePicker = false
    @State private var profileImage = "person.circle.fill"
    
    var body: some View {
        NavigationView {
            ZStack {
                // Background gradient matching LiveView
                LinearGradient(
                    gradient: Gradient(colors: [
                        Color(red: 0.1, green: 0.1, blue: 0.15),
                        Color(red: 0.05, green: 0.05, blue: 0.1)
                    ]),
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .ignoresSafeArea()
                
                ScrollView {
                    VStack(spacing: 30) {
                        // Profile Picture Section
                        VStack(spacing: 15) {
                            // Profile Image (like in LiveView)
                            Button(action: {
                                showingImagePicker = true
                            }) {
                                ZStack {
                                    Circle()
                                        .fill(Color.purple.opacity(0.8))
                                        .frame(width: 120, height: 120)
                                    
                                    Image(systemName: profileImage)
                                        .font(.system(size: 60, weight: .medium))
                                        .foregroundColor(.white)
                                    
                                    // Camera overlay
                                    VStack {
                                        Spacer()
                                        HStack {
                                            Spacer()
                                            Circle()
                                                .fill(Color.blue)
                                                .frame(width: 30, height: 30)
                                                .overlay(
                                                    Image(systemName: "camera.fill")
                                                        .font(.system(size: 12))
                                                        .foregroundColor(.white)
                                                )
                                        }
                                    }
                                    .frame(width: 120, height: 120)
                                }
                            }
                            .buttonStyle(PlainButtonStyle())
                            
                            Text("Tap to change photo")
                                .font(.caption)
                                .foregroundColor(.gray)
                        }
                        .padding(.top, 40)
                        
                        // Username Section
                        VStack(spacing: 15) {
                            HStack {
                                Text("Username")
                                    .font(.headline)
                                    .foregroundColor(.white)
                                Spacer()
                            }
                            
                            HStack {
                                if isEditingUsername {
                                    TextField("Username", text: $username)
                                        .textFieldStyle(RoundedBorderTextFieldStyle())
                                        .font(.title3)
                                } else {
                                    Text(username)
                                        .font(.title3)
                                        .foregroundColor(.white)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .padding(.vertical, 8)
                                }
                                
                                Button(action: {
                                    if isEditingUsername {
                                        // Save username
                                        saveUsername()
                                        isEditingUsername = false
                                        hideKeyboard()
                                    } else {
                                        // Start editing
                                        isEditingUsername = true
                                    }
                                }) {
                                    Image(systemName: isEditingUsername ? "checkmark.circle.fill" : "pencil.circle.fill")
                                        .font(.system(size: 20))
                                        .foregroundColor(isEditingUsername ? .green : .blue)
                                }
                                .buttonStyle(PlainButtonStyle())
                            }
                            
                            Divider()
                                .background(Color.gray.opacity(0.3))
                        }
                        .padding(.horizontal, 20)
                        
                        // Profile Stats Section
                        VStack(spacing: 20) {
                            HStack {
                                Text("Activity")
                                    .font(.headline)
                                    .foregroundColor(.white)
                                Spacer()
                            }
                            
                            HStack(spacing: 40) {
                                ProfileStatView(title: "Calls", value: "12")
                                ProfileStatView(title: "Friends", value: "34")
                                ProfileStatView(title: "Hours", value: "5.2")
                            }
                            
                            Divider()
                                .background(Color.gray.opacity(0.3))
                        }
                        .padding(.horizontal, 20)
                        
                        // Settings Section
                        VStack(spacing: 15) {
                            HStack {
                                Text("Settings")
                                    .font(.headline)
                                    .foregroundColor(.white)
                                Spacer()
                            }
                            
                            ProfileSettingRow(icon: "bell.fill", title: "Notifications", action: {})
                            ProfileSettingRow(icon: "lock.fill", title: "Privacy", action: {})
                            ProfileSettingRow(icon: "questionmark.circle.fill", title: "Help & Support", action: {})
                            ProfileSettingRow(icon: "info.circle.fill", title: "About", action: {})
                        }
                        .padding(.horizontal, 20)
                        
                        Spacer()
                    }
                }
            }
            .navigationTitle("Profile")
            .navigationBarTitleDisplayMode(.large)
            .preferredColorScheme(.dark)
            .onAppear {
                loadUsername()
            }
        }
        .sheet(isPresented: $showingImagePicker) {
            // Image picker placeholder
            VStack {
                Text("Image Picker")
                    .font(.title)
                    .padding()
                
                Text("Photo selection functionality will be added here")
                    .foregroundColor(.gray)
                    .padding()
                
                Button("Cancel") {
                    showingImagePicker = false
                }
                .padding()
            }
        }
    }
    private func loadUsername() {
        if let savedUsername = UserDefaults.standard.string(forKey: "username"), !savedUsername.isEmpty {
            username = savedUsername
        }
    }

    private func saveUsername() {
        UserDefaults.standard.set(username, forKey: "username")
    }
}


struct ProfileStatView: View {
    let title: String
    let value: String
    
    var body: some View {
        VStack(spacing: 5) {
            Text(value)
                .font(.title2)
                .fontWeight(.bold)
                .foregroundColor(.white)
            
            Text(title)
                .font(.caption)
                .foregroundColor(.gray)
        }
    }
}

struct ProfileSettingRow: View {
    let icon: String
    let title: String
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 15) {
                Image(systemName: icon)
                    .font(.system(size: 18))
                    .foregroundColor(.blue)
                    .frame(width: 25)
                
                Text(title)
                    .font(.body)
                    .foregroundColor(.white)
                
                Spacer()
                
                Image(systemName: "chevron.right")
                    .font(.system(size: 14))
                    .foregroundColor(.gray)
            }
            .padding(.vertical, 12)
            .padding(.horizontal, 15)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color.gray.opacity(0.1))
            )
        }
        .buttonStyle(PlainButtonStyle())
    }
}

// Extension to hide keyboard
extension View {
    func hideKeyboard() {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }
}

#Preview {
    ProfileView()
}
