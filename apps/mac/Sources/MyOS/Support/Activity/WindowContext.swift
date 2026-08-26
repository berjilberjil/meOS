import Foundation
#if os(macOS)
import AppKit
import ApplicationServices
#endif

/// What is actually in front of you, one level below the app.
///
/// `NSWorkspace` says "Google Chrome", which is not an answer — Chrome is where
/// the work happens *and* where the day leaks, and MyOS cannot tell those apart
/// from the app name. Accessibility can: the frontmost window's title, and for a
/// browser the address bar, which is the difference between "Chrome 2h" and
/// "github.com 1h / youtube.com 40m".
///
/// The line this holds: MyOS reads the *title bar and the domain*, never the
/// page, never the path, never a keystroke. A URL is truncated to its host
/// before it is stored, so a private document's address is a domain and nothing
/// more, and titles can be switched off entirely in Settings.
struct WindowContext: Equatable, Hashable {
    /// The frontmost window's title, cleaned of the app's own name.
    var title: String?
    /// The host of the page in front, for browsers. Never a path.
    var site: String?

    static let none = WindowContext()
    var isEmpty: Bool { title == nil && site == nil }
}

/// The pure half — parsing, not reading. Lives outside the `#if` so it compiles
/// on iOS and can be pinned by tests without a window on screen.
enum WindowSense {

    /// Browsers, where the address bar is the real subject of the session.
    static let browserIds: Set<String> = [
        "com.google.Chrome", "com.google.Chrome.canary", "com.apple.Safari",
        "com.apple.SafariTechnologyPreview", "company.thebrowser.Browser",
        "company.thebrowser.dia", "org.mozilla.firefox", "com.microsoft.edgemac",
        "com.brave.Browser", "com.operasoftware.Opera", "com.vivaldi.Vivaldi",
    ]

    static func isBrowser(bundleId: String?, appName: String) -> Bool {
        if let bundleId, browserIds.contains(bundleId) { return true }
        let n = appName.lowercased()
        return ["chrome", "safari", "firefox", "edge", "brave", "arc", "vivaldi", "opera", "dia"]
            .contains { n == $0 || n.hasPrefix($0 + " ") }
    }

    /// Turn whatever the address bar is showing into a bare host.
    ///
    /// The address bar is a *text field*: half the time it holds a URL, and the
    /// other half it holds whatever is being typed into it. Anything that is not
    /// unambiguously an address is rejected rather than guessed at, because a
    /// half-typed search term stored as a "site" is worse than no site at all.
    static func host(fromAddressBar raw: String?) -> String? {
        guard var s = raw?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
              !s.isEmpty, s.count <= 2048 else { return nil }

        // Internal pages are not places you spent time on the web.
        for scheme in ["chrome://", "about:", "safari-resource:", "arc://", "edge://", "brave://", "file://"]
        where s.hasPrefix(scheme) { return nil }

        var hadScheme = false
        for scheme in ["https://", "http://"] where s.hasPrefix(scheme) {
            s = String(s.dropFirst(scheme.count)); hadScheme = true
        }
        // A space means a search box, not an address — unless it was pasted in
        // with a scheme, in which case the space is trailing junk.
        if s.contains(" ") {
            guard hadScheme, let first = s.split(separator: " ").first else { return nil }
            s = String(first)
        }
        s = s.components(separatedBy: CharacterSet(charactersIn: "/?#")).first ?? s
        if let at = s.lastIndex(of: "@") { s = String(s[s.index(after: at)...]) }  // user:pass@host
        s = s.components(separatedBy: ":").first ?? s                              // port
        if s.hasPrefix("www.") { s = String(s.dropFirst(4)) }
        guard !s.isEmpty, s.count <= 253 else { return nil }

        let labels = s.split(separator: ".", omittingEmptySubsequences: false)
        guard labels.count >= 2, let tld = labels.last, tld.count >= 2,
              tld.allSatisfy({ $0.isLetter }),
              labels.allSatisfy({ !$0.isEmpty && $0.allSatisfy { $0.isLetter || $0.isNumber || $0 == "-" } })
        else { return nil }
        return s
    }

    /// Carry a browser's last known site across a moment when it cannot be read.
    ///
    /// An address bar with nothing address-shaped in it is almost always one
    /// being typed into, not a page without a URL — so clearing the site there
    /// would split one stretch of browsing into three: the site, a nameless
    /// "Google Chrome" while the words go in, and then the next site.
    static func settling(_ fresh: WindowContext, after previous: WindowContext,
                         isBrowser: Bool) -> WindowContext {
        guard isBrowser, fresh.site == nil, let held = previous.site else { return fresh }
        var out = fresh
        out.site = held
        return out
    }

    /// Strip the app's own name off its window title. "Revamp Finance Page -
    /// Google Chrome – Berjil" is a page called "Revamp Finance Page"; the rest
    /// is chrome, in both senses.
    static func cleanTitle(_ raw: String?, appName: String) -> String? {
        guard var s = raw?.trimmingCharacters(in: .whitespacesAndNewlines), !s.isEmpty else { return nil }

        // Chrome appends " – <profile>" after its own name, so cut at the name
        // rather than trying to match the tail.
        for marker in [" - Google Chrome", " – Google Chrome", " - Chromium", " — Google Chrome"] {
            if let r = s.range(of: marker) { s = String(s[s.startIndex..<r.lowerBound]) }
        }
        for separator in [" - ", " – ", " — ", " | "] {
            let suffix = separator + appName
            if s.lowercased().hasSuffix(suffix.lowercased()) { s = String(s.dropLast(suffix.count)) }
        }
        s = s.trimmingCharacters(in: .whitespacesAndNewlines)
        // A title that is only the app's name says nothing the app column does
        // not already say.
        guard !s.isEmpty, s.caseInsensitiveCompare(appName) != .orderedSame else { return nil }
        if s.count > 120 { s = String(s.prefix(120)).trimmingCharacters(in: .whitespaces) + "…" }
        return s
    }
}

#if os(macOS)

/// The Accessibility permission, as a thing the UI can ask about.
///
/// This is the one permission MyOS asks for, and it is worth being blunt about
/// why: without it the day reads "Chrome 2h", with it the day reads "github.com
/// 1h, youtube.com 40m". Tracking still works without it — it just cannot tell
/// those two apart.
@MainActor
enum AXAccess {
    static var isTrusted: Bool { AXIsProcessTrusted() }

    /// Ask, with the system prompt. Returns the state as it is *now* — macOS
    /// grants asynchronously, after the user acts in System Settings.
    @discardableResult
    static func request() -> Bool {
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        return AXIsProcessTrustedWithOptions([key: true] as CFDictionary)
    }

    static func openSettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")
        else { return }
        NSWorkspace.shared.open(url)
    }
}

/// Reads the frontmost window through Accessibility.
///
/// Two rules keep this from being felt: every AX call is given a hard 200ms
/// messaging timeout, so a busy app can never stall the sensor's tick, and the
/// browser's address bar element is cached per process — finding it is a tree
/// walk, reading it afterwards is one call.
@MainActor
enum WindowProbe {

    /// How deep the hunt for an address bar goes, and how many nodes it may
    /// touch. A browser's accessibility tree contains the whole page; this
    /// deliberately never reaches it — `AXWebArea` is a hard stop.
    ///
    /// Nine, because Chrome's omnibox is measured at depth **seven**
    /// (`window/0/1/0/0/0/3/1`, reached after ~20 nodes) and a browser that
    /// buries it one group deeper should not silently fall back to a row called
    /// "Google Chrome". Six looked generous and found nothing at all.
    private static let maxDepth = 9
    private static let maxNodes = 400
    private static let messagingTimeout: Float = 0.2

    private static var addressBars: [pid_t: AXUIElement] = [:]

    static func forget(pid: pid_t) { addressBars[pid] = nil }
    static func forgetAll() { addressBars.removeAll() }

    /// Read what is in front. `titles` off means the window title is never even
    /// requested — for a browser the address bar is still read, because a domain
    /// is not a document name.
    static func read(pid: pid_t, bundleId: String?, appName: String, titles: Bool) -> WindowContext {
        guard AXIsProcessTrusted() else { return .none }
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, messagingTimeout)
        guard let window = element(app, kAXFocusedWindowAttribute) ?? element(app, kAXMainWindowAttribute)
        else { return .none }

        var out = WindowContext()
        if titles {
            out.title = WindowSense.cleanTitle(string(window, kAXTitleAttribute), appName: appName)
        }
        if WindowSense.isBrowser(bundleId: bundleId, appName: appName) {
            out.site = site(pid: pid, window: window)
        }
        return out
    }

    // MARK: - Address bar

    private static func site(pid: pid_t, window: AXUIElement) -> String? {
        if let cached = addressBars[pid], let host = read(addressBar: cached) { return host }
        addressBars[pid] = nil
        var nodes = 0
        guard let field = findAddressBar(window, depth: 0, nodes: &nodes) else { return nil }
        addressBars[pid] = field
        return read(addressBar: field)
    }

    /// Nothing is read while the address bar has keyboard focus: that is a
    /// half-typed search, not where you are.
    private static func read(addressBar field: AXUIElement) -> String? {
        if let focused = attribute(field, kAXFocusedAttribute) as? Bool, focused { return nil }
        return WindowSense.host(fromAddressBar: string(field, kAXValueAttribute))
    }

    private static func findAddressBar(_ el: AXUIElement, depth: Int, nodes: inout Int) -> AXUIElement? {
        guard depth <= maxDepth, nodes < maxNodes else { return nil }
        nodes += 1
        if string(el, kAXRoleAttribute) == kAXTextFieldRole as String {
            let described = ((string(el, kAXDescriptionAttribute) ?? "") + " "
                             + (string(el, kAXTitleAttribute) ?? "")).lowercased()
            if described.contains("address") || described.contains("url") { return el }
            // Arc and friends label it differently; accept a field that already
            // holds something shaped like an address.
            if WindowSense.host(fromAddressBar: string(el, kAXValueAttribute)) != nil { return el }
        }
        // The address bar lives in the toolbar, never inside the web content.
        if string(el, kAXRoleAttribute) == "AXWebArea" { return nil }
        for child in children(el) {
            if let hit = findAddressBar(child, depth: depth + 1, nodes: &nodes) { return hit }
        }
        return nil
    }

    // MARK: - AX plumbing

    private static func attribute(_ el: AXUIElement, _ name: String) -> Any? {
        var out: CFTypeRef?
        guard AXUIElementCopyAttributeValue(el, name as CFString, &out) == .success else { return nil }
        return out
    }

    private static func string(_ el: AXUIElement, _ name: String) -> String? {
        attribute(el, name) as? String
    }

    private static func element(_ el: AXUIElement, _ name: String) -> AXUIElement? {
        guard let value = attribute(el, name), CFGetTypeID(value as CFTypeRef) == AXUIElementGetTypeID()
        else { return nil }
        return (value as! AXUIElement)
    }

    private static func children(_ el: AXUIElement) -> [AXUIElement] {
        (attribute(el, kAXChildrenAttribute) as? [AXUIElement]) ?? []
    }
}

#endif
