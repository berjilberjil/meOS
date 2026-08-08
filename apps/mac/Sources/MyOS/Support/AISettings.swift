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
        case .anthropic: return Palette.flame
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

    func load() async {
        do {
            async let k = api.aiKeys()
            async let r = api.aiRoutes()
            keys = try await k
            routing = try await r
            loaded = true
            loadError = nil
        } catch {
            loadError = Self.msg(error)
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
            actionError = Self.msg(error)
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
            actionError = Self.msg(error)
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

    static func msg(_ error: Error) -> String {
        (error as? APIError)?.message ?? error.localizedDescription
    }
}
