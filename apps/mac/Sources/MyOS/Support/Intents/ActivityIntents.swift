import AppIntents
import Foundation

/// The iPhone's activity sensor, such as iOS allows one to exist.
///
/// Paired with a personal automation — Shortcuts → Automation → App → *WhatsApp*
/// → Is Opened → Run *Track App Activity* — this is how MyOS learns that an app
/// was in front of you on the phone. It writes a ping to the shared App Group
/// container and returns immediately: the intent's process cannot decrypt MyOS
/// state, and hitting the network on every app launch would be both slow and a
/// last-write-wins hazard against a single synced blob.
///
/// `openAppWhenRun` is false so the automation is silent; if it opened MyOS
/// every time you opened WhatsApp it would be unusable.
struct TrackAppActivityIntent: AppIntent {
    static var title: LocalizedStringResource = "Track App Activity"
    static var description = IntentDescription(
        "Tell MyOS that an app was opened or closed. Pair with a Shortcuts personal automation to track iPhone activity.")
    static var openAppWhenRun = false
    static var isDiscoverable = true

    @Parameter(title: "App")
    var app: String

    @Parameter(title: "State", default: .opened)
    var state: AppActivityState

    static var parameterSummary: some ParameterSummary {
        Summary("Record that \(\.$app) was \(\.$state)")
    }

    func perform() async throws -> some IntentResult {
        let name = app.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { throw ActivityIntentError.noApp }
        guard ActivityInbox.add(appName: name, kind: state == .opened ? .opened : .closed) else {
            throw ActivityIntentError.noSharedContainer
        }
        return .result()
    }
}

enum AppActivityState: String, AppEnum {
    case opened, closed

    static var typeDisplayRepresentation = TypeDisplayRepresentation(name: "App State")
    static var caseDisplayRepresentations: [AppActivityState: DisplayRepresentation] = [
        .opened: "opened",
        .closed: "closed",
    ]
}

enum ActivityIntentError: LocalizedError, CustomLocalizedStringResourceConvertible {
    case noApp
    case noSharedContainer

    var errorDescription: String? {
        switch self {
        case .noApp:
            return "No app name was given."
        case .noSharedContainer:
            return "MyOS can't reach its shared storage on this device."
        }
    }

    var localizedStringResource: LocalizedStringResource {
        LocalizedStringResource(stringLiteral: errorDescription ?? "Something went wrong.")
    }
}
