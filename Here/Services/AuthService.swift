//
//  AuthService.swift
//  Here
//
//  Created by Aaron Lee on 2/28/26.
//

import FirebaseAuth
import FirebaseFirestore
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
    /// True from submitting the SMS code until the terms acceptance is saved,
    /// so nothing else (e.g. the terms-update sheet) pops up in between.
    @Published var isVerifyingPhone = false

    var isPhoneVerified: Bool { phoneNumber != nil }
    var memberSince: Date? { Auth.auth().currentUser?.metadata.creationDate }

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
                // Linking keeps the same user, so the state listener above is NOT
                // called: without this the app goes on thinking the phone is
                // unverified until it is restarted (the composer opens once, then
                // "Chat privately" asks to verify again). Found 2026-11-26 in the
                // first real sign-in with test numbers.
                apply(Auth.auth().currentUser)
                return
            } catch let error as NSError
                where error.code == AuthErrorCode.credentialAlreadyInUse.rawValue {
                // The number has an account already — become it. The failed
                // link used up the SMS code, so Firebase hands back a fresh
                // credential for exactly this; the original would be rejected.
                // The throwaway anonymous user is left behind; it owns nothing
                // that matters (reading requires no identity).
                let updated = error.userInfo["FIRAuthErrorUserInfoUpdatedCredentialKey"] as? AuthCredential
                _ = try await Auth.auth().signIn(with: updated ?? credential)
                return
            }
        }
        if let user = Auth.auth().currentUser, !user.isAnonymous {
            // Already signed in with a phone: this is the "confirm your number"
            // step before deleting the account. Re-authenticate the SAME
            // account; a different number fails instead of switching accounts.
            _ = try await user.reauthenticate(with: credential)
            return
        }
        _ = try await Auth.auth().signIn(with: credential)
    }

    /// Bump when the terms change materially: phone-verified accounts on an
    /// older version are asked to confirm again (ContentView → TermsUpdateSheet).
    /// "2026-10b" added the confirmation of being a woman.
    static let termsVersion = "2026-10b"

    /// Stores that this account confirmed being a woman and 18+ and accepted
    /// the terms (Apple requires UGC apps to have users agree to terms before
    /// posting; the attestation is what a ban for a fake identity rests on).
    func recordTermsAcceptance() async {
        guard let uid else { return }
        try? await Firestore.firestore().collection("users").document(uid).setData([
            "womanAttested": true,
            "termsVersion": Self.termsVersion,
            "termsAcceptedAt": FieldValue.serverTimestamp()
        ], merge: true)
    }

    // MARK: - Session

    /// Back to an anonymous, read-only session. Signing in with the same
    /// phone number later restores the account.
    func signOut() async {
        // Detach this phone's push token first, so a signed-out device stops
        // showing this account's message previews.
        // Wait at most 3s: offline, the delete stays queued, but it must not
        // hold the sign-out hostage until the phone reconnects.
        if let uid {
            let ref = Firestore.firestore().collection("users").document(uid)
            _ = try? await waitForWrite(atMost: 3) { done in
                ref.updateData(["fcmToken": FieldValue.delete()], completion: done)
            }
        }
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
