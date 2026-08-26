import XCTest
@testable import MyOS

/// Regressions from the pre-ship logic audit. Each test here stands for a bug
/// that was live, not a hypothetical — the comment says what used to happen.
final class ShipAuditTests: XCTestCase {

    private func photo(_ dateKey: String, _ id: String) -> ProgressPhoto {
        ProgressPhoto(id: id, date: dateKey, url: URL(fileURLWithPath: "/tmp/\(id).jpg"))
    }

    // MARK: - Weekly report photo thinning

    // `pick` divided by `limit - 1`. At limit 1 that is a division by zero, and
    // the infinity went straight into an `Int(...)` conversion — which traps in
    // Swift rather than saturating. Asking for one photo crashed the app.
    func testPickOfOneDoesNotDivideByZero() {
        let week = "2026-08-17"..."2026-08-23"
        let photos = (17...22).map { photo("2026-08-\($0)", "2026-08-\($0)__a") }
        let picked = WeeklyReportMath.pick(photos, in: week, limit: 1)
        XCTAssertEqual(picked.count, 1)
        XCTAssertEqual(picked.first?.id, "2026-08-22__a", "one photo asked for is the newest one")
    }

    func testPickOfNoneIsEmpty() {
        let week = "2026-08-17"..."2026-08-23"
        let photos = (17...22).map { photo("2026-08-\($0)", "2026-08-\($0)__a") }
        XCTAssertEqual(WeeklyReportMath.pick(photos, in: week, limit: 0).count, 0)
    }

    func testPickStillSpreadsAcrossTheWindow() {
        let week = "2026-08-17"..."2026-08-23"
        let photos = (17...22).map { photo("2026-08-\($0)", "2026-08-\($0)__a") }
        let picked = WeeklyReportMath.pick(photos, in: week, limit: 4)
        XCTAssertEqual(picked.count, 4)
        XCTAssertEqual(picked.first?.id, "2026-08-17__a")
        XCTAssertEqual(picked.last?.id, "2026-08-22__a")
    }

    // MARK: - Calorie floors

    // `goalCalories` was floored at 1000 but the cut/bulk figures beside it on
    // the Calories card were not, so the card could offer a "Cut" number the app
    // would refuse to actually use — and under a small enough profile, one below
    // zero.
    func testCutAndBulkShareTheSameFloorAsTheSelectedGoal() {
        // Deliberately tiny, so TDEE + the cut offset lands under the floor.
        let t = Nutrition.targets(sex: .female, weightKg: 35, heightCm: 120, age: 70,
                                  activity: .sedentary, goal: .cut)
        XCTAssertGreaterThanOrEqual(t.cut, 1000)
        XCTAssertGreaterThanOrEqual(t.bulk, 1000)
        XCTAssertEqual(t.goalCalories, t.cut, "the selected goal is the cut figure shown")
    }

    func testNormalProfileIsUntouchedByTheFloor() {
        let t = Nutrition.targets(sex: .male, weightKg: 90, heightCm: 175, age: 28,
                                  activity: .moderate, goal: .cut)
        XCTAssertGreaterThan(t.cut, 1000)
        XCTAssertGreaterThan(t.bulk, t.maintain)
        XCTAssertGreaterThan(t.maintain, t.cut)
    }

    // Protein is set from the weight passed in — which is why the caller must
    // pass the *current* weight and not the goal weight.
    func testProteinFollowsTheWeightItIsGiven() {
        let heavy = Nutrition.targets(sex: .male, weightKg: 90, heightCm: 175, age: 28,
                                      activity: .moderate, goal: .cut)
        let goalWeight = Nutrition.targets(sex: .male, weightKg: 70, heightCm: 175, age: 28,
                                           activity: .moderate, goal: .cut)
        XCTAssertGreaterThan(heavy.proteinG, goalWeight.proteinG,
                             "computing off the goal weight under-feeds protein by ~40g")
        XCTAssertGreaterThan(heavy.goalCalories, goalWeight.goalCalories)
    }

    // MARK: - Progress photo deletion

    // Deleting a photo removed it locally and asked the server to drop the cloud
    // copy with `try?`. When that request failed nothing recorded the intent, so
    // the next pull saw a remote photo this device didn't have and downloaded it
    // straight back — the deleted photo reappeared, every time.
    func testDeletedPhotoStaysTombstonedUntilTheServerConfirms() {
        let id = "2026-08-26__audit-\(UUID().uuidString)"
        addTeardownBlock { ProgressPhotoStore.clearDeleted(id) }

        XCTAssertFalse(ProgressPhotoStore.isDeleted(id))
        ProgressPhotoStore.markDeleted(id)
        XCTAssertTrue(ProgressPhotoStore.isDeleted(id), "a failed cloud delete stays queued")
        XCTAssertTrue(ProgressPhotoStore.deletedIds.contains(id), "and pull() filters against this set")

        ProgressPhotoStore.clearDeleted(id)
        XCTAssertFalse(ProgressPhotoStore.isDeleted(id), "confirmed gone — stop tracking it")
    }

    func testMarkingTheSameDeletionTwiceIsNotADuplicate() {
        let id = "2026-08-26__audit-\(UUID().uuidString)"
        addTeardownBlock { ProgressPhotoStore.clearDeleted(id) }
        ProgressPhotoStore.markDeleted(id)
        ProgressPhotoStore.markDeleted(id)
        XCTAssertEqual(ProgressPhotoStore.deletedIds.filter { $0 == id }.count, 1)
    }

    // MARK: - Food identity

    // `upsert_food` ran through `addFood`, which prepends unconditionally, so
    // re-running an import appended the whole library again instead of updating
    // it. Matching is by name because that is all an importer has.
    func testFoodMatchKeyIgnoresCaseAndSurroundingSpace() {
        XCTAssertEqual(Food.matchKey("  MuscleBlaze Creatine "), Food.matchKey("muscleblaze creatine"))
        XCTAssertNotEqual(Food.matchKey("Whey"), Food.matchKey("Whey Isolate"))
    }

    func testFoodMatchKeyOfBlankIsEmptySoItNeverMatches() {
        XCTAssertEqual(Food.matchKey("   "), "")
        XCTAssertEqual(Food.matchKey(""), "")
    }

    // MARK: - Focus time survives midnight

    // The focus timer banked its minutes into `days[todayKey]`, with todayKey
    // re-read from the clock when the block *ended*. A block begun at 23:50 and
    // finished at 00:15 looked for its to-do in a day that had just rolled over,
    // found nothing, and returned silently — and drainSpent() had already zeroed
    // the counter, so the time was lost rather than unrecorded.
    private func plan(_ ids: [String]) -> DayPlan {
        var d = DayPlan()
        d.todos = ids.map { FocusItem(id: $0, text: $0) }
        return d
    }

    func testWorkIsBankedAgainstTheDayThatOwnsIt() {
        let days = ["2026-08-25": plan(["late-block"]), "2026-08-26": plan(["fresh"])]
        XCTAssertEqual(
            FocusRecord.dayOwning(todo: "late-block", in: days, today: "2026-08-26"),
            "2026-08-25",
            "the block started yesterday, so yesterday is where its minutes go")
    }

    func testTodayWinsWhenTodayHoldsTheItem() {
        let days = ["2026-08-25": plan(["a"]), "2026-08-26": plan(["b"])]
        XCTAssertEqual(FocusRecord.dayOwning(todo: "b", in: days, today: "2026-08-26"), "2026-08-26")
    }

    func testAnUnknownTodoOwnsNoDay() {
        let days = ["2026-08-26": plan(["a"])]
        XCTAssertNil(FocusRecord.dayOwning(todo: "ghost", in: days, today: "2026-08-26"))
    }

    func testADuplicatedIdResolvesToTheNewestDay() {
        let days = ["2026-08-20": plan(["dup"]), "2026-08-24": plan(["dup"])]
        XCTAssertEqual(FocusRecord.dayOwning(todo: "dup", in: days, today: "2026-08-26"), "2026-08-24")
    }

    // MARK: - Replies that only look like commands

    // `parse` treated any line starting with "ACTION " as a command. When it then
    // failed to parse, the line was appended to neither the actions nor the
    // visible text — so an ordinary sentence vanished out of the middle of a reply.
    func testAnEnglishSentenceStartingWithActionSurvives() {
        let out = ChatAction.parse("Here is the plan.\nAction items: book the flight.\nThat's it.")
        XCTAssertTrue(out.visible.contains("Action items: book the flight."),
                      "a sentence that isn't a command must stay in the reply")
        XCTAssertTrue(out.actions.isEmpty)
    }

    func testARealActionLineIsStillStripped() {
        let out = ChatAction.parse("On it.\nACTION create_note title=\"Groceries\"")
        XCTAssertEqual(out.visible, "On it.")
        XCTAssertEqual(out.actions.count, 1)
        XCTAssertEqual(out.actions.first?.kind, .createNote)
        XCTAssertEqual(out.actions.first?.fields["title"], "Groceries")
    }

    // MARK: - Two people, one Mac

    // Logging out cleared state.json and nothing else, so body photos stayed in
    // one flat folder on disk and the next account to sign in on the same Mac
    // opened Progress and saw the previous user's body. The folder is scoped per
    // account now — hidden on logout rather than deleted, because an un-uploaded
    // photo is the owner's only copy.
    func testEachAccountGetsItsOwnPhotoFolder() {
        let original = ProgressPhotoStore.account
        addTeardownBlock { ProgressPhotoStore.use(account: original) }

        ProgressPhotoStore.use(account: "alice")
        let alice = ProgressPhotoStore.dir
        ProgressPhotoStore.use(account: "bob")
        let bob = ProgressPhotoStore.dir

        XCTAssertNotEqual(alice, bob, "one account must never read another's photos")
        XCTAssertEqual(alice.lastPathComponent, "alice")
        XCTAssertEqual(bob.lastPathComponent, "bob")
    }

    func testLoggedOutResolvesToItsOwnEmptyScope() {
        let original = ProgressPhotoStore.account
        addTeardownBlock { ProgressPhotoStore.use(account: original) }

        ProgressPhotoStore.use(account: "alice")
        let alice = ProgressPhotoStore.dir
        ProgressPhotoStore.use(account: "")
        XCTAssertNotEqual(ProgressPhotoStore.dir, alice, "logging out must stop showing them")
        XCTAssertTrue(ProgressPhotoStore.list().isEmpty, "and show nothing at all")
    }

    func testAccountNamesAreNormalisedIntoOneFolder() {
        let original = ProgressPhotoStore.account
        addTeardownBlock { ProgressPhotoStore.use(account: original) }

        ProgressPhotoStore.use(account: "Berjil")
        let a = ProgressPhotoStore.dir
        ProgressPhotoStore.use(account: "berjil")
        XCTAssertEqual(ProgressPhotoStore.dir, a, "case must not split one person in two")
    }

    // MARK: - The balance on the Fold tab

    // When Fold hands over no balances blob, banks are reconstructed from the
    // `current_balance` riding on each transaction. That walk assigned
    // unconditionally, so the last row won — and the feed arrives newest-first,
    // so the dictionary named `latest` held each account's *oldest* balance.
    // `liquid`, and then net worth, are derived from it.
    private func txn(_ id: String, _ balance: Double, _ stamp: String) -> [String: Any] {
        ["account_id": id, "current_balance": balance, "txn_timestamp": stamp,
         "financial_information_provider": ["name": "HDFC Bank"]]
    }

    func testBankBalanceIsTheNewestReadingNotTheOldest() {
        // Newest first, exactly how the feed pages.
        let txns = [txn("u1", 19_539.13, "2026-08-25T10:00:00Z"),
                    txn("u1", 4_000.00,  "2026-08-02T10:00:00Z"),
                    txn("u1", 1_200.00,  "2026-07-11T10:00:00Z")]
        let out = FoldSnapshotBuilder.outcome(blobs: [], transactions: txns, previous: nil)
        XCTAssertEqual(out.data.banks.count, 1)
        XCTAssertEqual(out.data.banks.first?.balance, 19_539.13,
                       "a balance from July is not what the account holds today")
        XCTAssertEqual(out.data.liquid, 19_539.13, accuracy: 0.001)
    }

    func testTheNewestReadingWinsWhateverOrderItArrivesIn() {
        let txns = [txn("u1", 1_200.00,  "2026-07-11T10:00:00Z"),
                    txn("u1", 19_539.13, "2026-08-25T10:00:00Z"),
                    txn("u1", 4_000.00,  "2026-08-02T10:00:00Z")]
        let out = FoldSnapshotBuilder.outcome(blobs: [], transactions: txns, previous: nil)
        XCTAssertEqual(out.data.banks.first?.balance, 19_539.13)
    }

    // With no timestamps there is nothing to sort on, so the first row seen wins
    // — which is the newest, given how the feed is paged.
    func testUndatedRowsFallBackToFeedOrder() {
        let txns: [[String: Any]] = [
            ["account_id": "u1", "current_balance": 900.0],
            ["account_id": "u1", "current_balance": 100.0]
        ]
        let out = FoldSnapshotBuilder.outcome(blobs: [], transactions: txns, previous: nil)
        XCTAssertEqual(out.data.banks.first?.balance, 900)
    }

    // MARK: - Looking at a note is not editing it

    // iOS saves from `onDisappear`, unconditionally, through the plain-text
    // entry point — which had no change guard. Opening a note and going back
    // rewrote `updatedAt` (the field the list is sorted and grouped by) and
    // rebuilt `content` from the flat body, so a note written on the Mac with
    // headings, checkboxes and images lost all of it to being looked at.
    func testReopeningANoteUnchangedIsNotAnEdit() {
        let n = Note(id: "n1", createdAt: "2026-08-01T10:00:00", updatedAt: "2026-08-01T10:00:00",
                     title: "Groceries", body: "milk\neggs")
        XCTAssertFalse(n.wouldChange(title: "Groceries", body: "milk\neggs"),
                       "opening and closing must not count as a change")
    }

    func testARealPlainTextEditIsStillAnEdit() {
        let n = Note(id: "n1", createdAt: "2026-08-01T10:00:00", updatedAt: "2026-08-01T10:00:00",
                     title: "Groceries", body: "milk\neggs")
        XCTAssertTrue(n.wouldChange(title: "Groceries", body: "milk\neggs\nbread"))
        XCTAssertTrue(n.wouldChange(title: "Shopping", body: "milk\neggs"))
    }

    // MARK: - What a failed save does next

    // Retrying is for the network being briefly gone. A 401 means the session is
    // over and a 400 means the server refuses this body every time — re-sending
    // either just burns requests against a free tier that has to stay free.
    func testAuthAndValidationFailuresAreNotRetried() {
        XCTAssertFalse(AppState.isWorthRetrying(APIError(status: 401, message: "Not logged in")))
        XCTAssertFalse(AppState.isWorthRetrying(APIError(status: 403, message: "Forbidden")))
        XCTAssertFalse(AppState.isWorthRetrying(APIError(status: 400, message: "Bad body")))
    }

    func testServerAndTransportFailuresAreRetried() {
        XCTAssertTrue(AppState.isWorthRetrying(APIError(status: 500, message: "Server error")))
        XCTAssertTrue(AppState.isWorthRetrying(APIError(status: 503, message: "Unavailable")))
        XCTAssertTrue(AppState.isWorthRetrying(URLError(.notConnectedToInternet)),
                      "the whole reason retries exist")
    }

    func testTimeoutsAndRateLimitsAreWorthWaitingOut() {
        XCTAssertTrue(AppState.isWorthRetrying(APIError(status: 408, message: "Timeout")))
        XCTAssertTrue(AppState.isWorthRetrying(APIError(status: 429, message: "Slow down")))
    }

    // MARK: - Numbers that used to crash the app

    // `Int(_: Double)` traps outside Int64 rather than saturating. These
    // formatters run on every keystroke of unvalidated fields, and on whatever
    // arrives from sync or from a model's guess.
    func testWeightFormatterSurvivesNonsense() {
        XCTAssertEqual(Fmt.trimKg(.infinity), "0")
        XCTAssertEqual(Fmt.trimKg(-.infinity), "0")
        XCTAssertEqual(Fmt.trimKg(.nan), "0")
        XCTAssertFalse(Fmt.trimKg(1e300).isEmpty, "clamped, not crashed")
    }

    func testWeightFormatterStillFormatsRealWeights() {
        XCTAssertEqual(Fmt.trimKg(72), "72")
        XCTAssertEqual(Fmt.trimKg(72.5), "72.5")
        XCTAssertEqual(Fmt.trimKg(72.44), "72.4")
    }

    func testNumberFieldFormatterSurvivesNonsense() {
        XCTAssertEqual(KLabeledNumberField.format(.infinity, decimals: 0), "")
        XCTAssertEqual(KLabeledNumberField.format(.nan, decimals: 1), "")
        XCTAssertEqual(KLabeledNumberField.format(nil, decimals: 0), "")
        XCTAssertFalse(KLabeledNumberField.format(1e300, decimals: 0).isEmpty)
    }

    func testNumberFieldFormatterStillFormats() {
        XCTAssertEqual(KLabeledNumberField.format(8000, decimals: 0), "8000")
        XCTAssertEqual(KLabeledNumberField.format(175.5, decimals: 1), "175.5")
    }

    // The profile height field parsed with bare `Double(_:)`, which accepts
    // "inf" — and an infinite height crashed the formatter on the next render.
    func testProfileDecimalParseRejectsInfinity() {
        XCTAssertNil(ProfileView.parseDecimal("inf"))
        XCTAssertNil(ProfileView.parseDecimal("nan"))
        XCTAssertNil(ProfileView.parseDecimal(""))
        XCTAssertEqual(ProfileView.parseDecimal("175.5"), 175.5)
        XCTAssertEqual(ProfileView.parseDecimal("17a5"), 175, "stray letters are dropped, not fatal")
    }

    // MARK: - A phone edit must not delete what the phone cannot show

    // iOS edits the plain-text mirror, and the save path replaced `content` with
    // BlockDoc.from(plainText:) outright. Images contribute nothing to plainText,
    // so they were not flattened — they were deleted, and it synced to the Mac.
    func testEditingOnThePhoneKeepsThePhotos() {
        let old = BlockDoc(blocks: [
            Block(type: .heading, spans: [TextSpan(text: "Trip")], level: 1),
            Block(type: .image, src: "data:image/jpeg;base64,AAAA"),
            Block(type: .paragraph, spans: [TextSpan(text: "book the flight")])
        ])
        let next = BlockDoc.merging(plainText: "Trip\nbook the flight tomorrow",
                                    keepingAttachmentsOf: old)
        XCTAssertEqual(next.blocks.filter { $0.isAttachment }.count, 1, "the photo survives")
        XCTAssertTrue(next.plainText.contains("book the flight tomorrow"))
    }

    func testMergingWithoutAttachmentsIsJustTheText() {
        let old = BlockDoc(blocks: [Block(type: .paragraph, spans: [TextSpan(text: "one")])])
        let next = BlockDoc.merging(plainText: "one\ntwo", keepingAttachmentsOf: old)
        XCTAssertTrue(next.blocks.filter { $0.isAttachment }.isEmpty)
        XCTAssertEqual(next.plainText, "one\ntwo")
    }

    // An image-only note has a blank title and a blank body, which is what the
    // phone's auto-delete tested — so opening one and going back destroyed it.
    func testAnImageOnlyNoteIsNotEmpty() {
        let doc = BlockDoc(blocks: [
            Block(type: .image, src: "data:image/jpeg;base64,AAAA"),
            Block(type: .paragraph, spans: [])
        ])
        XCTAssertFalse(doc.isEffectivelyEmpty, "there is a photo in it")
    }

    func testATrulyBlankNoteIsStillEmpty() {
        XCTAssertTrue(BlockDoc(blocks: [Block(type: .paragraph, spans: [])]).isEffectivelyEmpty)
    }

    // MARK: - Fold's month total

    // The card shows the top six categories; the headline is the whole month.
    // Summing the truncated list dropped every category past the sixth.
    private func debit(_ category: String, _ amount: Double, _ stamp: String) -> [String: Any] {
        ["type": "DEBIT", "amount": amount, "category": category, "txn_timestamp": stamp]
    }

    func testSpentThisMonthCountsEveryCategoryNotJustTheShownSix() {
        // Mid-month, so the UTC-vs-local offset can't push it into a neighbour.
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM"
        let stamp = f.string(from: Date()) + "-15T10:00:00Z"
        let cats = ["Transport", "Food", "Bills", "Shopping", "Health", "Rent", "Books", "Gifts"]
        let txns = cats.enumerated().map { debit($0.element, Double(800 - $0.offset * 50), stamp) }
        let out = FoldSnapshotBuilder.outcome(blobs: [], transactions: txns, previous: nil)
        XCTAssertEqual(out.data.topSpends.count, 6, "the card still shows six")
        let everything = (0..<8).reduce(0.0) { $0 + Double(800 - $1 * 50) }
        XCTAssertEqual(out.data.spentThisMonth, everything, accuracy: 0.001,
                       "but the headline is the whole month")
    }

    // An unreadable date is not evidence that a transaction is from this month.
    func testUndatedDebitsAreNotCountedAsThisMonth() {
        let txns: [[String: Any]] = [["type": "DEBIT", "amount": 5000.0, "category": "Rent"]]
        let out = FoldSnapshotBuilder.outcome(blobs: [], transactions: txns, previous: nil)
        XCTAssertEqual(out.data.spentThisMonth, 0)
        XCTAssertTrue(out.data.topSpends.isEmpty)
    }

    func testLastMonthsDebitsStayOutOfThisMonth() {
        let txns = [debit("Rent", 25_000, "2020-01-05T10:00:00Z")]
        let out = FoldSnapshotBuilder.outcome(blobs: [], transactions: txns, previous: nil)
        XCTAssertEqual(out.data.spentThisMonth, 0)
    }

    // MARK: - What the assistant remembers and forgets

    // isDuplicate normalised by the SMALLER token set, so any strict superset
    // scored a perfect 1.0 and the more specific fact was the one discarded.
    func testAMoreSpecificMemoryIsNotADuplicateOfALooserOne() {
        XCTAssertFalse(MemoryBank.isDuplicate("allergic to peanuts and shellfish",
                                              "allergic to peanuts"),
                       "the shellfish allergy has to be storable")
    }

    func testAGenuineRestatementIsStillADuplicate() {
        XCTAssertTrue(MemoryBank.isDuplicate("allergic to peanuts", "allergic to peanuts"))
        XCTAssertTrue(MemoryBank.isDuplicate("Allergic to peanuts.", "allergic to peanuts"))
    }

    func testUnrelatedMemoriesAreNotDuplicates() {
        XCTAssertFalse(MemoryBank.isDuplicate("ships on Fridays", "allergic to peanuts"))
    }

    // MARK: - Fenced code in a reply

    // The branch tested for a bare ``` while the pattern's json tag was
    // optional, so a Swift snippet lost its fence, kept "swift" as a stray
    // first line, and everything after the closing fence was cut.
    func testASwiftCodeFenceIsLeftAlone() {
        let raw = "```swift\nfunc debounce() {}\n```"
        XCTAssertEqual(ChatText.unwrap(raw), raw, "code fences are for showing code")
    }

    func testAJSONFenceIsStillUnwrapped() {
        XCTAssertEqual(ChatText.unwrap("```json\n{\"reply\":\"hello\"}\n```"), "hello")
    }

    func testAPlainReplyIsUntouched() {
        XCTAssertEqual(ChatText.unwrap("just a sentence"), "just a sentence")
    }

    // MARK: - Erasing activity has to stick

    // `merged` is a union, which is what lets two devices record at once — but a
    // union cannot express a removal. Erasing on the phone pushed an empty doc,
    // the Mac merged it and changed nothing, then pushed its full copy back, and
    // every erased session reappeared within a couple of minutes.
    private func doc(_ startedAt: [String], erasedAt: String = "") -> ActivityDoc {
        var d = ActivityDoc()
        d.erasedAt = erasedAt
        d.events = startedAt.map {
            ActivityEvent(id: $0, deviceId: "mac", deviceType: .mac, platform: "macOS",
                          appId: "com.apple.dt.Xcode", appName: "Xcode",
                          category: .development, startedAt: $0, endedAt: $0,
                          duration: 60, productivity: .productive, source: .macFrontmost)
        }
        return d
    }

    func testAnErasedHistoryIsNotMergedBackIn() {
        let mac = doc(["2026-08-20T10:00:00", "2026-08-21T10:00:00"])
        let erasedPhone = doc([], erasedAt: "2026-08-22T09:00:00")
        let out = mac.merged(with: erasedPhone)
        XCTAssertTrue(out.events.isEmpty, "the erase has to survive the union")
        XCTAssertEqual(out.erasedAt, "2026-08-22T09:00:00")
    }

    func testWorkRecordedAfterTheEraseIsKept() {
        let erased = doc([], erasedAt: "2026-08-22T09:00:00")
        let sinceThen = doc(["2026-08-22T11:00:00"])
        let out = erased.merged(with: sinceThen)
        XCTAssertEqual(out.events.count, 1, "you did that after asking to erase")
        XCTAssertEqual(out.events.first?.startedAt, "2026-08-22T11:00:00")
    }

    func testTheNewerEraseWins() {
        let a = doc([], erasedAt: "2026-08-20T09:00:00")
        let b = doc([], erasedAt: "2026-08-22T09:00:00")
        XCTAssertEqual(a.merged(with: b).erasedAt, "2026-08-22T09:00:00")
        XCTAssertEqual(b.merged(with: a).erasedAt, "2026-08-22T09:00:00")
    }

    func testWithNoEraseTheUnionIsUnchanged() {
        let a = doc(["2026-08-20T10:00:00"])
        let b = doc(["2026-08-21T10:00:00"])
        XCTAssertEqual(a.merged(with: b).events.count, 2)
    }

    // MARK: - What the weekly report is told

    // The brief read FitnessDay.calories, which only the natural-language
    // quick-log ever writes. Log every meal through the Fitness checklist all
    // week and the model was handed "calories: not logged", then asked for diet
    // advice against a phantom intake.
    func testTheBriefReportsWhatWasActuallyEaten() {
        let week = "2026-08-17"..."2026-08-23"
        let intake = ["2026-08-18": Macros(calories: 2100, protein: 160),
                      "2026-08-19": Macros(calories: 1900, protein: 150)]
        let text = WeeklyBrief.text(
            name: "Berjil", goal: .cut, targetWeightKg: 70,
            calorieTarget: 2000, proteinTarget: 180,
            fitness: [:], training: TrainingState(), intake: intake,
            lastWeek: .init(label: "LAST WEEK", range: week, photos: 1),
            thisWeek: .init(label: "THIS WEEK", range: week, photos: 1))
        XCTAssertTrue(text.contains("calories: avg 2000"), text)
        XCTAssertTrue(text.contains("protein: avg 155"), text)
        XCTAssertFalse(text.contains("calories: not logged"))
    }

    func testTheBriefStillSaysNotLoggedWhenNothingWasEaten() {
        let week = "2026-08-17"..."2026-08-23"
        let text = WeeklyBrief.text(
            name: "Berjil", goal: .cut, targetWeightKg: 70,
            calorieTarget: nil, proteinTarget: nil,
            fitness: [:], training: TrainingState(), intake: [:],
            lastWeek: .init(label: "LAST WEEK", range: week, photos: 0),
            thisWeek: .init(label: "THIS WEEK", range: week, photos: 0))
        XCTAssertTrue(text.contains("calories: not logged"), text)
    }

    // MARK: - Age

    // `dob` had the real date picker and looked authoritative, but nothing read
    // it — `age` was a separate hand-typed Int. Fill in the birth date and leave
    // Age blank and calorieTargets() returned nil at its `age > 0` guard: every
    // calorie and macro target silently unavailable, with nothing pointing at
    // the empty box.
    private func at(_ key: String) -> Date {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.calendar = Calendar(identifier: .gregorian)
        f.dateFormat = "yyyy-MM-dd"
        return f.date(from: key)!
    }

    func testAgeComesFromTheDateOfBirth() {
        XCTAssertEqual(Profile.age(fromDOB: "1998-03-14", on: at("2026-08-26")), 28)
    }

    func testAgeAdvancesOnTheBirthday() {
        XCTAssertEqual(Profile.age(fromDOB: "1998-08-26", on: at("2026-08-25")), 27, "day before")
        XCTAssertEqual(Profile.age(fromDOB: "1998-08-26", on: at("2026-08-26")), 28, "on the day")
    }

    func testNonsenseDatesOfBirthAreRefused() {
        XCTAssertNil(Profile.age(fromDOB: ""))
        XCTAssertNil(Profile.age(fromDOB: "not-a-date"))
        XCTAssertNil(Profile.age(fromDOB: "2030-01-01", on: at("2026-08-26")), "not born yet")
        XCTAssertNil(Profile.age(fromDOB: "1800-01-01", on: at("2026-08-26")), "beyond 120")
    }

    func testTypedAgeIsUsedWhenThereIsNoDateOfBirth() {
        var p = Profile()
        p.age = 31
        XCTAssertEqual(p.resolvedAge, 31)
        p.dob = "1998-03-14"
        XCTAssertEqual(p.resolvedAge, Profile.age(fromDOB: "1998-03-14"),
                       "the date of birth wins once it is set")
    }

    // MARK: - Typing a decimal point

    // Any binding that re-renders a number back into its own text field on each
    // keystroke eats the dot: the formatter has nothing to render for a trailing
    // ".", so it vanished under the cursor and the next digit joined the integer
    // part. 72.5 kg became 725, 172.5 cm became 1725, 12.5 g of fat became 125.
    func testATrailingDotSurvivesBeingTyped() {
        XCTAssertEqual(KLabeledNumberField.clean("72.", decimals: 1), "72.")
        XCTAssertEqual(KLabeledNumberField.clean("72.5", decimals: 1), "72.5")
    }

    func testOnlyOneDotIsAllowed() {
        XCTAssertEqual(KLabeledNumberField.clean("72.5.3", decimals: 2), "72.53")
    }

    func testAWholeNumberFieldRefusesADot() {
        XCTAssertEqual(KLabeledNumberField.clean("8000.5", decimals: 0), "80005")
        XCTAssertEqual(KLabeledNumberField.clean("8000", decimals: 0), "8000")
    }

    func testLettersNeverReachTheValue() {
        XCTAssertEqual(KLabeledNumberField.clean("17a2.5kg", decimals: 1), "172.5")
        XCTAssertEqual(KLabeledNumberField.clean("inf", decimals: 2), "")
        XCTAssertNil(KLabeledNumberField.parse(""))
    }

    func testTheParsedValueMatchesWhatWasTyped() {
        XCTAssertEqual(KLabeledNumberField.parse(KLabeledNumberField.clean("72.5", decimals: 1)), 72.5)
        XCTAssertEqual(KLabeledNumberField.parse(KLabeledNumberField.clean("12.5", decimals: 2)), 12.5)
    }

    // MARK: - One account, one row

    // The two bank producers derive `last4` differently — the identified path
    // from the masked account number, the transaction walk from the account
    // uuid's last four characters — so the `name + last4` dedupe never matched
    // across them and the same account appeared twice. `liquid` is the sum of
    // the rows when no total is supplied, so it was counted twice, and net worth
    // followed.
    func testAnAccountIsNotListedTwiceFromTwoSources() {
        let identities: [String: Any] = ["data": ["added": [
            ["uuid": "u1", "masked_account_number": "XXXXXX8362",
             "fi_type": "DEPOSIT", "fip": ["name": "HDFC Bank"]]
        ], "subscribed": []]]
        let balances: [String: Any] = ["data": [["account_id": "u1", "current_balance": 19_539.13]]]
        let txns: [[String: Any]] = [[
            "account_id": "u1-a1f3", "current_balance": 19_539.13,
            "txn_timestamp": "2026-08-25T10:00:00Z",
            "financial_information_provider": ["name": "HDFC Bank"]
        ]]
        let out = FoldSnapshotBuilder.outcome(blobs: [identities, balances],
                                              transactions: txns, previous: nil)
        XCTAssertEqual(out.data.banks.count, 1, "one account, one row")
        XCTAssertEqual(out.data.liquid, 19_539.13, accuracy: 0.001, "not doubled")
    }

    func testTransactionsStillSupplyBanksWhenNothingElseDoes() {
        let txns: [[String: Any]] = [[
            "account_id": "u1-a1f3", "current_balance": 500.0,
            "txn_timestamp": "2026-08-25T10:00:00Z",
            "financial_information_provider": ["name": "HDFC Bank"]
        ]]
        let out = FoldSnapshotBuilder.outcome(blobs: [], transactions: txns, previous: nil)
        XCTAssertEqual(out.data.banks.first?.balance, 500)
    }

    // MARK: - Regressions in the fixes themselves

    // "+91" plus eight typed digits is exactly ten, so a fix that stripped the
    // country code only when there were MORE than ten digits never fired at the
    // size it existed to catch — Send stayed enabled at a half-typed number.
    func testTheOTPGateCountsOnlyTypedDigits() {
        XCTAssertEqual(FoldData.nationalDigits("+9198765432").count, 8, "eight typed")
        XCTAssertEqual(FoldData.nationalDigits("+919876543210").count, 10, "a whole number")
        XCTAssertEqual(FoldData.nationalDigits("9876543210").count, 10, "no prefix typed")
    }

    // A block recovered from a compacted day knows how long it lasted but not
    // which app it was in, and both consumers interpolate the name straight into
    // a sentence — an empty one read "2h 14m in ."
    func testAFocusBlockAlwaysNamesAnApp() {
        XCTAssertFalse(FocusBlock.unknownApp.isEmpty)
    }

    // A flat 0.6 ratio meant any two-term forget query needed a perfect match,
    // so the most ordinary phrasing there is did nothing at all.
    func testForgettingMatchesOrdinaryPhrasing() {
        let q = Set(TextIndex.terms("peanut allergy"))
        let stored = MemoryBank.tokens("allergic to peanuts")
        let shared = stored.intersection(q).count
        XCTAssertGreaterThanOrEqual(shared, max(1, q.count - 1),
                                    "one stem mismatch must not defeat a short query")
    }

    func testForgettingStillIgnoresAnUnrelatedMemory() {
        let q = Set(TextIndex.terms("peanut allergy"))
        let unrelated = MemoryBank.tokens("ships on Fridays")
        XCTAssertLessThan(unrelated.intersection(q).count, max(1, q.count - 1))
    }

    // MARK: - Round-tripping a note between devices

    // A link card mirrors its URL into plainText so search finds it, so
    // re-parsing that text produced a paragraph holding the URL *and* the card
    // was appended beside it — the note grew a line on every hop between
    // devices.
    func testMergingIsIdempotentForLinkCards() {
        let card = Block(type: .linkCard, url: "https://example.com")
        let old = BlockDoc(blocks: [Block(type: .paragraph, spans: [TextSpan(text: "hello")]), card])
        let once = BlockDoc.merging(plainText: old.plainText, keepingAttachmentsOf: old)
        let twice = BlockDoc.merging(plainText: once.plainText, keepingAttachmentsOf: once)
        XCTAssertEqual(once.blocks.count, twice.blocks.count, "a second hop must not add a line")
        XCTAssertEqual(once.blocks.filter { $0.isAttachment }.count, 1)
        XCTAssertTrue(once.plainText.contains("hello"))
    }

    func testMergingStillKeepsAGenuineEdit() {
        let card = Block(type: .linkCard, url: "https://example.com")
        let old = BlockDoc(blocks: [Block(type: .paragraph, spans: [TextSpan(text: "hello")]), card])
        let next = BlockDoc.merging(plainText: "hello there\nhttps://example.com",
                                    keepingAttachmentsOf: old)
        XCTAssertTrue(next.plainText.contains("hello there"))
        XCTAssertEqual(next.blocks.filter { $0.isAttachment }.count, 1)
    }

    // MARK: - A logged meal stays logged

    // "Logged" was inferred from the meal having items, so removing the last one
    // made it unconfirmed again — and the tile went back to advertising the
    // plan, as if the meal were still ahead of you.
    func testEmptyingALoggedMealKeepsItLogged() {
        var log = MealLog()
        log.tick(.lunch, planned: [PlanItem(foodId: "chapati", quantity: 2)])
        XCTAssertEqual(log.state(.lunch), .logged)
        log.setItems(.lunch, [])
        XCTAssertEqual(log.state(.lunch), .logged, "you logged it; it was just empty")
    }

    func testSkippingAMealUnconfirmsIt() {
        var log = MealLog()
        log.tick(.lunch, planned: [PlanItem(foodId: "chapati", quantity: 1)])
        log.skip(.lunch)
        XCTAssertEqual(log.state(.lunch), .skipped)
    }

    func testAnUntouchedMealIsStillUnconfirmed() {
        XCTAssertEqual(MealLog().state(.dinner), .unconfirmed)
    }

    // A day written by an older build has no `confirmed` list; it must still read
    // correctly rather than turning every logged meal back into a plan.
    func testAnOlderDayDecodesAsLogged() throws {
        let json = #"{"meals":{"lunch":[{"id":"a","foodId":"chapati","quantity":2}]},"skipped":[]}"#
        let log = try JSONDecoder().decode(MealLog.self, from: Data(json.utf8))
        XCTAssertEqual(log.state(.lunch), .logged)
        XCTAssertEqual(log.state(.dinner), .unconfirmed)
    }

    // MARK: - The crash that would have shipped

    // Nutrition.targets was the one member of the Int(Double) family still
    // converting unbounded input. A twenty-digit height is committed, pushed and
    // synced before anything renders it — and then Today and Fitness trap on
    // every render, on both devices, permanently.
    func testCalorieMathsSurvivesAbsurdBodyStats() {
        let huge = Nutrition.targets(sex: .male, weightKg: 1e20, heightCm: 1e20, age: 30,
                                     activity: .moderate, goal: .cut)
        XCTAssertGreaterThan(huge.bmr, 0, "clamped, not crashed")
        let infinite = Nutrition.targets(sex: .female, weightKg: .infinity, heightCm: .nan, age: 30,
                                         activity: .sedentary, goal: .maintain)
        XCTAssertGreaterThanOrEqual(infinite.goalCalories, 0)
    }

    func testCalorieMathsIsUnchangedForRealBodies() {
        let t = Nutrition.targets(sex: .male, weightKg: 90, heightCm: 175, age: 28,
                                  activity: .moderate, goal: .cut)
        XCTAssertGreaterThan(t.bmr, 1500)
        XCTAssertLessThan(t.bmr, 2500)
    }

    // "inf" is a legal Double literal, and both weight fields parsed with bare
    // Double(_:) — so it passed their `> 0` check and was synced.
    func testWeightParseRefusesNonsense() {
        XCTAssertNil(Fmt.parseWeightKg("inf"))
        XCTAssertNil(Fmt.parseWeightKg("0"))
        XCTAssertNil(Fmt.parseWeightKg("99999"))
        XCTAssertEqual(Fmt.parseWeightKg("72.5"), 72.5)
    }

    // A metric carries 1D/1W/1M/YTD/1Y and nothing else, so 3M, 5Y and MAX had
    // been borrowing another window's number and printing it beside a chart
    // clipped to the real one.
    func testRangesWithNoRealChangeReportNone() throws {
        // Decoded rather than constructed — every field on MacroMetric is a `let`.
        let json = """
        {"id":"nifty","name":"NIFTY","category":"markets","country":"IN","unit":"",
         "kind":"index","frequency":"daily","source":"-","sourceUrl":"","priority":1,
         "value":100,"asOf":"2026-08-26",
         "change30D":{"abs":1.0,"pct":1.0},"change1Y":{"abs":-3.1,"pct":-3.1},
         "history":[],"quality":"verified"}
        """
        let m = try XCTUnwrap(try? JSONDecoder().decode(MacroMetric.self, from: Data(json.utf8)))
        XCTAssertNil(MacroRange.m3.delta(m), "3M has no honest number")
        XCTAssertNil(MacroRange.y5.delta(m))
        XCTAssertNil(MacroRange.max.delta(m))
        XCTAssertNotNil(MacroRange.m1.delta(m))
        XCTAssertNotNil(MacroRange.y1.delta(m))
    }
}
