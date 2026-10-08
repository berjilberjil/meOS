import Foundation

// Macro Intelligence's client half. Snapshots are per-date and cached in memory
// for the session; the server keeps the durable copy and is the only thing that
// talks to FRED or the model.

extension AppState {
    /// Load a date's snapshot. Cached per date, so paging back and forth through
    /// the week costs one request each and no more.
    func loadMacro(date: String, refresh: Bool = false) async {
        if !refresh, macroCache[date] != nil {
            macro = macroCache[date]
            macroError = nil
            return
        }
        macroBusy = true
        macroError = nil
        defer { macroBusy = false }
        do {
            let snap = try await api.macro(date: date, refresh: refresh)
            macroCache[date] = snap
            macro = snap
        } catch {
            macro = macroCache[date]
            macroError = (error as? APIError)?.message ?? error.localizedDescription
        }
    }
}
