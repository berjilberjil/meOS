# MyOS for Mac — the rebuild

The old Mac app (`apps/mac`) had a shell and a skin from an earlier era. This
target is the whole Mac app rewritten for the redesign the iOS app shipped:
balanced white canvas, one accent, hairlines instead of shadows, springs over
eases, screens that arrive by fading.

Nothing in `apps/mac/Sources/MyOS/Support` was touched — that logic layer is
compiled by the iOS app too. The old Mac UI files still sit in
`apps/mac/Sources/MyOS/Views`; this target simply does not compile them. Delete
them in a cleanup pass once this app is your daily driver.

## Build

```sh
cd apps/mac2
xcodegen generate
open MyOS.xcodeproj    # scheme: MyOS
```

## What is in Sources/

- `MyOSApp.swift` — app entry. First launch pins Light (balanced white).
- `WhiteTheme.swift` — the new Mac chrome: tab set, launch defaults.
- `MainView.swift` — the new shell: sidebar + per-tab NavigationStacks, the
  chat widget, notification routes, sync hooks. Same wiring as the iOS shell.
- `TodayPager.swift`, `TodayReorderEditor.swift` — ports of the iOS day pager.
- `NotesView.swift`, `NoteBlockEditor.swift` — the iOS notes experience,
  adapted to the Mac (context menus instead of swipes, ShareLink instead of
  the iOS share sheet, NSImage where the phone used UIImage).
- `EventsView.swift`, `EventMediaViewer.swift` — the iOS events/memory log,
  media viewer in a sheet instead of a full-screen cover.
- `VoiceCallView.swift` — the assistant voice loop, mic via the same
  shared SpeechListener stack.
- `BodyPhotosCard.swift` — the body-photos card and gallery, save-to-Photos
  becomes a save panel.
- `SettingsView.swift` — the iOS settings screen, plain sheets instead of
  detents.
