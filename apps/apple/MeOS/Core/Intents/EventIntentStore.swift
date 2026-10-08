import Foundation

/// Why a Siri request couldn't be served. Each case maps to one plain sentence
/// Siri reads back — see the `CustomLocalizedStringResourceConvertible`
/// conformance in `EventIntents.swift`.
enum EventIntentError: LocalizedError {
    /// No live session recorded on this device.
    case notSignedIn
    /// Session exists but the DEK isn't reachable — logged out of the vault, or
    /// the device is locked (the key is `WhenUnlockedThisDeviceOnly`).
    case locked
    /// Needed the server and couldn't reach it.
    case unreachable

    var errorDescription: String? {
        switch self {
        case .notSignedIn: return "Sign in to MeOS on this device first."
        case .locked:      return "Unlock your device and open MeOS once, then try again."
        case .unreachable: return "Couldn't reach MeOS. Try again in a moment."
        }
    }
}

/// Reads and writes events with no UI and no `AppState` — the data path Siri
/// uses while the app stays closed.
///
/// It leans on exactly the same pieces the app's instant-relaunch path uses
/// (`APIClient` cache + `Vault.unlockFromKeychain`), so a device that opens MeOS
/// without a passphrase prompt can also answer Siri without one.
struct EventIntentStore {
    private let api = APIClient()
    private let vault = Vault()

    /// Silent unlock from this device's Keychain. The crypto meta rides along in
    /// the cached blob as plaintext, so this needs no network.
    private func unlock() throws {
        guard let user = SessionDefaults.currentUsername else { throw EventIntentError.notSignedIn }
        api.vault = vault
        guard let raw = api.cachedRawState(), let meta = api.cryptoMeta(from: raw) else {
            throw EventIntentError.locked
        }
        vault.adoptMeta(meta)
        guard vault.unlockFromKeychain(username: user) else { throw EventIntentError.locked }
    }

    /// Map a transport failure onto something Siri can say.
    private func speakable(_ error: Error) -> EventIntentError {
        if let e = error as? APIError, e.status == 401 || e.status == 403 { return .notSignedIn }
        return .unreachable
    }

    /// Every event, freshest available. Falls back to the on-disk cache when the
    /// network is down so a question still gets an answer.
    func loadEvents() async throws -> [EventItem] {
        try unlock()
        if let raw = try? await api.fetchStateRaw(),
           let payload = try? api.decodePayload(fromRaw: raw) {
            return payload.events ?? []
        }
        guard let cached = api.decodeCachedPayload() else { throw EventIntentError.unreachable }
        return cached.events ?? []
    }

    /// Append one event and sync it.
    ///
    /// Deliberately refuses to write offline. State is a single last-write-wins
    /// blob, so appending to a stale cached array would silently delete anything
    /// added on another device since that cache was written.
    @discardableResult
    func addEvent(title: String, dateKey: String) async throws -> EventItem {
        try unlock()

        let raw: [String: Any]
        do { raw = try await api.fetchStateRaw() } catch { throw speakable(error) }

        var events = (try? api.decodePayload(fromRaw: raw))?.events ?? []
        var tag = EventVoice.tagID(forTitle: title)
        if let ai = try? await api.categorizeEvent(title: title, date: dateKey),
           ["travel", "family", "work", "personal", "milestone", "reminder", "other"].contains(ai.tagId) {
            tag = ai.tagId
        }
        let item = EventItem(date: dateKey, title: title, tagIDs: [tag], category: EventCategory(rawValue: tag) ?? .personal)
        events.append(item)

        do { try await api.putState(StateKey.events, events) } catch { throw speakable(error) }

        // Refresh the disk cache so the app's next cold start shows the new event
        // immediately instead of a blob that predates it.
        _ = try? await api.fetchStateRaw()
        return item
    }
}
