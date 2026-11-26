import FirebaseFirestore
import Foundation

/// Firestore's async writes only return once the server has confirmed them,
/// which never happens while the phone is offline (the write waits in the
/// local queue and goes out on reconnect). For actions where the user is
/// watching a spinner, wait for the server at most `seconds`.
///
/// Returns true when the server confirmed the write, false when it is still
/// queued after `seconds` (it will be sent once the phone is back online).
/// Throws when the server rejected it (e.g. security rules, banned number).
@MainActor
func waitForWrite(
    atMost seconds: TimeInterval,
    _ start: (@escaping (Error?) -> Void) -> Void
) async throws -> Bool {
    let once = ResumeOnce()
    return try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Bool, Error>) in
        start { error in
            DispatchQueue.main.async {
                guard !once.done else { return }
                once.done = true
                if let error {
                    cont.resume(throwing: error)
                } else {
                    cont.resume(returning: true)
                }
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds) {
            guard !once.done else { return }
            once.done = true
            cont.resume(returning: false)
        }
    }
}

/// Makes sure the continuation above is resumed exactly once. Only touched on
/// the main queue.
private final class ResumeOnce {
    var done = false
}
