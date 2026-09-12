import SwiftUI

/// Narrow high-frequency UI stores.
///
/// `AppState` is one `ObservableObject`: any `@Published` change rebuilds
/// every view that observes it (both shells, every Today page, the chat
/// overlay). These stores own the ticks that used to broadcast through
/// `AppState.objectWillChange`, so only the view that shows a value observes
/// it:
///
/// - `LiveActivityStore` — the Mac sensor's live reading (app switch + 20s
///   re-emit). Observed by `ActivityIntelligenceCard` only.
/// - `ChatUIStore` — Catherine's busy dot / pending prompt / error.
///   Observed by `ChatWidget` (and `VoiceCallView` via the `AppState` proxy).
/// - `SuggestUIStore` — Today's "what to do now" fetch. Observed by the
///   suggestions card and the chat briefing, so thinking in chat does not
///   rebuild Today and refreshing suggestions does not rebuild the shell.
/// - `NewsUIStore` — Today's news fetch. Observed by the news card only.
/// - `ModuleBusyStore` — one flag per module fetch. Observed by that
///   module's screen only; the shell and Today never subscribe.
///
/// `AppState` keeps computed proxies with the same names so existing call
/// sites (coordinator, voice, sync guards) keep compiling — but a proxy
/// assignment never fires `AppState.objectWillChange`.
@MainActor
final class LiveActivityStore: ObservableObject {
    static let shared = LiveActivityStore()
    private init() {}
    @Published var event: ActivityEvent?
}

@MainActor
final class ChatUIStore: ObservableObject {
    static let shared = ChatUIStore()
    private init() {}
    @Published var busy = false
    @Published var pendingPrompt: String?
    @Published var chatError: String?
}

@MainActor
final class SuggestUIStore: ObservableObject {
    static let shared = SuggestUIStore()
    private init() {}
    @Published var result: SuggestResult?
    @Published var busy = false
    @Published var error: String?
}

@MainActor
final class NewsUIStore: ObservableObject {
    static let shared = NewsUIStore()
    private init() {}
    @Published var result: NewsResult?
    @Published var busy = false
    @Published var error: String?
}

@MainActor
final class ModuleBusyStore: ObservableObject {
    static let shared = ModuleBusyStore()
    private init() {}
    @Published var fold = false
    @Published var macro = false
    @Published var image = false
    @Published var weekly = false
    @Published var plan = false
    @Published var quickLog = false
}
