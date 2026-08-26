import Foundation
import SwiftUI

/// The AI providers the app can use. Keys are added, validated and stored server-side
/// (encrypted); the mac app only ever handles the raw key at the moment of entry.
enum AIProvider: String, CaseIterable, Identifiable {
    case gemini, anthropic, openai
    var id: String { rawValue }

    var label: String {
        switch self {
        case .gemini:    return "Gemini"
        case .anthropic: return "Claude"
        case .openai:    return "OpenAI"
        }
    }
    var accent: Color {
        switch self {
        case .gemini:    return Palette.blue
        case .anthropic: return Palette.activity
        case .openai:    return Palette.green
        }
    }
    var keyPlaceholder: String {
        switch self {
        case .gemini:    return "AIza… or AQ.…"
        case .anthropic: return "sk-ant-…"
        case .openai:    return "sk-…"
        }
    }
    var getKeyURL: URL? {
        switch self {
        case .gemini:    return URL(string: "https://aistudio.google.com/apikey")
        case .anthropic: return URL(string: "https://console.anthropic.com/settings/keys")
        case .openai:    return URL(string: "https://platform.openai.com/api-keys")
        }
    }
}

/// The AI "uses" in the app that can each be routed to a different key + model.
/// `default` (nil feature) covers anything not explicitly routed.
enum AIFeature: String, CaseIterable, Identifiable {
    case chat, analysis, vision, parse, suggest, plan, news
    var id: String { rawValue }

    var label: String {
        switch self {
        case .chat:     return "Chat"
        case .analysis: return "Analysis & advice"
        case .vision:   return "Screenshot reading"
        case .parse:    return "Quick logging"
        case .suggest:  return "Today suggestions"
        case .plan:     return "Plan generation"
        case .news:     return "News"
        }
    }
    /// News needs Google Search grounding — Gemini only.
    var geminiOnly: Bool { self == .news }
    var note: String? { geminiOnly ? "Gemini only — uses Google Search" : nil }
}

/// Loads and mutates the user's AI keys + per-feature routing through the backend.
/// A device-local view over server state, so it works across devices automatically.
@MainActor
final class AISettingsStore: ObservableObject {
    static let shared = AISettingsStore()
    private let api = APIClient()

    @Published var keys: [APIClient.AIKeyDTO] = []
    @Published var routing = APIClient.AIRouting()
    @Published var loaded = false
    @Published var loadError: String?
    @Published var busy = false
    @Published var actionError: String?

    var enabledKeys: [APIClient.AIKeyDTO] { keys.filter { $0.enabled && !$0.models.isEmpty } }

    func loadIfNeeded() async { if !loaded { await load() } }

    /// Forget everything about the account that just signed out.
    ///
    /// This is a process-lifetime singleton and `loadIfNeeded` short-circuits on
    /// `loaded`, so without this the next person to sign in on the same Mac
    /// opened Settings → AI providers and saw the previous user's key labels,
    /// masked prefixes, model lists and feature routing — and any toggle they
    /// flipped fired against the previous user's key ids.
    func reset() {
        keys = []
        routing = APIClient.AIRouting()
        loaded = false
        loadError = nil
        busy = false
        actionError = nil
    }

    func load() async {
        do {
            async let k = api.aiKeys()
            async let r = api.aiRoutes()
            keys = try await k
            routing = try await r
            loaded = true
            loadError = nil
        } catch {
            loadError = Self.msg(error, .loading)
        }
    }

    @discardableResult
    func addKey(provider: AIProvider, label: String, key: String) async -> Bool {
        busy = true; actionError = nil
        defer { busy = false }
        do {
            let added = try await api.aiAddKey(provider: provider.rawValue, label: label, key: key)
            keys.append(added)
            return true
        } catch {
            actionError = Self.msg(error, .checking)
            return false
        }
    }

    func setEnabled(_ key: APIClient.AIKeyDTO, _ on: Bool) async {
        actionError = nil
        do { replace(try await api.aiUpdateKey(id: key.id, enabled: on)) }
        catch { actionError = Self.msg(error) }
    }

    func rename(_ key: APIClient.AIKeyDTO, to label: String) async {
        actionError = nil
        do { replace(try await api.aiUpdateKey(id: key.id, label: label)) }
        catch { actionError = Self.msg(error) }
    }

    func recheck(_ key: APIClient.AIKeyDTO) async {
        busy = true; actionError = nil
        defer { busy = false }
        do {
            let models = try await api.aiCheckKey(id: key.id)
            if let i = keys.firstIndex(where: { $0.id == key.id }) { keys[i].models = models }
        } catch {
            actionError = Self.msg(error, .checking)
        }
    }

    func delete(_ key: APIClient.AIKeyDTO) async {
        actionError = nil
        do {
            try await api.aiDeleteKey(id: key.id)
            keys.removeAll { $0.id == key.id }
            await pruneRoutes(removing: key.id)
        } catch {
            actionError = Self.msg(error)
        }
    }

    /// Route one feature (or the default when `feature` is nil) to a key+model, or
    /// clear it (ref = nil) to fall back to the default / server env.
    func setRoute(_ feature: AIFeature?, to ref: APIClient.AIRouteRef?) async {
        var r = routing
        if let feature {
            var f = r.features ?? [:]
            if let ref { f[feature.rawValue] = ref } else { f.removeValue(forKey: feature.rawValue) }
            r.features = f
        } else {
            r.defaultRoute = ref
        }
        routing = r
        actionError = nil
        do { try await api.aiPutRoutes(r) } catch { actionError = Self.msg(error) }
    }

    func route(for feature: AIFeature?) -> APIClient.AIRouteRef? {
        if let feature { return routing.features?[feature.rawValue] }
        return routing.defaultRoute
    }

    // MARK: - Helpers

    private func replace(_ key: APIClient.AIKeyDTO) {
        if let i = keys.firstIndex(where: { $0.id == key.id }) { keys[i] = key }
    }

    private func pruneRoutes(removing keyId: Int) async {
        var r = routing
        var changed = false
        if r.defaultRoute?.keyId == keyId { r.defaultRoute = nil; changed = true }
        if var f = r.features {
            for (k, v) in f where v.keyId == keyId { f.removeValue(forKey: k); changed = true }
            r.features = f
        }
        if changed {
            routing = r
            try? await api.aiPutRoutes(r)
        }
    }

    /// What the person was trying to do — so the message can say something
    /// about *that* rather than about the failure's internals.
    enum Doing {
        case loading   // reading saved keys and routes back
        case checking  // validating a key with its provider
        case saving    // anything else this store writes
    }

    /// Turns an error into a sentence someone can act on.
    ///
    /// This used to end in `error.localizedDescription`, which for a
    /// `DecodingError` is "The data couldn't be read because it isn't in the
    /// correct format." That sentence sat in the middle of the AI keys setup
    /// screen: it describes our JSON parser, tells the reader nothing they can
    /// do, and reads like a crash. Framework prose never reaches the UI now.
    static func msg(_ error: Error, _ doing: Doing = .saving) -> String {
        // The server writes its messages for people — always prefer them.
        if let api = error as? APIError, !api.message.isEmpty { return api.message }

        if let url = error as? URLError {
            switch url.code {
            case .notConnectedToInternet, .dataNotAllowed:
                return "No internet connection."
            case .timedOut:
                return "The server didn't respond. Try again."
            default:
                return "Couldn't reach MyOS. Check your connection."
            }
        }

        switch doing {
        case .loading:  return "Couldn't load your AI settings. Try again."
        case .checking: return "Couldn't validate this key. Check the key and try again."
        case .saving:   return "That didn't save. Try again."
        }
    }
}
