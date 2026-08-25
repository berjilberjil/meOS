import XCTest
import SwiftUI
@testable import MyOS

/// The palette's one hard rule: a bold card is filled with a gradient and has
/// white text written on it, so the top of that gradient must clear the WCAG
/// large-text floor of 3:1. Amber, cyan and orange all failed it at full
/// strength, which is why `darkenedForWhiteText` exists — this pins it, so a
/// new hue cannot be added with a colour that is too light to write on.
final class HueTests: XCTestCase {

    func testEveryHueClearsWhiteTextContrast() {
        for hue in Hue.all {
            let start = hue.core.darkenedForWhiteText()
            XCTAssertGreaterThanOrEqual(
                start.contrastWithWhite, 3.0,
                "\(hue.id): white text on the bold gradient would fail contrast"
            )
        }
    }

    /// A hue dark enough already must not be darkened — that would flatten the
    /// difference between, say, purple and indigo.
    func testAlreadyDarkHuesAreLeftAlone() {
        let purple = Hue.purple.core
        XCTAssertEqual(purple.darkenedForWhiteText().contrastWithWhite,
                       purple.contrastWithWhite, accuracy: 0.0001)
    }

    func testHueIdentityIsStable() {
        XCTAssertEqual(Hue.named("green"), Hue.green)
        XCTAssertEqual(Hue.named("nonsense"), Hue.indigo)
    }

    /// Note and tag colours are derived from a key and must not move between
    /// launches — a note that changes colour every time you open the app is a
    /// bug, not a feature.
    func testKeyedHueIsDeterministic() {
        let first = Hue.forKey("note-1234")
        XCTAssertEqual(first, Hue.forKey("note-1234"))
        XCTAssertEqual(Hue.forKey(""), .indigo)
    }

    /// A card must be visibly different from the page it sits on.
    func testCardFillSeparatesFromCanvas() {
        for hue in Hue.all {
            let card = hue.core.mixedWithWhite(0.82).wcagLuminance
            let page = hue.core.mixedWithWhite(0.95).wcagLuminance
            XCTAssertGreaterThan(page - card, 0.03, "\(hue.id): card and canvas are too close in light mode")
        }
    }
}
