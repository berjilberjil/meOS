import XCTest
import SwiftUI
@testable import meOS

/// The palette has been rewritten four times, in both directions, and each time
/// the regression was the same: colour creeping back in as decoration. These
/// pin the rules that survived — three accents, legible text on each, and text
/// on the canvas that clears contrast in both appearances.
@MainActor
final class DesignSystemTests: XCTestCase {

    /// Three accents and no more. A fourth case here means someone added a
    /// colour; it needs a semantic reason first.
    func testThereAreExactlyThreeAccents() {
        let coloured = Accent.allCases.filter { $0 != .none }
        XCTAssertEqual(coloured.count, 3)
        XCTAssertEqual(Set(coloured.map(\.id)), ["green", "orange", "blue"])
    }

    /// The neon green and the orange are both far too light to carry white text
    /// and the light-mode blue is too dark to carry black — which is why
    /// `legibleInk` picks per appearance instead of hard-coding one answer. If
    /// someone "tidies" this to always be white, half the buttons go unreadable.
    ///
    /// Note the raw values: resolving a dynamic colour's components re-enters
    /// its provider and turned this test into a 100-second test once already.
    func testAccentInkIsLegibleOnItsAccent() {
        for accent in Accent.allCases where accent != .none {
            for scheme in [ColorScheme.light, .dark] {
                let tint = accent.raw(scheme)
                let ink = Palette.legibleInk(on: tint)
                let ratio = tint.contrast(with: ink)
                XCTAssertGreaterThanOrEqual(ratio, 4.0,
                    "\(accent.id) in \(scheme): ink is not legible on it (contrast \(ratio))")
            }
        }
    }

    /// The three accents must be told apart by *hue*, not by brightness — two
    /// colours can share a luminance and still be obviously different, which is
    /// why this compares channels rather than contrast.
    func testAccentsAreDistinct() {
        // The shipped defaults, not `Accent.raw` — that follows the live
        // appearance, and mono collapses the three hues onto one ink at
        // different opacities, which this test would read as "the same colour".
        let pairs: [(Color, Color, String)] = [
            (Palette.Dark.defaultGreen, Palette.Dark.defaultOrange, "dark green/orange"),
            (Palette.Dark.defaultGreen, Palette.Dark.defaultBlue, "dark green/blue"),
            (Palette.Dark.defaultOrange, Palette.Dark.defaultBlue, "dark orange/blue"),
            (Palette.Light.defaultGreen, Palette.Light.defaultOrange, "light green/orange"),
            (Palette.Light.defaultGreen, Palette.Light.defaultBlue, "light green/blue"),
            (Palette.Light.defaultOrange, Palette.Light.defaultBlue, "light orange/blue"),
        ]
        for (a, b, name) in pairs {
            let ca = platformComponents(a, fallback: .black)
            let cb = platformComponents(b, fallback: .black)
            let distance = abs(ca.r - cb.r) + abs(ca.g - cb.g) + abs(ca.b - cb.b)
            XCTAssertGreaterThan(distance, 0.5, "two accents are too close to tell apart (\(name))")
        }
    }

    /// Semantic aliases are the only names screens should use. This pins what
    /// each one currently means, so a change is a deliberate one-line decision
    /// rather than a drift.
    func testSemanticsMapToTheRightAccent() {
        XCTAssertEqual(Palette.success,     Palette.green)
        XCTAssertEqual(Palette.action,      Palette.green)
        XCTAssertEqual(Palette.fitness,     Palette.green)
        XCTAssertEqual(Palette.productive,  Palette.green)
        XCTAssertEqual(Palette.activity,    Palette.green)
        XCTAssertEqual(Palette.attention,   Palette.green)
        XCTAssertEqual(Palette.nutrition,   Palette.green)
        XCTAssertEqual(Palette.information, Palette.blue)
        XCTAssertEqual(Palette.events,      Palette.blue)
        // Orange is bad news and nothing else.
        XCTAssertEqual(Palette.warning,     Palette.orange)
        XCTAssertEqual(Palette.distracting, Palette.orange)
    }

    /// The semantic `Accent` constructors have to agree with the `Palette`
    /// aliases, or a section label and the value under it end up different
    /// colours — which is exactly how the app drifted orange the first time.
    func testAccentConstructorsAgreeWithPalette() {
        XCTAssertEqual(Accent.activity,    .green)
        XCTAssertEqual(Accent.nutrition,   .green)
        XCTAssertEqual(Accent.attention,   .green)
        XCTAssertEqual(Accent.productive,  .green)
        XCTAssertEqual(Accent.complete,    .green)
        XCTAssertEqual(Accent.information, .blue)
        XCTAssertEqual(Accent.warning,     .orange)
        XCTAssertEqual(Accent.distracting, .orange)
    }

    /// Today is the screen Berjil actually looks at every day, and it is the one
    /// that went orange. Nothing on it may claim orange: orange means something
    /// has gone wrong, and eating lunch has not gone wrong. Intake is loud
    /// because the number is huge, not because it is a second colour.
    func testNoTodaySectionIsOrange() {
        let orange = TodaySection.allCases.filter { $0.accent == .orange }
        XCTAssertTrue(orange.isEmpty,
                      "Today is the app's colour, white and black — found \(orange.map(\.rawValue))")
    }

    /// Spacing and radius are scales, not free numbers.
    func testScalesAreOnTheGrid() {
        let grid: Set<CGFloat> = [4, 8, 12, 16, 20, 24, 32, 40, 48]
        for v in [Space.xs, Space.sm, Space.md, Space.lg, Space.xl, Space.xxl, Space.section, Space.screen] {
            XCTAssertTrue(grid.contains(v), "\(v) is not on the spacing scale")
        }
        for v in [Radius.xs, Radius.sm, Radius.md, Radius.lg, Radius.xl] {
            XCTAssertTrue([12, 16, 24].contains(v), "\(v) is not on the radius scale")
        }
        // Gap is an alias onto Space — it must not drift off it.
        XCTAssertTrue(grid.contains(Gap.screen) && grid.contains(Gap.row) && grid.contains(Gap.tight))
    }

    /// Duration is formatted in one place, because it appears in three.
    func testDurationFormatting() {
        XCTAssertEqual(Fmt.duration(0), "0s")
        XCTAssertEqual(Fmt.duration(45), "45s")
        XCTAssertEqual(Fmt.duration(60), "1m")
        XCTAssertEqual(Fmt.duration(27 * 60), "27m")
        XCTAssertEqual(Fmt.duration(7 * 3600 + 44 * 60), "7h 44m")
        XCTAssertEqual(Fmt.duration(3 * 3600), "3h")
        XCTAssertEqual(Fmt.shortDuration(7 * 3600 + 44 * 60), "7h44")
        XCTAssertEqual(Fmt.shortDuration(5 * 60), "5m")
    }

    /// Fold scale, as numbers: display tracking stays negative, section
    /// tracking stays positive, and press answers on finger-down at ~0.97 in
    /// ~100ms. If a redesign "tidies" these, heroes stop dominating and
    /// presses stop feeling instant.
    func testTypeAndPressTokensAreFoldScale() {
        XCTAssertEqual(FluidType.displayTracking, -1.2)
        XCTAssertEqual(FluidType.sectionTracking, 0.8)
        XCTAssertEqual(FluidType.bodyTracking, 0)
        XCTAssertEqual(FluidPressStyle().scale, 0.97, accuracy: 0.001)
        XCTAssertEqual(HeroBar.clamped(-0.2), 0, accuracy: 0.0001)
        XCTAssertEqual(HeroBar.clamped(0.4), 0.4, accuracy: 0.0001)
        XCTAssertEqual(HeroBar.clamped(1.7), 1, accuracy: 0.0001)
        XCTAssertEqual(IntakeHero.remain(calories: 2_100, goal: 2_000), 0)
        XCTAssertEqual(IntakeHero.remain(calories: 1_200, goal: 2_000), 800)
        XCTAssertEqual(IntakeHero.fraction(calories: 500, goal: 0), 0, accuracy: 0.0001)
        XCTAssertEqual(IntakeHero.fraction(calories: 1_000, goal: 2_000), 0.5, accuracy: 0.0001)
    }
}
