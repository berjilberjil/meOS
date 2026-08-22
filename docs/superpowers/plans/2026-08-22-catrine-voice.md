# Catrine Voice Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Berjil can hold a spoken conversation with Catrine on his iPhone — she listens on-device, thinks with her existing brain, and answers aloud — at zero cost.

**Architecture:** On-device speech recognition produces a transcript, the existing `runCatrineTurn()` answers it unchanged, and the reply is spoken sentence-by-sentence via Deepgram Aura on Cloudflare Workers AI, falling back to `AVSpeechSynthesizer` when the free daily allowance is spent. Audio never leaves the device; only reply text goes up.

**Tech Stack:** Swift 5.9 / SwiftUI (iOS 17 target, `#available` gate to iOS 26 for `SpeechAnalyzer`), SvelteKit on Cloudflare Workers, D1, Workers AI (`@cf/deepgram/aura-2-en`), Vitest, XCTest.

**Spec:** `docs/superpowers/specs/2026-08-22-catrine-voice-design.md`

## Global Constraints

- **This must never cost money.** Two independent stops: Cloudflare's 10,000 neuron/day free allocation, and a Worker-side hard cap of **7,000 characters per UTC day** per user.
- Deployment targets stay **iOS 17.0 / macOS 14.0**. Newer APIs are reached with `#available`, never a target bump.
- Shared code goes in `apps/mac/Sources/MyOS/Support/` — that whole directory is compiled into the iOS target too. iOS-only views go in `apps/ios/Sources/MyOS/Views/`.
- All server timestamps come from `nowISO()` in `src/lib/server/db.ts`. **Never** SQLite `current_timestamp` — `YYYY-MM-DD HH:MM:SS` does not sort against `YYYY-MM-DDTHH:MM:SS.sssZ`.
- Design language: `ScreenTitle`, `Gap.screen` (18) / `Gap.row` (12) / `Gap.tight` (8), `.knRise(i)` (opacity only), `knPop` (critically damped). Nothing moves after it lands.
- The call UI is a `fullScreenCover`. **Never** put voice work on the Today page — `TodayPager` keeps three pages alive and forbids work in `.task`/`.onAppear`.
- Branch: `feat/catrine-voice` off `main`. Conventional commits. Commit identity `Berjil Jacob <berjiljacob@gmail.com>`.
- `apps/api` has vitest installed but **zero test files today** — Task 1 creates the first one.

---

### Task 0: Branch

**Files:** none

- [ ] **Step 1: Create the branch**

```bash
cd /Users/berjilskcript/Documents/Personal/MyOS
git checkout main && git pull --ff-only
git checkout -b feat/catrine-voice
```

- [ ] **Step 2: Commit the spec** (written during design, still untracked)

```bash
git add docs/superpowers/specs/2026-08-22-catrine-voice-design.md docs/superpowers/plans/2026-08-22-catrine-voice.md
git commit -m "docs(voice): spec and plan for free on-device Catrine voice"
```

---

### Task 1: Voice budget arithmetic

The pure part of "this can never bill you". No D1, no network — just the two decisions.

**Files:**
- Create: `apps/api/src/lib/server/voiceBudget.ts`
- Test: `apps/api/src/lib/server/voiceBudget.test.ts`

**Interfaces:**
- Consumes: nothing
- Produces:
  - `VOICE_DAILY_CHAR_CAP: number` (7000)
  - `utcDayKey(iso: string): string` — `'2026-08-22'`
  - `budgetDecision(used: number, request: number, cap?: number): { allowed: boolean; remaining: number }`

- [ ] **Step 1: Write the failing test**

Create `apps/api/src/lib/server/voiceBudget.test.ts`:

```ts
import { describe, expect, it } from 'vitest';
import { VOICE_DAILY_CHAR_CAP, budgetDecision, utcDayKey } from './voiceBudget';

describe('utcDayKey', () => {
  it('takes the UTC calendar day, not the local one', () => {
    expect(utcDayKey('2026-08-22T00:15:00.000Z')).toBe('2026-08-22');
    expect(utcDayKey('2026-08-22T23:59:59.999Z')).toBe('2026-08-22');
    expect(utcDayKey('2026-08-23T00:00:00.000Z')).toBe('2026-08-23');
  });

  it('rolls at midnight UTC even when IST is already tomorrow', () => {
    // 05:00 IST on the 23rd is 23:30 UTC on the 22nd — still the 22nd's budget.
    expect(utcDayKey('2026-08-22T23:30:00.000Z')).toBe('2026-08-22');
  });
});

describe('budgetDecision', () => {
  it('allows a request that fits', () => {
    expect(budgetDecision(0, 100)).toEqual({ allowed: true, remaining: VOICE_DAILY_CHAR_CAP - 100 });
  });

  it('allows a request that exactly exhausts the cap', () => {
    expect(budgetDecision(VOICE_DAILY_CHAR_CAP - 50, 50)).toEqual({ allowed: true, remaining: 0 });
  });

  it('refuses a request that would overshoot, and spends nothing', () => {
    expect(budgetDecision(VOICE_DAILY_CHAR_CAP - 10, 50)).toEqual({ allowed: false, remaining: 10 });
  });

  it('refuses once the cap is already gone', () => {
    expect(budgetDecision(VOICE_DAILY_CHAR_CAP, 1)).toEqual({ allowed: false, remaining: 0 });
  });

  it('never reports negative remaining even if usage somehow overshot', () => {
    expect(budgetDecision(VOICE_DAILY_CHAR_CAP + 500, 1)).toEqual({ allowed: false, remaining: 0 });
  });

  it('honours an explicit cap', () => {
    expect(budgetDecision(0, 100, 120)).toEqual({ allowed: true, remaining: 20 });
  });
});
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd apps/api && bunx vitest run src/lib/server/voiceBudget.test.ts`
Expected: FAIL — `Failed to resolve import "./voiceBudget"`

- [ ] **Step 3: Write minimal implementation**

Create `apps/api/src/lib/server/voiceBudget.ts`:

```ts
/**
 * The hard stop that keeps voice free.
 *
 * Cloudflare's 10,000 free neurons/day already cap this on the Workers Free
 * plan, but the account may be on Workers Paid for D1/R2 — where overage bills
 * rather than fails. So the Worker enforces its own ceiling and refuses before
 * ever reaching a billable neuron. Two independent stops, deliberately.
 *
 * @cf/deepgram/aura-2-en costs 1363.64 neurons per 1,000 characters, so the
 * free 10,000 neurons buy ~7,333 characters. 7,000 leaves headroom.
 */
export const VOICE_DAILY_CHAR_CAP = 7000;

/** The UTC calendar day an instant falls in. Workers AI resets at 00:00 UTC. */
export function utcDayKey(iso: string): string {
  return new Date(iso).toISOString().slice(0, 10);
}

/**
 * Whether one synthesis request fits in what is left of the day.
 *
 * All-or-nothing: a request that would overshoot spends nothing rather than
 * being clipped, because half a spoken sentence is worse than none.
 */
export function budgetDecision(
  used: number,
  request: number,
  cap: number = VOICE_DAILY_CHAR_CAP
): { allowed: boolean; remaining: number } {
  const left = Math.max(0, cap - used);
  if (request > left) return { allowed: false, remaining: left };
  return { allowed: true, remaining: left - request };
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd apps/api && bunx vitest run src/lib/server/voiceBudget.test.ts`
Expected: PASS, 8 tests

- [ ] **Step 5: Commit**

```bash
git add apps/api/src/lib/server/voiceBudget.ts apps/api/src/lib/server/voiceBudget.test.ts
git commit -m "feat(voice): daily character budget arithmetic"
```

---

### Task 2: Budget persistence in D1

**Files:**
- Modify: `apps/api/src/lib/server/voiceBudget.ts` (append)
- Modify: `apps/api/db/schema.sql` (append)
- Modify: `apps/api/db/schema.sqlite.sql` (append)

**Interfaces:**
- Consumes: `budgetDecision`, `utcDayKey`, `VOICE_DAILY_CHAR_CAP` from Task 1; `sql` and `nowISO` from `./db`
- Produces: `reserveVoiceChars(userId: number, chars: number): Promise<{ allowed: boolean; remaining: number }>`

- [ ] **Step 1: Add the table to both schema files**

Append to `apps/api/db/schema.sql`:

```sql
-- Characters of speech synthesised per user per UTC day. This is the hard stop
-- that keeps voice free: the Worker refuses before reaching a billable neuron.
create table if not exists voice_budget (
  user_id    integer not null references users(id) on delete cascade,
  day        text not null,          -- 'YYYY-MM-DD', UTC
  chars      integer not null default 0,
  updated_at timestamptz not null default now(),
  primary key (user_id, day)
);
```

Append to `apps/api/db/schema.sqlite.sql`:

```sql
create table if not exists voice_budget (
  user_id    integer not null references users(id) on delete cascade,
  day        text not null,
  chars      integer not null default 0,
  updated_at text not null,
  primary key (user_id, day)
);
```

- [ ] **Step 2: Append the reservation function**

Append to `apps/api/src/lib/server/voiceBudget.ts`:

```ts
import { nowISO, sql } from './db';

// One idempotent DDL per server process, mirroring `ensureAiTable` in ai.ts —
// so a fresh local D1 works without a manual migration step.
let ensured: Promise<void> | null = null;
function ensureVoiceTable(): Promise<void> {
  if (!ensured) {
    ensured = (async () => {
      await sql`
        create table if not exists voice_budget (
          user_id    integer not null,
          day        text not null,
          chars      integer not null default 0,
          updated_at text not null,
          primary key (user_id, day)
        )`;
    })().catch((e) => {
      ensured = null; // let a later request retry
      throw e;
    });
  }
  return ensured;
}

/**
 * Spend `chars` of today's allowance, or refuse.
 *
 * Read-then-write rather than a single atomic statement: this is a single-user
 * app and the caller is one phone speaking one sentence at a time, so the race
 * window is theoretical. The all-or-nothing rule in `budgetDecision` means the
 * worst case of a lost update is a few hundred characters of overspend against
 * a cap that already sits below the free allowance.
 */
export async function reserveVoiceChars(
  userId: number,
  chars: number
): Promise<{ allowed: boolean; remaining: number }> {
  await ensureVoiceTable();
  const now = nowISO();
  const day = utcDayKey(now);

  const rows = await sql`
    select chars from voice_budget where user_id = ${userId} and day = ${day}`;
  const used = rows.length ? Number(rows[0].chars) : 0;

  const decision = budgetDecision(used, chars);
  if (!decision.allowed) return decision;

  await sql`
    insert into voice_budget (user_id, day, chars, updated_at)
    values (${userId}, ${day}, ${used + chars}, ${now})
    on conflict (user_id, day) do update set chars = ${used + chars}, updated_at = ${now}`;

  return decision;
}
```

- [ ] **Step 3: Verify the pure tests still pass and typecheck is clean**

Run: `cd apps/api && bunx vitest run src/lib/server/voiceBudget.test.ts && bun run check`
Expected: PASS 8 tests, then `svelte-check` with 0 errors

- [ ] **Step 4: Commit**

```bash
git add apps/api/src/lib/server/voiceBudget.ts apps/api/db/schema.sql apps/api/db/schema.sqlite.sql
git commit -m "feat(voice): persist the daily speech budget in D1"
```

---

### Task 3: `POST /api/voice/speak`

**Files:**
- Create: `apps/api/src/routes/api/voice/speak/+server.ts`
- Modify: `apps/api/wrangler.jsonc`
- Modify: `apps/api/src/app.d.ts` (add the `AI` binding to `Platform`)

**Interfaces:**
- Consumes: `reserveVoiceChars` from Task 2
- Produces: `POST /api/voice/speak` — body `{ text: string, speaker?: string }`, returns `audio/mpeg` bytes on success, `429 { code: 'voice_budget_exhausted', remaining: number }` when spent.

- [ ] **Step 1: Add the AI binding to wrangler**

In `apps/api/wrangler.jsonc`, after the `r2_buckets` array, add:

```jsonc
  "ai": { "binding": "AI" }
```

- [ ] **Step 2: Declare the binding for TypeScript**

In `apps/api/src/app.d.ts`, inside the `Platform` interface's `env`, add alongside `DB` and `MEDIA`:

```ts
        AI: { run: (model: string, input: Record<string, unknown>, opts?: { returnRawResponse?: boolean }) => Promise<Response> };
```

- [ ] **Step 3: Write the route**

Create `apps/api/src/routes/api/voice/speak/+server.ts`:

```ts
import { error, json } from '@sveltejs/kit';
import type { RequestHandler } from './$types';
import { reserveVoiceChars } from '$lib/server/voiceBudget';

/**
 * Catrine's voice.
 *
 * The client sends ONE sentence at a time and plays each clip as it arrives —
 * Aura synthesises a whole string before returning, so speaking a long reply in
 * one call would leave her silent for seconds.
 *
 * Audio only ever travels DOWN. Her ears are on-device (SpeechAnalyzer), so the
 * microphone stream never reaches this server, and this route is the only part
 * of voice that touches the network.
 *
 * A 429 here is normal, not an error: the client falls back to the on-device
 * AVSpeechSynthesizer voice and keeps the conversation going.
 */

/** One sentence. Longer than this means the client failed to chunk. */
const MAX_TEXT = 400;

/** Aura's speakers. Catrine defaults to `athena`. */
const SPEAKERS = new Set([
  'angus', 'asteria', 'arcas', 'orion', 'orpheus',
  'athena', 'luna', 'zeus', 'perseus', 'helios', 'hera', 'stella'
]);

export const POST: RequestHandler = async ({ request, locals, platform }) => {
  if (!locals.user) throw error(401, 'Not logged in');

  const body = await request.json().catch(() => ({}));
  const text = String(body.text ?? '').trim().slice(0, MAX_TEXT);
  if (!text) throw error(400, 'Nothing to say');

  const rawSpeaker = String(body.speaker ?? 'athena');
  const speaker = SPEAKERS.has(rawSpeaker) ? rawSpeaker : 'athena';

  const budget = await reserveVoiceChars(locals.user.id, text.length);
  if (!budget.allowed) {
    return json({ code: 'voice_budget_exhausted', remaining: budget.remaining }, { status: 429 });
  }

  const ai = platform?.env?.AI;
  if (!ai) throw error(503, 'Voice is not configured on the server');

  try {
    const resp = await ai.run(
      '@cf/deepgram/aura-2-en',
      { text, speaker, encoding: 'mp3' },
      { returnRawResponse: true }
    );
    return new Response(resp.body, {
      status: 200,
      headers: {
        'Content-Type': 'audio/mpeg',
        'Cache-Control': 'no-store',
        'X-Voice-Remaining': String(budget.remaining)
      }
    });
  } catch (e) {
    // Cloudflare's own neuron allowance ran out (3036) or capacity is short
    // (3040). Either way the client should fall back, not show an error.
    return json({ code: 'voice_unavailable', detail: (e as Error)?.message ?? '' }, { status: 429 });
  }
};
```

- [ ] **Step 4: Verify it builds**

`bun run check` alone does **not** catch SvelteKit's "Invalid export" rule for `+server.ts` — this repo has been bitten by that before. Run both:

Run: `cd apps/api && bun run check && bun run build`
Expected: 0 svelte-check errors, build succeeds

- [ ] **Step 5: Commit**

```bash
git add apps/api/src/routes/api/voice/speak/+server.ts apps/api/wrangler.jsonc apps/api/src/app.d.ts
git commit -m "feat(voice): /api/voice/speak backed by Deepgram Aura on Workers AI"
```

---

### Task 4: Sentence chunker

Pure string logic, so it gets real tests. This is what stops her going silent for five seconds before speaking.

**Files:**
- Create: `apps/mac/Sources/MyOS/Support/Voice/VoiceText.swift`
- Test: `apps/mac/Tests/VoiceTextTests.swift`

**Interfaces:**
- Consumes: nothing
- Produces: `enum VoiceText { static func sentences(_ text: String, maxLength: Int = 400) -> [String] }`

- [ ] **Step 1: Write the failing test**

Create `apps/mac/Tests/VoiceTextTests.swift`:

```swift
import XCTest
@testable import MyOS

final class VoiceTextTests: XCTestCase {
    func testSplitsOnSentenceEnders() {
        XCTAssertEqual(VoiceText.sentences("You skipped legs. Fix that tomorrow."),
                       ["You skipped legs.", "Fix that tomorrow."])
    }

    func testKeepsQuestionAndExclamation() {
        XCTAssertEqual(VoiceText.sentences("Did you? Really!"), ["Did you?", "Really!"])
    }

    func testTextWithNoTerminatorIsOneChunk() {
        XCTAssertEqual(VoiceText.sentences("no full stop here"), ["no full stop here"])
    }

    func testEmptyAndWhitespaceYieldNothing() {
        XCTAssertEqual(VoiceText.sentences(""), [])
        XCTAssertEqual(VoiceText.sentences("   \n  "), [])
    }

    func testDoesNotSplitOnDecimals() {
        XCTAssertEqual(VoiceText.sentences("You lifted 82.5 kg today."), ["You lifted 82.5 kg today."])
    }

    func testDoesNotSplitOnCommonAbbreviations() {
        XCTAssertEqual(VoiceText.sentences("Dr. Rao called. Ring him back."),
                       ["Dr. Rao called.", "Ring him back."])
    }

    func testTreatsEllipsisAsOneBreak() {
        XCTAssertEqual(VoiceText.sentences("Hmm... maybe not."), ["Hmm...", "maybe not."])
    }

    func testSplitsAnOverlongSentenceOnAWordBoundary() {
        let long = String(repeating: "word ", count: 200).trimmingCharacters(in: .whitespaces)
        let parts = VoiceText.sentences(long, maxLength: 60)
        XCTAssertGreaterThan(parts.count, 1)
        XCTAssertTrue(parts.allSatisfy { $0.count <= 60 }, "every chunk must fit the server's cap")
        XCTAssertFalse(parts.contains { $0.hasPrefix(" ") || $0.hasSuffix(" ") })
        // Nothing may be lost in the split.
        XCTAssertEqual(parts.joined(separator: " "), long)
    }

    func testCollapsesNewlinesInsideASentence() {
        XCTAssertEqual(VoiceText.sentences("Two things:\n- rest\n- eat"), ["Two things: - rest - eat"])
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd apps/mac && xcodegen generate && xcodebuild -project MyOS.xcodeproj -scheme MyOS -configuration Debug -derivedDataPath build test -only-testing:MyOSTests/VoiceTextTests 2>&1 | tail -20`
Expected: FAIL — `cannot find 'VoiceText' in scope`

- [ ] **Step 3: Write minimal implementation**

Create `apps/mac/Sources/MyOS/Support/Voice/VoiceText.swift`:

```swift
import Foundation

/// Turning one of Catrine's replies into speakable pieces.
///
/// Aura synthesises a whole string before it returns anything, so handing it a
/// four-sentence answer means four seconds of silence. Speaking sentence by
/// sentence means she starts almost immediately and the rest streams in behind
/// her — the difference between a conversation and a voicemail.
enum VoiceText {

    /// Abbreviations whose full stop does NOT end a sentence.
    private static let abbreviations: Set<String> = [
        "dr", "mr", "mrs", "ms", "prof", "sr", "jr", "st",
        "vs", "etc", "e.g", "i.e", "approx", "no", "kg", "cm"
    ]

    /// Split into pieces small enough for `/api/voice/speak` to accept.
    ///
    /// Nothing is ever dropped: joining the result with a single space
    /// reproduces the input's words in order.
    static func sentences(_ text: String, maxLength: Int = 400) -> [String] {
        let flat = text
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\r", with: " ")
        let collapsed = flat.split(separator: " ", omittingEmptySubsequences: true).joined(separator: " ")
        guard !collapsed.isEmpty else { return [] }

        var out: [String] = []
        var current = ""

        for word in collapsed.split(separator: " ") {
            current += current.isEmpty ? String(word) : " " + word
            if endsSentence(String(word)) {
                out.append(current)
                current = ""
            }
        }
        if !current.isEmpty { out.append(current) }

        return out.flatMap { split($0, maxLength: maxLength) }
    }

    /// Does this word terminate a sentence?
    private static func endsSentence(_ word: String) -> Bool {
        guard let last = word.last, ".?!".contains(last) else { return false }

        // "82.5" — a digit either side of the dot is a number, not a full stop.
        // (Only reachable when the dot is interior; a trailing dot can't be.)
        let body = word.trimmingCharacters(in: CharacterSet(charactersIn: ".?!"))
        if body.isEmpty { return false }

        // "Dr." — a known abbreviation keeps the sentence open.
        let bare = body.lowercased().trimmingCharacters(
            in: CharacterSet.alphanumerics.inverted.subtracting(CharacterSet(charactersIn: ".")))
        if abbreviations.contains(bare) { return false }

        // A bare number before a full stop ("82.5 kg." is fine; "82." mid-list is not).
        if last == ".", body.allSatisfy({ $0.isNumber || $0 == "." }) { return false }

        return true
    }

    /// Break a piece that is still too long, on word boundaries.
    private static func split(_ piece: String, maxLength: Int) -> [String] {
        guard piece.count > maxLength else { return [piece] }
        var out: [String] = []
        var current = ""
        for word in piece.split(separator: " ") {
            let candidate = current.isEmpty ? String(word) : current + " " + word
            if candidate.count > maxLength, !current.isEmpty {
                out.append(current)
                current = String(word)
            } else {
                current = candidate
            }
        }
        if !current.isEmpty { out.append(current) }
        return out
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd apps/mac && xcodegen generate && xcodebuild -project MyOS.xcodeproj -scheme MyOS -configuration Debug -derivedDataPath build test -only-testing:MyOSTests/VoiceTextTests 2>&1 | tail -20`
Expected: PASS, 9 tests

- [ ] **Step 5: Commit**

```bash
git add apps/mac/Sources/MyOS/Support/Voice/VoiceText.swift apps/mac/Tests/VoiceTextTests.swift
git commit -m "feat(voice): sentence chunker so Catrine starts speaking immediately"
```

---

### Task 5: Audio session helper

**Files:**
- Create: `apps/mac/Sources/MyOS/Support/Voice/VoiceAudioSession.swift`
- Test: `apps/mac/Tests/VoiceAudioSessionTests.swift`

**Interfaces:**
- Consumes: nothing
- Produces: `enum VoiceAudioSession { static func begin() ; static func end() ; static var isActive: Bool }` and the testable `struct AudioSessionState { var depth: Int; mutating func enter() -> Bool; mutating func exit() -> Bool }`

Rationale: `AVAudioSession` cannot be unit-tested on macOS (it is iOS-only), so the *balance* logic is extracted into a plain struct and tested; the framework calls are a thin `#if os(iOS)` shell around it.

- [ ] **Step 1: Write the failing test**

Create `apps/mac/Tests/VoiceAudioSessionTests.swift`:

```swift
import XCTest
@testable import MyOS

final class VoiceAudioSessionTests: XCTestCase {
    func testFirstEnterActivatesAndLastExitRestores() {
        var s = AudioSessionState()
        XCTAssertTrue(s.enter(), "first enter must actually configure the session")
        XCTAssertTrue(s.exit(), "last exit must actually restore it")
    }

    func testNestedEntersOnlyConfigureOnce() {
        var s = AudioSessionState()
        XCTAssertTrue(s.enter())
        XCTAssertFalse(s.enter(), "already configured — must not reconfigure mid-call")
        XCTAssertFalse(s.exit(), "still one holder left — must not restore yet")
        XCTAssertTrue(s.exit(), "now the last holder is gone")
    }

    func testUnbalancedExitIsHarmless() {
        var s = AudioSessionState()
        XCTAssertFalse(s.exit(), "exit without enter must not claim to restore")
        XCTAssertEqual(s.depth, 0, "depth must never go negative")
    }

    func testDepthNeverGoesNegativeAcrossManyExits() {
        var s = AudioSessionState()
        _ = s.enter()
        _ = s.exit()
        _ = s.exit()
        _ = s.exit()
        XCTAssertEqual(s.depth, 0)
        XCTAssertTrue(s.enter(), "a later call must still be able to configure")
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd apps/mac && xcodegen generate && xcodebuild -project MyOS.xcodeproj -scheme MyOS -configuration Debug -derivedDataPath build test -only-testing:MyOSTests/VoiceAudioSessionTests 2>&1 | tail -20`
Expected: FAIL — `cannot find 'AudioSessionState' in scope`

- [ ] **Step 3: Write minimal implementation**

Create `apps/mac/Sources/MyOS/Support/Voice/VoiceAudioSession.swift`:

```swift
import Foundation
#if os(iOS)
import AVFoundation
#endif

/// Balance tracking for the audio session, split out so it can be tested.
///
/// `AVAudioSession` is iOS-only and cannot be exercised from the macOS test
/// bundle, so the part that actually goes wrong — forgetting to restore, or
/// restoring while a call is still running — lives here as plain arithmetic.
struct AudioSessionState {
    private(set) var depth = 0

    /// Returns true when the caller should configure the session for a call.
    mutating func enter() -> Bool {
        depth += 1
        return depth == 1
    }

    /// Returns true when the caller should restore the previous configuration.
    mutating func exit() -> Bool {
        guard depth > 0 else { return false }
        depth -= 1
        return depth == 0
    }
}

/// Putting the phone into call mode, and — the part that matters — putting it back.
///
/// `SoundPlayer` runs the app's UI sound on `.playback` + `.mixWithOthers`
/// (fixed 2026-08-19 so the ring/silent switch stops muting it). A call needs
/// `.playAndRecord` + `.voiceChat`. If the swap is not undone on EVERY exit
/// path, UI sound dies after the first call — so `end()` is a `defer`, never a
/// line at the bottom of a happy path.
enum VoiceAudioSession {
    nonisolated(unsafe) private static var state = AudioSessionState()
    private static let lock = NSLock()

    static var isActive: Bool {
        lock.lock(); defer { lock.unlock() }
        return state.depth > 0
    }

    static func begin() {
        lock.lock()
        let shouldConfigure = state.enter()
        lock.unlock()
        guard shouldConfigure else { return }
        #if os(iOS)
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playAndRecord,
                                 mode: .voiceChat,
                                 options: [.defaultToSpeaker, .allowBluetooth])
        try? session.setActive(true)
        #endif
    }

    static func end() {
        lock.lock()
        let shouldRestore = state.exit()
        lock.unlock()
        guard shouldRestore else { return }
        #if os(iOS)
        let session = AVAudioSession.sharedInstance()
        try? session.setActive(false, options: [.notifyOthersOnDeactivation])
        // Back to what SoundPlayer expects, or the drop sound goes silent.
        try? session.setCategory(.playback, mode: .default, options: [.mixWithOthers])
        #endif
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd apps/mac && xcodegen generate && xcodebuild -project MyOS.xcodeproj -scheme MyOS -configuration Debug -derivedDataPath build test -only-testing:MyOSTests/VoiceAudioSessionTests 2>&1 | tail -20`
Expected: PASS, 4 tests

- [ ] **Step 5: Commit**

```bash
git add apps/mac/Sources/MyOS/Support/Voice/VoiceAudioSession.swift apps/mac/Tests/VoiceAudioSessionTests.swift
git commit -m "feat(voice): call-mode audio session that always restores"
```

---

### Task 6: The voice router — Aura with Apple fallback

**Files:**
- Create: `apps/mac/Sources/MyOS/Support/Voice/CatrineVoice.swift`
- Test: `apps/mac/Tests/CatrineVoiceTests.swift`
- Modify: `apps/mac/Sources/MyOS/Support/APIClient.swift` (append one method)

**Interfaces:**
- Consumes: `VoiceText.sentences` (Task 4), `VoiceAudioSession` (Task 5)
- Produces:
  - `protocol SpeechSynth { func speak(_ text: String) async -> Bool ; func stop() }` — `speak` returns false to mean "I could not, try the fallback"
  - `final class VoiceRouter { init(remote: SpeechSynth, local: SpeechSynth) ; var remoteExhausted: Bool ; func speak(reply: String) async ; func stop() }`
  - `APIClient.speak(text: String, speaker: String) async throws -> Data` — throws `APIError(status: 429, …)` when the budget is spent

- [ ] **Step 1: Write the failing test**

Create `apps/mac/Tests/CatrineVoiceTests.swift`:

```swift
import XCTest
@testable import MyOS

/// Records what it was asked to say, and can be told to refuse.
private final class FakeSynth: SpeechSynth, @unchecked Sendable {
    var spoken: [String] = []
    var stopped = 0
    var succeed = true
    func speak(_ text: String) async -> Bool {
        spoken.append(text)
        return succeed
    }
    func stop() { stopped += 1 }
}

final class CatrineVoiceTests: XCTestCase {

    func testSpeaksEverySentenceThroughTheRemoteVoice() async {
        let remote = FakeSynth(), local = FakeSynth()
        let router = VoiceRouter(remote: remote, local: local)
        await router.speak(reply: "You skipped legs. Fix that tomorrow.")
        XCTAssertEqual(remote.spoken, ["You skipped legs.", "Fix that tomorrow."])
        XCTAssertTrue(local.spoken.isEmpty)
    }

    func testFallsBackToTheLocalVoiceWhenRemoteRefuses() async {
        let remote = FakeSynth(), local = FakeSynth()
        remote.succeed = false
        let router = VoiceRouter(remote: remote, local: local)
        await router.speak(reply: "Budget is gone.")
        XCTAssertEqual(local.spoken, ["Budget is gone."])
    }

    func testStaysOnTheFallbackForTheRestOfTheCall() async {
        let remote = FakeSynth(), local = FakeSynth()
        remote.succeed = false
        let router = VoiceRouter(remote: remote, local: local)
        await router.speak(reply: "One. Two. Three.")
        // Only the FIRST sentence may probe the remote — retrying every sentence
        // burns a round trip each time for an answer we already have.
        XCTAssertEqual(remote.spoken, ["One."])
        XCTAssertEqual(local.spoken, ["One.", "Two.", "Three."])
        XCTAssertTrue(router.remoteExhausted)
    }

    func testExhaustionPersistsAcrossReplies() async {
        let remote = FakeSynth(), local = FakeSynth()
        remote.succeed = false
        let router = VoiceRouter(remote: remote, local: local)
        await router.speak(reply: "First.")
        await router.speak(reply: "Second.")
        XCTAssertEqual(remote.spoken, ["First."], "must not probe the remote again")
        XCTAssertEqual(local.spoken, ["First.", "Second."])
    }

    func testStopSilencesBothVoices() {
        let remote = FakeSynth(), local = FakeSynth()
        let router = VoiceRouter(remote: remote, local: local)
        router.stop()
        XCTAssertEqual(remote.stopped, 1)
        XCTAssertEqual(local.stopped, 1)
    }

    func testEmptyReplySaysNothing() async {
        let remote = FakeSynth(), local = FakeSynth()
        let router = VoiceRouter(remote: remote, local: local)
        await router.speak(reply: "   ")
        XCTAssertTrue(remote.spoken.isEmpty)
        XCTAssertTrue(local.spoken.isEmpty)
    }

    func testStopMidReplyDropsTheQueuedSentences() async {
        let remote = FakeSynth(), local = FakeSynth()
        let router = VoiceRouter(remote: remote, local: local)
        router.stop()                       // barge-in arrives before speaking starts
        await router.speak(reply: "One. Two. Three.")
        XCTAssertTrue(remote.spoken.isEmpty, "a cancelled router must not start speaking")
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd apps/mac && xcodegen generate && xcodebuild -project MyOS.xcodeproj -scheme MyOS -configuration Debug -derivedDataPath build test -only-testing:MyOSTests/CatrineVoiceTests 2>&1 | tail -20`
Expected: FAIL — `cannot find type 'SpeechSynth' in scope`

- [ ] **Step 3: Add the API method**

Append to `apps/mac/Sources/MyOS/Support/APIClient.swift`, inside the same type as `chat(...)` (after it):

```swift
    // MARK: - Voice

    /// Synthesise ONE sentence. Throws `APIError(status: 429)` when today's free
    /// allowance is spent — the caller treats that as "use the on-device voice",
    /// not as a failure.
    func speak(text: String, speaker: String) async throws -> Data {
        let body = try JSONSerialization.data(withJSONObject: ["text": text, "speaker": speaker])
        return try await requestData("POST", "api/voice/speak", bodyData: body, using: aiSession)
    }
```

- [ ] **Step 4: Write the router and both synths**

Create `apps/mac/Sources/MyOS/Support/Voice/CatrineVoice.swift`:

```swift
import Foundation
import AVFoundation

/// Something that can say a sentence out loud.
///
/// `speak` returns **false** to mean "I couldn't — use the other one". It never
/// throws, because from the caller's side a spent budget and a dead network are
/// the same event: fall back and keep the conversation going.
protocol SpeechSynth: AnyObject, Sendable {
    func speak(_ text: String) async -> Bool
    func stop()
}

/// Catrine's good voice — Deepgram Aura, on the Cloudflare account that already
/// holds everything else. Free until the day's allowance runs out.
final class AuraSynth: SpeechSynth, @unchecked Sendable {
    private let api: APIClient
    private let speaker: String
    private var player: AVAudioPlayer?
    private let lock = NSLock()

    init(api: APIClient, speaker: String = "athena") {
        self.api = api
        self.speaker = speaker
    }

    func speak(_ text: String) async -> Bool {
        guard let data = try? await api.speak(text: text, speaker: speaker) else { return false }
        guard let p = try? AVAudioPlayer(data: data) else { return false }
        lock.lock(); player = p; lock.unlock()
        p.prepareToPlay()
        p.play()
        // Hold the turn until the clip finishes, so sentences don't overlap.
        while p.isPlaying {
            try? await Task.sleep(nanoseconds: 60_000_000)
            if Task.isCancelled { p.stop(); return true }
        }
        return true
    }

    func stop() {
        lock.lock(); let p = player; player = nil; lock.unlock()
        p?.stop()
    }
}

/// The always-available voice. Free, offline, unlimited — and clearly synthetic,
/// which is the price of never paying. Prefers a downloaded Premium/Enhanced
/// voice over the compact default, because the difference is large.
final class SystemSynth: NSObject, SpeechSynth, @unchecked Sendable {
    private let synth = AVSpeechSynthesizer()
    private var continuation: CheckedContinuation<Bool, Never>?

    /// Best installed English voice: Premium, else Enhanced, else whatever the
    /// system gives us.
    static func bestVoice(language: String = "en-US") -> AVSpeechSynthesisVoice? {
        let candidates = AVSpeechSynthesisVoice.speechVoices()
            .filter { $0.language.hasPrefix(String(language.prefix(2))) }
        return candidates.first { $0.quality == .premium }
            ?? candidates.first { $0.quality == .enhanced }
            ?? AVSpeechSynthesisVoice(language: language)
    }

    override init() {
        super.init()
        synth.delegate = self
    }

    func speak(_ text: String) async -> Bool {
        await withCheckedContinuation { (c: CheckedContinuation<Bool, Never>) in
            continuation = c
            let utterance = AVSpeechUtterance(string: text)
            utterance.voice = Self.bestVoice()
            utterance.rate = AVSpeechUtteranceDefaultSpeechRate
            synth.speak(utterance)
        }
    }

    func stop() {
        synth.stopSpeaking(at: .immediate)
        finish()
    }

    private func finish() {
        let c = continuation
        continuation = nil
        c?.resume(returning: true)
    }
}

extension SystemSynth: AVSpeechSynthesizerDelegate {
    func speechSynthesizer(_ s: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) { finish() }
    func speechSynthesizer(_ s: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) { finish() }
}

/// Decides which mouth speaks, sentence by sentence.
///
/// The rule that matters: once the remote voice has refused ONCE, stay on the
/// fallback for the rest of the session. The refusal means the daily budget is
/// gone, and that does not un-happen before midnight UTC — probing again on
/// every sentence would just add a wasted round trip to each one.
final class VoiceRouter: @unchecked Sendable {
    private let remote: SpeechSynth
    private let local: SpeechSynth
    private let lock = NSLock()
    private var exhausted = false
    private var cancelled = false

    var remoteExhausted: Bool {
        lock.lock(); defer { lock.unlock() }
        return exhausted
    }

    init(remote: SpeechSynth, local: SpeechSynth) {
        self.remote = remote
        self.local = local
    }

    /// Speak a whole reply. Returns when she has finished, or when `stop()` cut in.
    func speak(reply: String) async {
        lock.lock(); cancelled = false; lock.unlock()

        for sentence in VoiceText.sentences(reply) {
            lock.lock()
            let stop = cancelled
            let useLocal = exhausted
            lock.unlock()
            if stop { return }

            if useLocal {
                _ = await local.speak(sentence)
                continue
            }
            if await remote.speak(sentence) { continue }

            lock.lock(); exhausted = true; lock.unlock()
            _ = await local.speak(sentence)
        }
    }

    /// Barge-in. Kills the current clip and drops everything queued behind it.
    func stop() {
        lock.lock(); cancelled = true; lock.unlock()
        remote.stop()
        local.stop()
    }
}
```

- [ ] **Step 5: Run test to verify it passes**

Run: `cd apps/mac && xcodegen generate && xcodebuild -project MyOS.xcodeproj -scheme MyOS -configuration Debug -derivedDataPath build test -only-testing:MyOSTests/CatrineVoiceTests 2>&1 | tail -20`
Expected: PASS, 7 tests

- [ ] **Step 6: Commit**

```bash
git add apps/mac/Sources/MyOS/Support/Voice/CatrineVoice.swift apps/mac/Tests/CatrineVoiceTests.swift apps/mac/Sources/MyOS/Support/APIClient.swift
git commit -m "feat(voice): Aura voice with automatic on-device fallback"
```

---

### Task 7: On-device listening

**Files:**
- Create: `apps/mac/Sources/MyOS/Support/Voice/SpeechListener.swift`

**Interfaces:**
- Consumes: nothing
- Produces: `@MainActor final class SpeechListener: ObservableObject` with `@Published var partial: String`, `var onFinal: ((String) -> Void)?`, `var onSpeechStarted: (() -> Void)?`, `func requestAuthorization() async -> Bool`, `func start() throws`, `func stop()`

No unit test: this is a thin shell over `SFSpeechRecognizer`/`AVAudioEngine` with no logic of its own worth asserting. It is verified on-device in Task 9.

- [ ] **Step 1: Write the listener**

Create `apps/mac/Sources/MyOS/Support/Voice/SpeechListener.swift`:

```swift
import Foundation
import Speech
import AVFoundation

/// Catrine's ears — entirely on the device.
///
/// `requiresOnDeviceRecognition = true` is the whole privacy story: the audio is
/// transcribed by the phone's own model and the microphone stream never reaches
/// a server. It is also why listening is unlimited and free, which is what makes
/// the daily budget in `/api/voice/speak` cover only her half of the conversation.
///
/// iOS 26's `SpeechAnalyzer` is faster and more accurate, but the deployment
/// target is 17, so `SFSpeechRecognizer` is the floor. Both are on-device; the
/// newer one is a later upgrade behind `#available`, not a prerequisite.
@MainActor
final class SpeechListener: ObservableObject {

    /// What he is saying right now, updated as he says it.
    @Published private(set) var partial = ""

    /// A complete utterance — this is what gets sent to Catrine.
    var onFinal: ((String) -> Void)?

    /// Voice detected while she was talking. This is the barge-in trigger, and
    /// it must fire on the FIRST partial result, not on a final transcript —
    /// waiting for a final is far too late to feel like an interruption.
    var onSpeechStarted: (() -> Void)?

    private let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-IN"))
        ?? SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
    private let engine = AVAudioEngine()
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private var silenceTimer: Timer?
    private var sawSpeechThisUtterance = false

    /// How long a pause ends an utterance. Short enough to feel responsive,
    /// long enough to survive thinking mid-sentence.
    private let endpointSilence: TimeInterval = 1.1

    enum ListenerError: Error { case unavailable, denied }

    func requestAuthorization() async -> Bool {
        let speech = await withCheckedContinuation { (c: CheckedContinuation<Bool, Never>) in
            SFSpeechRecognizer.requestAuthorization { c.resume(returning: $0 == .authorized) }
        }
        guard speech else { return false }
        #if os(iOS)
        return await withCheckedContinuation { (c: CheckedContinuation<Bool, Never>) in
            AVAudioSession.sharedInstance().requestRecordPermission { c.resume(returning: $0) }
        }
        #else
        return true
        #endif
    }

    func start() throws {
        guard let recognizer, recognizer.isAvailable else { throw ListenerError.unavailable }
        stop()

        let req = SFSpeechAudioBufferRecognitionRequest()
        req.shouldReportPartialResults = true
        req.requiresOnDeviceRecognition = true      // never leaves the device
        request = req

        let input = engine.inputNode
        input.removeTap(onBus: 0)
        input.installTap(onBus: 0, bufferSize: 1024, format: input.outputFormat(forBus: 0)) { buffer, _ in
            req.append(buffer)
        }
        engine.prepare()
        try engine.start()

        task = recognizer.recognitionTask(with: req) { [weak self] result, error in
            guard let self else { return }
            Task { @MainActor in
                if let result {
                    let text = result.bestTranscription.formattedString
                    if !text.isEmpty {
                        if !self.sawSpeechThisUtterance {
                            self.sawSpeechThisUtterance = true
                            self.onSpeechStarted?()
                        }
                        self.partial = text
                        self.armEndpoint(text)
                    }
                }
                if error != nil { self.flush() }
            }
        }
    }

    func stop() {
        silenceTimer?.invalidate(); silenceTimer = nil
        task?.cancel(); task = nil
        request?.endAudio(); request = nil
        if engine.isRunning { engine.stop() }
        engine.inputNode.removeTap(onBus: 0)
        partial = ""
        sawSpeechThisUtterance = false
    }

    /// Restart the "has he stopped talking?" clock on every new word.
    private func armEndpoint(_ text: String) {
        silenceTimer?.invalidate()
        silenceTimer = Timer.scheduledTimer(withTimeInterval: endpointSilence, repeats: false) { [weak self] _ in
            Task { @MainActor in self?.flush() }
        }
    }

    private func flush() {
        let text = partial.trimmingCharacters(in: .whitespacesAndNewlines)
        partial = ""
        sawSpeechThisUtterance = false
        silenceTimer?.invalidate(); silenceTimer = nil
        guard !text.isEmpty else { return }
        onFinal?(text)
    }
}
```

- [ ] **Step 2: Verify both targets still compile**

Run: `cd apps/mac && xcodegen generate && xcodebuild -project MyOS.xcodeproj -scheme MyOS -configuration Debug -derivedDataPath build build 2>&1 | tail -5`
Expected: `** BUILD SUCCEEDED **`

Run: `cd apps/ios && xcodegen generate && xcodebuild -project MyOS.xcodeproj -scheme MyOS -configuration Debug -sdk iphonesimulator -destination 'generic/platform=iOS Simulator' -derivedDataPath build build 2>&1 | tail -5`
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 3: Commit**

```bash
git add apps/mac/Sources/MyOS/Support/Voice/SpeechListener.swift
git commit -m "feat(voice): on-device speech recognition, audio never leaves the phone"
```

---

### Task 8: The call screen

**Files:**
- Create: `apps/ios/Sources/MyOS/Views/VoiceCallView.swift`
- Modify: `apps/ios/Info.plist`
- Modify: `apps/mac/Sources/MyOS/Views/ChatWidget.swift`

**Interfaces:**
- Consumes: `SpeechListener` (7), `VoiceRouter` / `AuraSynth` / `SystemSynth` (6), `VoiceAudioSession` (5), `AppState.runCatrineTurn(query:turns:agent:)`, `APIClient.AgentInfo`, `APIClient.ChatTurn`, `AgentConfig.shared`
- Produces: `struct VoiceCallView: View` presented as a `fullScreenCover`

- [ ] **Step 1: Add the usage strings and background mode**

In `apps/ios/Info.plist`, alongside the existing `NSFaceIDUsageDescription` entry, add:

```xml
	<key>NSMicrophoneUsageDescription</key>
	<string>So you can talk to Catrine instead of typing.</string>
	<key>NSSpeechRecognitionUsageDescription</key>
	<string>Your speech is transcribed on this device and never uploaded.</string>
	<key>UIBackgroundModes</key>
	<array>
		<string>audio</string>
	</array>
```

- [ ] **Step 2: Write the call screen**

Create `apps/ios/Sources/MyOS/Views/VoiceCallView.swift`:

```swift
import SwiftUI

/// Talking to Catrine.
///
/// The loop is deliberately the same one the text chat uses: a transcript goes
/// into `runCatrineTurn` and a reply comes out, so her tools, retrieval, memory
/// and bounded reasoning are identical whether he typed or spoke. Voice is an
/// I/O change, not a brain change.
struct VoiceCallView: View {
    @EnvironmentObject private var state: AppState
    @Environment(\.dismiss) private var dismiss
    @StateObject private var listener = SpeechListener()

    @State private var phase: Phase = .starting
    @State private var heard = ""
    @State private var said = ""
    @State private var router: VoiceRouter?
    @State private var turn: Task<Void, Never>?
    @State private var denied = false

    enum Phase { case starting, listening, thinking, speaking, blocked }

    var body: some View {
        VStack(spacing: Gap.screen) {
            header
            Spacer(minLength: 0)
            orb
            transcript
            Spacer(minLength: 0)
            endButton
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Palette.bg.ignoresSafeArea())
        .task { await begin() }
        .onDisappear { finish() }
    }

    // MARK: - Pieces

    private var header: some View {
        HStack {
            ScreenTitle(text: AgentConfig.shared.displayName)
            Spacer()
        }
        .knRise(0)
    }

    private var orb: some View {
        Circle()
            .fill(phase == .speaking ? Palette.accent : Palette.card)
            .frame(width: 132, height: 132)
            .overlay(
                Image(systemName: icon)
                    .font(.system(size: 40, weight: .semibold))
                    .foregroundStyle(phase == .speaking ? Palette.bg : Palette.text)
            )
            .animation(.knPop, value: phase)
            .knRise(1)
    }

    private var icon: String {
        switch phase {
        case .starting:  return "hourglass"
        case .listening: return "mic.fill"
        case .thinking:  return "ellipsis"
        case .speaking:  return "waveform"
        case .blocked:   return "mic.slash.fill"
        }
    }

    private var transcript: some View {
        VStack(spacing: Gap.tight) {
            Text(label)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Palette.dim)
            Text(displayText)
                .font(.system(size: 15))
                .foregroundStyle(Palette.text)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity, alignment: .center)
                .frame(minHeight: 72, alignment: .top)
        }
        .knRise(2)
    }

    private var label: String {
        switch phase {
        case .starting:  return "Connecting"
        case .listening: return "Listening"
        case .thinking:  return "Thinking"
        case .speaking:  return AgentConfig.shared.displayName
        case .blocked:   return "Microphone access needed"
        }
    }

    private var displayText: String {
        if phase == .blocked {
            return "Turn on Microphone and Speech Recognition for MyOS in Settings."
        }
        if phase == .speaking { return said }
        if !listener.partial.isEmpty { return listener.partial }
        return heard
    }

    private var endButton: some View {
        Button("End") { dismiss() }
            .buttonStyle(KButtonStyle())
            .knRise(3)
    }

    // MARK: - Lifecycle

    private func begin() async {
        guard await listener.requestAuthorization() else {
            phase = .blocked
            denied = true
            return
        }

        VoiceAudioSession.begin()
        router = VoiceRouter(remote: AuraSynth(api: state.api), local: SystemSynth())

        // Barge-in: the moment he speaks, she stops. This fires on the first
        // partial result, not the final transcript — a final would be far too late.
        listener.onSpeechStarted = {
            router?.stop()
            turn?.cancel()
            if phase == .speaking || phase == .thinking { phase = .listening }
        }

        listener.onFinal = { text in
            heard = text
            answer(text)
        }

        do {
            try listener.start()
            phase = .listening
        } catch {
            phase = .blocked
        }
    }

    private func answer(_ text: String) {
        turn?.cancel()
        phase = .thinking
        turn = Task {
            let a = AgentConfig.shared
            let agent = APIClient.AgentInfo(name: a.displayName,
                                            tone: a.tone.directive,
                                            custom: a.custom.trimmingCharacters(in: .whitespacesAndNewlines))
            let turns = state.voiceTurns()
            state.appendVoiceTurn(role: "user", content: text)

            do {
                let outcome = try await state.runCatrineTurn(query: text, turns: turns, agent: agent)
                if Task.isCancelled { return }
                let reply = ChatAction.parse(outcome.reply).visible
                state.appendVoiceTurn(role: "assistant", content: reply)
                said = reply
                phase = .speaking
                await router?.speak(reply: reply)
            } catch {
                if Task.isCancelled { return }
                said = "Something went wrong there."
                phase = .speaking
                await router?.speak(reply: said)
            }
            if !Task.isCancelled { phase = .listening }
        }
    }

    private func finish() {
        turn?.cancel()
        router?.stop()
        listener.stop()
        if !denied { VoiceAudioSession.end() }
    }
}
```

- [ ] **Step 3: Add the two AppState helpers the view calls**

Append to `apps/mac/Sources/MyOS/Support/AppState.swift`, in the same extension area as the chat code:

```swift
extension AppState {
    /// The current thread's history, in the shape `runCatrineTurn` wants.
    /// Voice and text share one thread on purpose — a spoken question and a
    /// typed follow-up are the same conversation.
    func voiceTurns() -> [APIClient.ChatTurn] {
        guard let i = chat.threads.firstIndex(where: { $0.id == chat.activeID }) else { return [] }
        return chat.threads[i].messages
            .filter { !$0.content.isEmpty }
            .suffix(24)
            .map { APIClient.ChatTurn(role: $0.role, content: $0.content) }
    }

    /// Record a spoken turn in the active thread so it survives the call.
    func appendVoiceTurn(role: String, content: String) {
        guard !content.isEmpty,
              let i = chat.threads.firstIndex(where: { $0.id == chat.activeID }) else { return }
        chat.threads[i].messages.append(ChatMessage(role: role, content: content, at: Self.nowStamp()))
        chat.threads[i].updatedAt = Self.nowStamp()
        if isHydrated { push(StateKey.chat, chat) }
    }
}
```

Before writing this, confirm the active-thread property name:

```bash
grep -n "activeID\|var active\|selectChat" apps/mac/Sources/MyOS/Support/AppState.swift | head
```

If it is not `chat.activeID`, use whatever `selectChat` assigns and adjust both helpers.

- [ ] **Step 4: Add the call button to the chat widget**

In `apps/mac/Sources/MyOS/Views/ChatWidget.swift`, in the icon-button row near line 136 (next to History / New chat), add — wrapped for iOS only, since the Mac cannot open the microphone yet:

```swift
            #if os(iOS)
            iconButton("phone.fill", help: "Talk") { showCall = true }
            #endif
```

Add the state near the other `@State` properties:

```swift
    #if os(iOS)
    @State private var showCall = false
    #endif
```

And attach the cover next to the existing `.fullScreenCover` around line 54:

```swift
            #if os(iOS)
            .fullScreenCover(isPresented: $showCall) {
                VoiceCallView().environmentObject(state)
            }
            #endif
```

- [ ] **Step 5: Build both targets**

Run: `cd apps/mac && xcodegen generate && xcodebuild -project MyOS.xcodeproj -scheme MyOS -configuration Debug -derivedDataPath build build 2>&1 | tail -5`
Expected: `** BUILD SUCCEEDED **`

Run: `cd apps/ios && xcodegen generate && xcodebuild -project MyOS.xcodeproj -scheme MyOS -configuration Debug -sdk iphonesimulator -destination 'generic/platform=iOS Simulator' -derivedDataPath build build 2>&1 | tail -5`
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 6: Run the whole Swift suite**

Run: `cd apps/mac && xcodebuild -project MyOS.xcodeproj -scheme MyOS -configuration Debug -derivedDataPath build test 2>&1 | tail -12`
Expected: all tests pass — 304 existing + 20 new

- [ ] **Step 7: Commit**

```bash
git add apps/ios/Sources/MyOS/Views/VoiceCallView.swift apps/ios/Info.plist apps/mac/Sources/MyOS/Views/ChatWidget.swift apps/mac/Sources/MyOS/Support/AppState.swift
git commit -m "feat(voice): call screen, barge-in, and a phone button in the chat widget"
```

---

### Task 9: Deploy, install, verify

**Files:** none

- [ ] **Step 1: Full verification**

```bash
cd /Users/berjilskcript/Documents/Personal/MyOS/apps/api && bunx vitest run && bun run check && bun run build
cd ../mac && xcodebuild -project MyOS.xcodeproj -scheme MyOS -configuration Debug -derivedDataPath build test 2>&1 | tail -8
```
Expected: vitest passes, 0 svelte-check errors, build succeeds, Swift suite green.

- [ ] **Step 2: Deploy the Worker**

The `AI` binding is new, so this deploy is what makes `/api/voice/speak` exist.

```bash
cd /Users/berjilskcript/Documents/Personal/MyOS/apps/api && bunx wrangler deploy
```

Then confirm the route answers rather than 404s:

```bash
curl -s -o /dev/null -w '%{http_code}\n' -X POST \
  https://myos-api.berjiljacob.workers.dev/api/voice/speak \
  -H 'Content-Type: application/json' -d '{"text":"hello"}'
```
Expected: `401` (not logged in) — which proves the route is deployed and auth-guarded. A `404` means the deploy did not take.

- [ ] **Step 3: Merge and push**

```bash
cd /Users/berjilskcript/Documents/Personal/MyOS
git checkout main && git merge --ff-only feat/catrine-voice && git push origin main
```

- [ ] **Step 4: Install on both devices**

```bash
./scripts/install-apps.sh both
```

The iPhone drops off Wi-Fi regularly; the script retries every 10s until it appears. Do **not** report failure because the phone is briefly away, and do not suggest plugging in a cable — "Connect via network" is already on. Diagnose with `xcrun devicectl list devices -v` (check `tunnelState`) if it never lands.

- [ ] **Step 5: Berjil verifies on the phone**

Things only he can check:
- Chat widget → phone button → does she hear him.
- Interrupt her mid-sentence — does she actually stop, and quickly.
- Ask something only a note would answer ("what did I decide about X") — does she reach into the vault.
- After ~8 minutes of her talking, does the voice change to the Apple one *without the conversation breaking*.
- Does the UI drop sound still work after ending a call (that is the audio-session restore).

---

## Self-Review

**Spec coverage:**

| Spec section | Task |
| --- | --- |
| On-device STT, audio never leaves phone | 7 |
| `runCatrineTurn` unchanged | 8 (call site) |
| Aura primary voice | 3, 6 |
| Apple fallback, stays fallen back | 6 |
| Free budget, two independent stops | 1, 2, 3 |
| Sentence chunking so she starts fast | 4 |
| Audio session swap + guaranteed restore | 5 |
| `fullScreenCover`, never on Today | 8 |
| Design tokens, stiff motion | 8 |
| Voice + text share one `ChatThread` | 8 |
| Info.plist strings, background audio | 8 |
| No target bump | 7 (SFSpeechRecognizer floor) |
| Mac mic entitlement | out of scope (Phase 2) — call button is `#if os(iOS)` |

**Known deviations from the spec, deliberate:**
- The spec described `SpeechAnalyzer` with an `SFSpeechRecognizer` fallback. Task 7 ships **only** `SFSpeechRecognizer`, which is on-device, free, and works on the iOS 17 floor. Adding the iOS 26 path behind `#available` is a clean follow-up that changes no interface — it was not worth doubling the surface area before the loop is proven on-device.
- The spec's "show remaining budget in the UI" is not implemented. `X-Voice-Remaining` is returned by the route so the view can adopt it later; the phase indicator already makes the voice change visible.

**Placeholder scan:** none — every code step carries the real body.

**Type consistency:** `SpeechSynth.speak` returns `Bool` in the protocol, the fakes, `AuraSynth` and `SystemSynth`. `VoiceRouter.speak(reply:)` is used with that label in Task 6's tests and Task 8's view. `reserveVoiceChars` returns `{ allowed, remaining }` in Task 2 and is destructured that way in Task 3. `VoiceText.sentences(_:maxLength:)` is called with one argument in Task 6 and two in Task 4's tests, matching the default.
