# Phase A — Interaction Primitives Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add the cross-cutting interaction primitives — app-wide haptics and a slide-to-confirm control — that later phases (mood slider, chat, food/fitness) build on.

**Architecture:** A single `Haptics` enum in `Support/` (compiled into both mac + iOS) provides four feedback calls behind a platform `#if`. A `pressHaptic` view modifier fires a light tap from every shared button style, giving app-wide tap feedback in one place. A pure `SlideConfirmState` struct holds the drag→threshold logic (unit-tested), wrapped by a `SlideToConfirm` SwiftUI view — the commit-side counterpart to the existing destructive `HoldToConfirmButton`.

**Tech Stack:** Swift 5 / SwiftUI, xcodegen, xcodebuild. iOS 17 / macOS 14 deployment targets (modern `onChange(of:_:)` two-parameter closure available). Unit tests run in the `MyOSTests` mac target (`apps/mac/Tests/`).

**Spec:** `docs/superpowers/specs/2026-08-15-polish-notifications-food-fitness-design.md` (Phase A section).

## Global Constraints

- Shared code lives in `apps/mac/Sources/MyOS/Support/` (auto-compiled into iOS via `apps/ios/project.yml`). Per-platform UI stays in each target's `Views/`.
- After adding any new file under a globbed source path, run `xcodegen generate` in that app dir before building (`project.yml` globs `Sources/` and `Tests/`).
- Colors/spacing come from `Palette`, `Radius`, and `.knFast` animation (defined in `Theme.swift`). Do not hardcode theme colors.
- Deferred by design (DRY — the phases that rewrite these code paths add the haptic there, not here): **mood-slider** selection haptic → Phase B4; **chat send/reply** haptic → Phase B7 (rewrites `sendChat` for streaming); **fitness delete → hold-to-delete** and **commit → slide-to-confirm** adoption → Phase D. Phase A ships the primitives + universal button/tab haptics only.
- Build verification per platform:
  - mac: `cd apps/mac && xcodegen generate && xcodebuild -project MyOS.xcodeproj -scheme MyOS -configuration Debug -derivedDataPath build build`
  - iOS: `cd apps/ios && xcodegen generate && xcodebuild -project MyOS.xcodeproj -scheme MyOS -configuration Debug -sdk iphonesimulator -destination 'generic/platform=iOS Simulator' build`
  - tests: `cd apps/mac && xcodebuild -project MyOS.xcodeproj -scheme MyOS -configuration Debug -derivedDataPath build test`

---

### Task 1: Haptics helper

**Files:**
- Create: `apps/mac/Sources/MyOS/Support/Haptics.swift`

**Interfaces:**
- Produces: `enum Haptics` with static `tap()`, `selection()`, `success()`, `warning()` — all `@MainActor`-safe, no return value.

- [ ] **Step 1: Create the helper**

```swift
import SwiftUI
#if os(macOS)
import AppKit
#else
import UIKit
#endif

/// Thin cross-platform haptic feedback shim. On macOS this fires only on a
/// Force Touch trackpad (a no-op otherwise); on iOS it uses the UIKit feedback
/// generators. Call from the main actor.
enum Haptics {
    /// A light tap — generic button press.
    static func tap() {
        #if os(macOS)
        NSHapticFeedbackManager.defaultPerformer.perform(.generic, performanceTime: .now)
        #else
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        #endif
    }

    /// A selection tick — a value stepped (slider stop, segment / tab change).
    static func selection() {
        #if os(macOS)
        NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
        #else
        UISelectionFeedbackGenerator().selectionChanged()
        #endif
    }

    /// Success — a commit landed (send, confirm, log).
    static func success() {
        #if os(macOS)
        NSHapticFeedbackManager.defaultPerformer.perform(.levelChange, performanceTime: .now)
        #else
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        #endif
    }

    /// Warning — a destructive action confirmed (delete).
    static func warning() {
        #if os(macOS)
        NSHapticFeedbackManager.defaultPerformer.perform(.levelChange, performanceTime: .now)
        #else
        UINotificationFeedbackGenerator().notificationOccurred(.warning)
        #endif
    }
}
```

- [ ] **Step 2: Regenerate + build mac** (`xcodegen generate && xcodebuild … build`). Expected: `** BUILD SUCCEEDED **` (haptics is a thin platform shim with no observable return — verified by compile, not a unit test).

- [ ] **Step 3: Commit**

```bash
git add apps/mac/Sources/MyOS/Support/Haptics.swift
git commit -m "feat(haptics): cross-platform haptic feedback helper"
```

---

### Task 2: Slide-to-confirm (pure model, TDD) + view

**Files:**
- Create: `apps/mac/Tests/InteractionTests.swift`
- Modify: `apps/mac/Sources/MyOS/Views/SharedComponents.swift` (append after the hold-to-confirm section, ~line 190)

**Interfaces:**
- Produces: `struct SlideConfirmState { var threshold: CGFloat; var progress: CGFloat {get}; var confirmed: Bool {get}; mutating func drag(translationX:width:); mutating func end() -> Bool; mutating func reset() }` and `struct SlideToConfirm: View`.

- [ ] **Step 1: Write the failing test**

```swift
import XCTest
@testable import MyOS

final class InteractionTests: XCTestCase {
    func testDragClampsProgressBetweenZeroAndOne() {
        var s = SlideConfirmState()
        s.drag(translationX: -20, width: 100)
        XCTAssertEqual(s.progress, 0, accuracy: 0.001)
        s.drag(translationX: 50, width: 100)
        XCTAssertEqual(s.progress, 0.5, accuracy: 0.001)
        s.drag(translationX: 300, width: 100)
        XCTAssertEqual(s.progress, 1, accuracy: 0.001)
    }

    func testEndBelowThresholdDoesNotFireAndResets() {
        var s = SlideConfirmState(threshold: 0.85)
        s.drag(translationX: 50, width: 100) // 0.5 < 0.85
        XCTAssertFalse(s.end())
        XCTAssertEqual(s.progress, 0, accuracy: 0.001)
        XCTAssertFalse(s.confirmed)
    }

    func testEndAtThresholdFiresExactlyOnce() {
        var s = SlideConfirmState(threshold: 0.85)
        s.drag(translationX: 90, width: 100) // 0.9 >= 0.85
        XCTAssertTrue(s.end())      // fires
        XCTAssertTrue(s.confirmed)
        XCTAssertEqual(s.progress, 1, accuracy: 0.001)
        XCTAssertFalse(s.end())     // does not fire again
    }

    func testResetClearsConfirmedState() {
        var s = SlideConfirmState(threshold: 0.85)
        s.drag(translationX: 90, width: 100)
        _ = s.end()
        s.reset()
        XCTAssertFalse(s.confirmed)
        XCTAssertEqual(s.progress, 0, accuracy: 0.001)
    }
}
```

- [ ] **Step 2: Run the test, verify it fails**

Run: `cd apps/mac && xcodegen generate && xcodebuild -project MyOS.xcodeproj -scheme MyOS -configuration Debug -derivedDataPath build test`
Expected: FAIL — `SlideConfirmState` is undefined (compile error).

- [ ] **Step 3: Implement the model + view** (append to `SharedComponents.swift`)

```swift
// MARK: - Slide to confirm (commit actions)

/// Pure drag→threshold logic for a slide-to-confirm control, split from the
/// view so it is unit-testable without SwiftUI.
struct SlideConfirmState {
    var threshold: CGFloat = 0.85
    private(set) var progress: CGFloat = 0
    private(set) var confirmed = false

    /// Update progress from the current drag translation and available travel.
    mutating func drag(translationX: CGFloat, width: CGFloat) {
        guard !confirmed else { return }
        progress = min(1, max(0, translationX / max(width, 1)))
    }

    /// End the drag. Returns `true` exactly once — when released at/after the
    /// threshold. Below threshold it snaps progress back to 0.
    mutating func end() -> Bool {
        guard !confirmed else { progress = 1; return false }
        if progress >= threshold { confirmed = true; progress = 1; return true }
        progress = 0
        return false
    }

    mutating func reset() { progress = 0; confirmed = false }
}

/// A drag-to-commit control: drag the thumb to the end to fire `action`; snaps
/// back if released early; fires a success haptic on commit. The commit-side
/// counterpart to `HoldToConfirmButton` (which is destructive hold-to-delete).
struct SlideToConfirm: View {
    var label: String = "Slide to confirm"
    var tint: Color = Palette.brand
    let action: () -> Void

    @State private var state = SlideConfirmState()
    private let thumb: CGFloat = 44

    var body: some View {
        GeometryReader { geo in
            let travel = max(1, geo.size.width - thumb)
            ZStack(alignment: .leading) {
                Capsule().fill(tint.opacity(0.16))
                Text(state.confirmed ? "Confirmed" : label)
                    .font(.system(size: 13, weight: .heavy, design: .rounded))
                    .foregroundStyle(tint)
                    .frame(maxWidth: .infinity)
                Capsule().fill(tint)
                    .frame(width: thumb + state.progress * travel)
                Image(systemName: state.confirmed ? "checkmark" : "arrow.right")
                    .font(.system(size: 14, weight: .heavy))
                    .foregroundStyle(Palette.bg)
                    .frame(width: thumb, height: thumb)
                    .offset(x: state.progress * travel)
            }
            .contentShape(Capsule())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { v in
                        withAnimation(.knFast) { state.drag(translationX: v.translation.width, width: travel) }
                    }
                    .onEnded { _ in
                        let fired = state.end()
                        if fired { Haptics.success(); action() }
                        else { withAnimation(.knFast) { } }
                    }
            )
            .onHover { h in cursor(h) }
        }
        .frame(height: thumb)
    }
}
```

- [ ] **Step 4: Run the test, verify it passes**

Run: `cd apps/mac && xcodebuild -project MyOS.xcodeproj -scheme MyOS -configuration Debug -derivedDataPath build test`
Expected: PASS (all 4 `InteractionTests`).

- [ ] **Step 5: Build iOS** (the view is shared): iOS build command from Global Constraints. Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 6: Commit**

```bash
git add apps/mac/Sources/MyOS/Views/SharedComponents.swift apps/mac/Tests/InteractionTests.swift
git commit -m "feat(ui): SlideToConfirm control + tested progress model"
```

---

### Task 3: App-wide button-press haptic

**Files:**
- Modify: `apps/mac/Sources/MyOS/Support/Theme.swift` (button styles at lines 245–406)

**Interfaces:**
- Consumes: `Haptics.tap()` (Task 1).
- Produces: `View.pressHaptic(_:)` modifier; every shared button style fires a tap on press-down.

- [ ] **Step 1: Add the modifier** (place just above `KPrimaryButtonStyle`, ~line 244)

```swift
extension View {
    /// Fire a light tap when a button style transitions into the pressed state.
    func pressHaptic(_ pressed: Bool) -> some View {
        onChange(of: pressed) { _, now in if now { Haptics.tap() } }
    }
}
```

- [ ] **Step 2: Apply it in each button style.** In `KPrimaryButtonStyle.Inner.body`, `KSecondaryButtonStyle.Inner.body`, and `KSoftButtonStyle.Inner.body` (each has `let pressed = configuration.isPressed`), add `.pressHaptic(pressed)` to the end of the label modifier chain (after `.onHover { … }`). In `KGhostButtonStyle.Inner.body` and `KIconButtonStyle.Inner.body` (which use `configuration.isPressed` inline), add `.pressHaptic(configuration.isPressed)`. In `KPressStyle.makeBody`, add `.pressHaptic(configuration.isPressed)` after the `.animation(...)` line.

Example (KPrimaryButtonStyle.Inner, after `.onHover { h in hover = h; cursor(h) }`):

```swift
                .onHover { h in hover = h; cursor(h) }
                .pressHaptic(pressed)
```

- [ ] **Step 3: Build mac + iOS.** Expected: `** BUILD SUCCEEDED **` on both.

- [ ] **Step 4: Commit**

```bash
git add apps/mac/Sources/MyOS/Support/Theme.swift
git commit -m "feat(haptics): light tap on every shared button press"
```

---

### Task 4: Tab-switch haptic

**Files:**
- Modify: `apps/mac/Sources/MyOS/Views/MainView.swift`
- Modify: `apps/ios/Sources/MyOS/Views/MainView.swift`

**Interfaces:**
- Consumes: `Haptics.selection()` (Task 1). The selected tab is `@State private var tab: NavTab` in both files.

- [ ] **Step 1: mac** — add to the root view of `MainView.body` (the outer container), a change observer:

```swift
        .onChange(of: tab) { _, _ in Haptics.selection() }
```

- [ ] **Step 2: iOS** — add the same `.onChange(of: tab) { _, _ in Haptics.selection() }` to the `TabView`'s enclosing `ZStack` in `apps/ios/.../MainView.swift`.

- [ ] **Step 3: Build mac + iOS.** Expected: `** BUILD SUCCEEDED **` on both. Manual check: switching tabs produces a selection tick on a trackpad (mac) / device (iOS).

- [ ] **Step 4: Commit**

```bash
git add apps/mac/Sources/MyOS/Views/MainView.swift apps/ios/Sources/MyOS/Views/MainView.swift
git commit -m "feat(haptics): selection tick on tab switch"
```

---

## Self-Review

- **Spec coverage (Phase A):** A1 Haptics helper → Task 1. A2 app-wide wiring → Task 3 (button styles) + Task 4 (tab switch); mood/chat moments intentionally deferred (see Global Constraints). A3 slide-to-confirm + testable model → Task 2. A-testing (slide-confirm unit test) → Task 2 Step 1.
- **Placeholder scan:** none — every step has concrete code or an exact command.
- **Type consistency:** `SlideConfirmState.drag(translationX:width:)`, `.end() -> Bool`, `.reset()`, `.progress`, `.confirmed`, `.threshold` match between the test (Task 2 Step 1) and the implementation (Step 3). `Haptics.tap/selection/success/warning` match between Task 1 and its consumers (Tasks 2–4).
