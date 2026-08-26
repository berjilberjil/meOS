import XCTest
import SwiftUI
@testable import MyOS

/// The appearance system re-skins the whole app from one screen. The thing that
/// must not break while it does is meaning: a warning has to keep looking like a
/// warning whatever colour the rest of the app has become.
final class AppearanceTests: XCTestCase {

    /// `Palette` holds the live appearance in a global, so every test here has
    /// to put it back or it leaks into the design-system tests.
    override func tearDown() {
        Palette.apply(AppearanceSettings())
        super.tearDown()
    }

    // MARK: Defaults

    func testShippedDefaultIsTheGreenPreset() {
        Palette.apply(AppearanceSettings())
        XCTAssertEqual(Palette.accentRaw(.primary, dark: true), Palette.Dark.defaultGreen)
        XCTAssertEqual(Palette.accentRaw(.primary, dark: false), Palette.Light.defaultGreen)
    }

    // MARK: Presets

    func testAPresetChangesThePrimaryAndNothingElse() {
        Palette.apply(AppearanceSettings().applying(.purple))
        XCTAssertEqual(Palette.accentRaw(.primary, dark: true), Color(hex: ThemePreset.purple.dark))
        // The two that carry meaning are deliberately NOT derived from it.
        XCTAssertEqual(Palette.accentRaw(.warning, dark: true), Palette.Dark.defaultOrange)
        XCTAssertEqual(Palette.accentRaw(.info, dark: true), Palette.Dark.defaultBlue)
    }

    func testEveryPresetShipsBothAppearances() {
        for preset in ThemePreset.all {
            XCTAssertNotEqual(preset.light, preset.dark,
                              "\(preset.name) uses one value for both appearances — a neon that works on black is unreadable on white")
        }
    }

    func testPresetIdsAreUnique() {
        XCTAssertEqual(Set(ThemePreset.all.map(\.id)).count, ThemePreset.all.count)
    }

    // MARK: Mono

    /// Mono is not "grey everything" — the three meanings still have to be told
    /// apart, so they become three steps of the one ink.
    func testMonoKeepsTheThreeMeaningsDistinct() {
        Palette.apply(AppearanceSettings().applying(.mono))
        let primary = Palette.accentRaw(.primary, dark: true)
        let warning = Palette.accentRaw(.warning, dark: true)
        let info = Palette.accentRaw(.info, dark: true)
        XCTAssertNotEqual(primary, warning)
        XCTAssertNotEqual(primary, info)
        XCTAssertNotEqual(warning, info)
    }

    func testMonoFlipsWithTheAppearance() {
        Palette.apply(AppearanceSettings().applying(.mono))
        XCTAssertEqual(Palette.accentRaw(.primary, dark: true), Color.white)
        XCTAssertEqual(Palette.accentRaw(.primary, dark: false), Color.black)
    }

    /// Choosing a colour after mono has to actually leave mono.
    func testPickingAColourClearsMono() {
        var s = AppearanceSettings().applying(.mono)
        XCTAssertTrue(s.mono)
        s = s.applying(.teal)
        XCTAssertFalse(s.mono)
        XCTAssertEqual(s.presetID, "teal")
    }

    // MARK: Data colours

    /// Event tags and belonging tints are colours out of Berjil's own data, not
    /// out of the palette. An Events tab full of green, blue, amber and purple
    /// chips is not a monochrome app however black the canvas behind it is —
    /// this is the mapping that fixes that, and it must not touch the stored
    /// hex, only what gets drawn.
    func testMonoMapsDataColoursToInk() {
        Palette.apply(AppearanceSettings())
        XCTAssertEqual(Palette.dataTint(0x58CC02), Color(hex: 0x58CC02),
                       "outside mono a data colour is itself")

        Palette.apply(AppearanceSettings().applying(.mono))
        XCTAssertNotEqual(Palette.dataTint(0x58CC02), Color(hex: 0x58CC02))
    }

    /// A set of distinct hues has to stay a set of distinct greys, or every tag
    /// in Events becomes the same chip.
    func testMonoKeepsDistinctHuesDistinct() {
        Palette.apply(AppearanceSettings().applying(.mono))
        let tags: [UInt32] = [0x58CC02, 0x1CB0F6, 0xFF9600, 0xFFC800, 0xCE82FF]
        let mapped = tags.map { Palette.dataTint($0) }
        XCTAssertEqual(Set(mapped).count, tags.count,
                       "two tags collapsed onto the same grey")
    }

    /// Even the darkest tag has to stay visible against the canvas.
    func testMonoNeverMapsToInvisible() {
        Palette.apply(AppearanceSettings().applying(.mono))
        XCTAssertNotEqual(Palette.dataTint(0x000000), Color.clear)
        XCTAssertNotEqual(Palette.dataTint(0x000000), Palette.dataTint(0xFFFFFF))
    }

    // MARK: Text size

    /// The Mac's "default" is deliberately a step above the phone's — that is
    /// the whole fix for "the macOS app feels tiny".
    func testDefaultTextSizeIsLargerOnTheMac() {
        let standard = AppearanceSettings.TextSize.standard.dynamicTypeSize
        #if os(macOS)
        XCTAssertEqual(standard, .xLarge)
        #else
        XCTAssertEqual(standard, .large)
        #endif
    }

    func testTextSizeStepsAreMonotonic() {
        let sizes = AppearanceSettings.TextSize.allCases.map(\.dynamicTypeSize)
        for (smaller, bigger) in zip(sizes, sizes.dropFirst()) {
            XCTAssertLessThan(smaller, bigger, "the size steps are out of order")
        }
    }

    func testTextSizeSurvivesARoundTrip() throws {
        var s = AppearanceSettings()
        s.textSize = .huge
        let back = try JSONDecoder().decode(AppearanceSettings.self, from: JSONEncoder().encode(s))
        XCTAssertEqual(back.textSize, .huge)
    }

    // MARK: Persistence

    /// A field added later must not stop an older synced payload decoding —
    /// otherwise one device upgrading breaks the other.
    func testOlderPayloadDecodesToDefaults() throws {
        let json = Data(#"{"presetID":"blue","primaryLight":11,"primaryDark":22}"#.utf8)
        let decoded = try JSONDecoder().decode(AppearanceSettings.self, from: json)
        XCTAssertEqual(decoded.presetID, "blue")
        XCTAssertEqual(decoded.cardStyle, .flat)
        XCTAssertFalse(decoded.mono)
    }

    func testRoundTrips() throws {
        var s = AppearanceSettings().applying(.pink)
        s.cardStyle = .gradient
        let back = try JSONDecoder().decode(AppearanceSettings.self, from: JSONEncoder().encode(s))
        XCTAssertEqual(back, s)
    }

    // MARK: The custom picker's colour maths

    func testDarkenAndLightenMoveTowardsTheRightEnd() {
        XCTAssertEqual(Color.darkened(0xFFFFFF, by: 1.0), 0x000000)
        XCTAssertEqual(Color.lightened(0x000000, by: 1.0), 0xFFFFFF)
        XCTAssertEqual(Color.darkened(0x808080, by: 0.0), 0x808080)
    }

    func testDerivedPartnerStaysInRange() {
        for hex: UInt32 in [0x000000, 0xFFFFFF, 0x39FF14, 0x123456] {
            let dark = Color.lightened(hex, by: 0.42)
            let light = Color.darkened(hex, by: 0.42)
            for value in [dark, light] {
                XCTAssertLessThanOrEqual(value, 0xFFFFFF)
            }
        }
    }
}

/// Five reminders that all sound the same are five reminders you ignore.
final class ReminderSoundTests: XCTestCase {

    /// A reminder saved before sounds existed must still load.
    func testReminderWithoutASoundKeyDecodes() throws {
        let json = Data(#"{"id":"lunch","label":"Lunch","body":"eat","hour":12,"minute":30,"enabled":true}"#.utf8)
        let r = try JSONDecoder().decode(Reminder.self, from: json)
        XCTAssertEqual(r.sound, .standard)
        XCTAssertEqual(r.hour, 12)
    }

    /// A sound chosen on the Mac and synced to a phone that has never heard of
    /// it must fall back — never fall silent by accident.
    func testMacOnlySoundsResolveSafely() {
        #if os(macOS)
        XCTAssertEqual(ReminderSound.sosumi.resolved, .sosumi)
        #else
        XCTAssertEqual(ReminderSound.sosumi.resolved, .standard)
        #endif
        XCTAssertEqual(ReminderSound.silent.resolved, .silent)
    }

    func testSilentIsActuallySilent() {
        XCTAssertNil(ReminderSound.silent.notificationSound)
        XCTAssertNotNil(ReminderSound.standard.notificationSound)
    }

    func testEveryOfferedSoundIsAvailableOnThisPlatform() {
        for choice in ReminderSound.available {
            XCTAssertEqual(choice.resolved, choice,
                           "\(choice.label) is offered here but resolves to something else")
        }
    }

    /// Changing a reminder's time or switch must not quietly reset its sound.
    func testMergeKeepsTheChosenSound() {
        var saved = ReminderDefaults.all()
        saved[1].sound = .glass
        saved[1].hour = 9
        let merged = ReminderDefaults.merged(saved: saved)
        XCTAssertEqual(merged[1].sound, .glass)
        XCTAssertEqual(merged[1].hour, 9)
    }
}
