//
//  AuthService.swift
//  Here
//
//  Created by Aaron Lee on 2/28/26.
//


import FirebaseAuth
import Foundation

@MainActor
final class AuthService: ObservableObject {
    @Published var uid: String?
    @Published var isSignedIn = false
    
    init() {
        if let user = Auth.auth().currentUser {
            self.uid = user.uid
            self.isSignedIn = true
        }
    }
    
    func signInAnonymously() async {
        guard Auth.auth().currentUser == nil else { return }
        
        do {
            let result = try await Auth.auth().signInAnonymously()
            self.uid = result.user.uid
            self.isSignedIn = true
            print("Signed in with UID: \(result.user.uid)")
        } catch {
            print("Auth error: \(error)")
        }
    }
}
