import Foundation

// MARK: - AppState integration

extension AppState {
    /// Today's record for the challenge (never nil — an untouched day reads as
    /// an empty record, which is what the checklist shows).
    var sixPackToday: SixPackDayRecord {
        sixPack.record(on: todayKey)
    }

    /// One push for the whole module, after the local value has changed.
    func updateSixPack(_ transform: (inout SixPackState) -> Void) {
        var next = sixPack
        transform(&next)
        guard next != sixPack else { return }
        sixPack = next
        push(StateKey.sixPack, next)
    }

    func toggleSixPackItem(_ item: SixPackItem) {
        updateSixPack { $0.toggle(item, on: todayKey) }
    }

    func logSixPackWeight(_ kg: Double) {
        updateSixPack { $0.setWeight(kg, on: todayKey) }
    }
}
