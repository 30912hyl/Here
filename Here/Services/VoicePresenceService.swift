import FirebaseFirestore
import Foundation

/// Presence layer for the Voice tab — the "open to connect" toggle and the
/// live count of other people who currently have it on.
///
/// Deliberately stops short of matching or calling. It exists to measure
/// whether enough people are ever online at the same time to make a voice
/// feature worth building; the toggle + `othersAvailable` is all that needs.
///
/// Data: `voicePresence/{uid}` = { available: Bool, lastSeen: Timestamp }.
/// A doc counts as live only while `lastSeen` is fresh — iOS gives no
/// reliable "app was killed" hook, so a stale heartbeat is how a phone that
/// died or lost signal drops out of the count.
@MainActor
final class VoicePresenceService: ObservableObject {
    /// Heartbeat interval while the toggle is on.
    static let heartbeatInterval: TimeInterval = 30
    /// A presence doc older than this is treated as offline.
    static let staleAfter: TimeInterval = 90

    @Published private(set) var isAvailable = false
    /// Other users whose presence is on and fresh. Excludes self.
    @Published private(set) var othersAvailable = 0

    private let db = Firestore.firestore()
    private var uid = ""
    private var listener: ListenerRegistration?
    /// Runs for the whole time the listener is up: re-filters the count for
    /// staleness (so a silent phone drops out without a Firestore change) and,
    /// while the toggle is on, refreshes our own `lastSeen`.
    private var ticker: Timer?
    private var liveDocs: [String: Date] = [:]

    // MARK: - Lifecycle

    func start(uid: String) {
        guard !uid.isEmpty, uid != self.uid || listener == nil else { return }
        stop()
        self.uid = uid
        listener = db.collection("voicePresence")
            .whereField("available", isEqualTo: true)
            .addSnapshotListener { [weak self] snapshot, error in
                guard let self else { return }
                if let error {
                    print("Voice presence listener error: \(error.localizedDescription)")
                    return
                }
                var docs: [String: Date] = [:]
                for doc in snapshot?.documents ?? [] {
                    // serverTimestamp is nil for a beat until the server stamps
                    // it; treat that write as "just now" rather than stale.
                    let seen = (doc.get("lastSeen") as? Timestamp)?.dateValue() ?? Date()
                    docs[doc.documentID] = seen
                }
                self.liveDocs = docs
                self.recount()
            }
        startTicker()
    }

    func stop() {
        if isAvailable { writePresence(available: false) }
        listener?.remove()
        listener = nil
        stopTicker()
        liveDocs = [:]
        othersAvailable = 0
        isAvailable = false
        uid = ""
    }

    // MARK: - Toggle

    func setAvailable(_ on: Bool) {
        guard !uid.isEmpty else { return }
        isAvailable = on
        writePresence(available: on)
    }

    /// App left the foreground — the toggle is meant to be "while I'm here",
    /// so drop out rather than sit in the count while the phone is in a bag.
    func appDidLeaveForeground() {
        guard isAvailable else { return }
        setAvailable(false)
    }

    // MARK: - Internals

    private func writePresence(available: Bool) {
        db.collection("voicePresence").document(uid).setData([
            "available": available,
            "lastSeen": FieldValue.serverTimestamp()
        ], merge: true) { error in
            if let error {
                print("Voice presence write failed: \(error.localizedDescription)")
            }
        }
    }

    private func startTicker() {
        stopTicker()
        ticker = Timer.scheduledTimer(
            withTimeInterval: Self.heartbeatInterval,
            repeats: true
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                if self.isAvailable {
                    self.writePresence(available: true)
                }
                self.recount()
            }
        }
    }

    private func stopTicker() {
        ticker?.invalidate()
        ticker = nil
    }

    private func recount() {
        let cutoff = Date().addingTimeInterval(-Self.staleAfter)
        othersAvailable = liveDocs
            .filter { $0.key != uid && $0.value > cutoff }
            .count
    }
}
