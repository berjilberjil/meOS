import Foundation
import SwiftUI

/// Who the in-app chat assistant is: its name, its tone, and any extra style notes
/// the user types in. Stored locally in UserDefaults — a per-device preference, not
/// synced account data — so it never touches the state-sync schema or any other
/// module. The chat widget and the Settings editor both observe this one shared
/// instance, and `AppState.sendChat` reads it when it calls the backend.
final class AgentConfig: ObservableObject {
    static let shared = AgentConfig()

    @Published var name: String   { didSet { UserDefaults.standard.set(name, forKey: Self.kName) } }
    @Published var toneRaw: String { didSet { UserDefaults.standard.set(toneRaw, forKey: Self.kTone) } }
    @Published var custom: String { didSet { UserDefaults.standard.set(custom, forKey: Self.kCustom) } }

    private static let kName   = "myos.agent.name"
    private static let kTone   = "myos.agent.tone"
    private static let kCustom = "myos.agent.custom"

    private init() {
        let d = UserDefaults.standard
        name    = Self.canonicalName(d.string(forKey: Self.kName))
        toneRaw = d.string(forKey: Self.kTone)   ?? AgentTone.blunt.rawValue
        custom  = d.string(forKey: Self.kCustom) ?? ""
    }

    var tone: AgentTone {
        get { AgentTone(rawValue: toneRaw) ?? .blunt }
        set { toneRaw = newValue.rawValue }
    }

    /// The name to show and send — never empty.
    var displayName: String {
        let t = name.trimmingCharacters(in: .whitespaces)
        return Self.canonicalName(t)
    }

    /// Every AI in the app is Catherine. The old default spelling is remapped.
    static func canonicalName(_ raw: String?) -> String {
        let t = (raw ?? "").trimmingCharacters(in: .whitespaces)
        if t.isEmpty || t.lowercased() == "cathrine" { return "Catherine" }
        return t
    }
}

/// The voice presets the user can pick for their assistant. `directive` is the exact
/// line sent to the model, so this enum is the single source of what each tone
/// means — the web side just injects whatever string it receives.
enum AgentTone: String, CaseIterable, Identifiable {
    case blunt, warm, chill, hype, professional
    var id: String { rawValue }

    var label: String {
        switch self {
        case .blunt:        return "Blunt"
        case .warm:         return "Warm"
        case .chill:        return "Chill"
        case .hype:         return "Hype"
        case .professional: return "Pro"
        }
    }

    var directive: String {
        switch self {
        case .blunt:
            return "Blunt and direct — no sugar-coating. If he's wrong, tell him straight; if he's right, confirm it and sharpen it. Push him. This is his default."
        case .warm:
            return "Warm and encouraging, but still honest. Back him up, don't flatter. Kind, not soft."
        case .chill:
            return "Chill and casual, like a close friend texting. Relaxed, a little playful, still actually useful."
        case .hype:
            return "High-energy hype. Fire him up in short, punchy lines — make him want to move, but stay grounded in the truth."
        case .professional:
            return "Calm and professional. Neutral, precise, concise. No slang, no drama."
        }
    }
}
