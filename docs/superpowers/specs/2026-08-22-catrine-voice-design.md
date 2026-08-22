# Catrine, out loud — free live voice for the MyOS assistant

**Date:** 2026-08-22
**Status:** design, awaiting approval to plan
**Scope:** Phase 1 — voice on iPhone. Presence/continuity is a separate phase.

## Goal

Berjil holds a spoken conversation with Catrine on his iPhone: he talks, she
answers aloud, and he can cut her off mid-sentence. She stays the same Catrine —
same character, same grounding, same tools against the unlocked vault.

**Hard constraint: this costs nothing.** No subscription, no card, no usage that
can produce a bill. That constraint drove the whole design and, unusually, made
it simpler rather than worse.

## Why not ElevenLabs / OpenAI Realtime / Gemini Live

All three are per-minute paid ($0.08–0.12/min, ~$22–99/month at daily use), and
all three require shipping his audio to a company that does not already hold his
data. Rejected on cost first, privacy second.

Their one real advantage — a *cloned* voice — is given up deliberately.

## Architecture

```
iPhone mic
   │
   ▼
SpeechAnalyzer (on-device STT)  ──── audio NEVER leaves the phone
   │
   ▼  transcript
runCatrineTurn()  ──── AgentLoop, Retrieval, ContextBuilder, tools, vault
   │                   entirely unchanged from text chat
   ▼  reply text
CatrineVoice router
   │
   ├──► POST /api/voice/speak ──► Worker ──► @cf/deepgram/aura-2-en ──► audio
   │       (good voice, while the free daily allowance lasts)
   │
   └──► AVSpeechSynthesizer (Premium voice, on-device)
           (fallback: unlimited, offline, free forever)
```

Three properties worth stating plainly:

1. **Audio never leaves the device.** Only her reply *text* goes up, to be
   spoken. That is a smaller data footprint than the text chat already has.
2. **No new vendor.** Cloudflare already runs `myos-api`, D1 `myos` and R2
   `myos-media`. The Deepgram models are Cloudflare-hosted on that same account.
3. **Her brain is untouched.** `AgentLoop`'s ceilings (3 rounds / 6 tool calls /
   55s, final round tools-off), `Retrieval`, `ContextBuilder`, `MemoryExtraction`
   all run exactly as they do for text. Voice is an I/O change, not a brain
   change.

## The free budget, precisely

Workers AI gives **10,000 neurons per day at no charge, on Free and Paid plans
alike**, resetting 00:00 UTC.

`@cf/deepgram/aura-2-en` costs 1,363.64 neurons per 1,000 characters. So:

> 10,000 neurons ÷ 1.36364 neurons/char ≈ **7,333 characters/day**
> ≈ 1,200 words ≈ **8–10 minutes of Catrine talking, every day, free.**

Listening is free and unlimited regardless, because it is on-device.

**It cannot bill.** On the Workers *Free* plan, exceeding the allowance returns
HTTP 429 / error `3036` — there is no billing path. Because the account may be
on Workers *Paid* (D1/R2), the Worker additionally enforces its own hard daily
character budget and refuses before ever reaching a billable neuron. Two
independent stops.

When the budget is gone she keeps talking in the Apple voice until midnight UTC.
She never goes silent.

## Components

### 1. `Support/Voice/SpeechListener.swift` — new (shared)

Wraps on-device speech recognition behind one small interface:
`start()`, `onPartial`, `onFinalTranscript`, `onSpeechDetected`, `stop()`.

- `SpeechAnalyzer` + `SpeechTranscriber` when `#available(iOS 26, macOS 26)` —
  Apple's current model, fully on-device, ~2× faster than Whisper Large v3 Turbo.
- Falls back to `SFSpeechRecognizer` with `requiresOnDeviceRecognition = true`
  on iOS 17–25. Also free and on-device, just weaker.
- Deployment targets stay at iOS 17 / macOS 14. No bump; the gate is
  `#available`.
- `onSpeechDetected` is what powers barge-in and must fire on voice activity,
  not on a final transcript — waiting for a transcript is far too late to feel
  like an interruption.

### 2. `Support/Voice/CatrineVoice.swift` — new (shared)

The mouth, and the thing that makes "free" invisible.

- Splits her reply into sentences and speaks them **one at a time**. Aura over
  HTTP synthesises a whole string before returning, so a long reply would sit
  silent for seconds. Sentence chunking means she starts talking after the first
  clause. (Aura also supports a real-time WebSocket mode — a later upgrade, not
  needed for v1.)
- Per sentence: try `/api/voice/speak`. On `429`, any network failure, or
  airplane mode → `AVSpeechSynthesizer` with the best installed voice, preferring
  `.premium` then `.enhanced` quality. Once the server says "budget gone", stay
  on the fallback for the rest of the call rather than retrying every sentence.
- `stop()` must kill both the `AVAudioPlayer` and the synthesizer, and drop any
  queued sentences. This is the barge-in path — it has to be instant.

### 3. `POST /api/voice/speak` — new (apps/api)

- Auth: existing session (`locals.user`). No new public surface.
- Body: `{ text, speaker }`. `text` capped (~400 chars — it is one sentence).
- Budget: a `voice_budget` row per user per UTC day tracking characters spent.
  Checked and incremented in the same request. Timestamps via `nowISO()` from
  `lib/server/db.ts` — **never** SQLite `current_timestamp`, or the day
  comparison sorts wrong (this bit the state ETag before).
- Over budget → `429 { code: 'voice_budget_exhausted' }`. The client treats this
  as a normal, expected outcome, not an error to surface.
- Otherwise `env.AI.run('@cf/deepgram/aura-2-en', { text, speaker })` and return
  the audio bytes.
- Requires adding the `AI` binding to the Worker config.

### 4. `VoiceCallView.swift` — new (iOS)

- Presented as a `fullScreenCover` from `ChatWidget`. **Never** on the Today
  page — `TodayPager` keeps three pages alive and forbids work in
  `.task`/`.onAppear`.
- States: connecting → listening → thinking → speaking → ended.
- Design language: `ScreenTitle`, `Gap.screen`/`Gap.row`, `RiseIn` opacity-only,
  `knPop` critically damped. Nothing moves after it lands.
- Turns append to the current `ChatThread`, so voice and text are one
  conversation, not two histories.
- Shows the remaining good-voice budget honestly (e.g. "premium voice: 6 min
  left today") rather than silently degrading and leaving him wondering why she
  changed.

### 5. Audio session

`SoundPlayer` sets `.playback` + `.mixWithOthers` (fixed 2026-08-19 so the
ring/silent switch stops muting UI sound). A call needs `.playAndRecord` +
`.voiceChat`. Swapped on call start and **restored on every exit path**,
including error and background termination, or UI sound dies after the first
call. One helper with `defer`, not inline calls at two sites.

### 6. Configuration

- `apps/ios/Info.plist`: `NSMicrophoneUsageDescription`,
  `NSSpeechRecognitionUsageDescription`, `UIBackgroundModes` → `audio`.
- Worker: `AI` binding.
- No new dependencies. No SDK. No accounts.

## Testing

Vitest (`apps/api`):
- Budget accounting: increments, blocks at the cap, rolls over at 00:00 UTC,
  and two concurrent requests cannot both spend the last of the allowance.
- `429` response shape carries `voice_budget_exhausted`.
- Text length cap enforced.

XCTest (`apps/mac` — shared layer, so it covers iOS):
- Sentence chunker: abbreviations, decimals, ellipses, and text with no
  terminator at all.
- `CatrineVoice` falls back on 429, on network error, and stays fallen back for
  the remainder of the call.
- Audio session helper restores the prior category on success *and* on throw.

On-device (Berjil): the call itself — does the interruption feel right, does she
actually reach into the vault when asked something only a note would answer, and
is the Apple fallback voice tolerable enough to live with daily.

## Risks

1. **Aura HTTP latency.** Batch synthesis per sentence adds a round trip before
   she starts speaking. Sentence chunking hides most of it; if it still drags,
   the WebSocket real-time mode is the fix.
2. **iOS 26 availability on the phone.** If it is older, `SFSpeechRecognizer`
   carries it — worse transcription, same architecture.
3. **Mac cannot open the mic.** `apps/mac/project.yml` sets
   `ENABLE_HARDENED_RUNTIME: YES` with an empty `MyOS.entitlements`, so any mic
   request is denied. Fix is `com.apple.security.device.audio-input` +
   `NSMicrophoneUsageDescription`. Unlike the data-protection Keychain
   entitlement (`-34018`), this one works ad-hoc signed. Phase 2.
4. **The Apple fallback voice is the honest weak point.** It is clearly
   synthetic. If it turns out to be unbearable, the answer is to spend fewer
   characters on Aura (shorter spoken replies) rather than to start paying.

## Out of scope

- Mac voice (Phase 2, after the entitlement fix).
- Presence and continuity — her starting conversations, referencing last week
  unprompted. The other half of "feels like a real human"; its own spec.
- Voice input outside the chat widget (logging food by voice, etc).
- Voice cloning. Not possible for free, and not worth paying for yet.
