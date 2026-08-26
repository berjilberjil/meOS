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
}
