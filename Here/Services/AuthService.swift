//
//  AuthService.swift
//  Here
//
//  Created by Aaron Lee on 2/28/26.
//

import FirebaseAuth
import Foundation

/// Two tiers of identity:
///   - anonymous: everyone gets one on first launch; enough to read posts
///   - phone-verified: required to post, chat or join voice — this is what
///     gives moderation something to act on (see firestore.rules `canWrite`)
/// Linking a phone number to the anonymous user keeps the same uid, so
/// anything the person did before verifying stays attached to them.
@MainActor
final class AuthService: ObservableObject {
    @Published var uid: String?
    @Published var isSignedIn = false
    @Published var phoneNumber: String?

    var isPhoneVerified: Bool { phoneNumber != nil }

    private var stateHandle: AuthStateDidChangeListenerHandle?

    init() {
        apply(Auth.auth().currentUser)
        stateHandle = Auth.auth().addStateDidChangeListener { [weak self] _, user in
            Task { @MainActor in self?.apply(user) }
        }
    }

    private func apply(_ user: User?) {
        uid = user?.uid
        isSignedIn = user != nil
        phoneNumber = user?.phoneNumber
    }

    func signInAnonymously() async {
        guard Auth.auth().currentUser == nil else { return }
        do {
            _ = try await Auth.auth().signInAnonymously()
        } catch {
            print("Auth error: \(error.localizedDescription)")
        }
    }

    // MARK: - Phone verification

    /// Sends the SMS. Returns the verification id needed by `confirmCode`.
    /// `e164` must be a full international number, e.g. "+14155551234".
    func startPhoneVerification(_ e164: String) async throws -> String {
        try await PhoneAuthProvider.provider().verifyPhoneNumber(e164, uiDelegate: nil)
    }

    /// Links the phone to the current anonymous user. If that number already
    /// belongs to another account (a returning user on a new install), signs
    /// in as that account instead so their history comes back.
    func confirmCode(verificationID: String, code: String) async throws {
        let credential = PhoneAuthProvider.provider().credential(
            withVerificationID: verificationID, verificationCode: code)

        if let user = Auth.auth().currentUser, user.isAnonymous {
            do {
                _ = try await user.link(with: credential)
                return
            } catch let error as NSError
                where error.code == AuthErrorCode.credentialAlreadyInUse.rawValue {
                // Fall through: the number has an account already — become it.
                // The throwaway anonymous user is left behind; it owns nothing
                // that matters (reading requires no identity).
            }
        }
        _ = try await Auth.auth().signIn(with: credential)
    }

    // MARK: - Session

    /// Back to an anonymous, read-only session. Signing in with the same
    /// phone number later restores the account.
    func signOut() async {
        do {
            try Auth.auth().signOut()
        } catch {
            print("Sign out error: \(error.localizedDescription)")
        }
        await signInAnonymously()
    }

    enum DeleteAccountError: Error {
        /// Firebase requires a recent sign-in for destructive actions —
        /// the caller should re-run phone verification, then retry.
        case needsRecentLogin
    }

    /// Deletes the Firebase Auth user. Content cleanup is the caller's job.
    func deleteAccount() async throws {
        guard let user = Auth.auth().currentUser else { return }
        do {
            try await user.delete()
        } catch let error as NSError
            where error.code == AuthErrorCode.requiresRecentLogin.rawValue {
            throw DeleteAccountError.needsRecentLogin
        }
        await signInAnonymously()
    }
}
