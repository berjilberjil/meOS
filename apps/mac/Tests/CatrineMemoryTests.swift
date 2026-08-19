import XCTest
@testable import MyOS

/// What Catherine is allowed to remember, and what she pulls back out.
///
/// This is the pollution guard. A second brain that remembers everything is a
/// transcript — these tests pin the line between a durable fact and a diary
/// entry, and they are the reason the memory bank stays small enough to matter.
final class CatrineMemoryTests: XCTestCase {

    private func mem(_ text: String,
                     _ category: MemoryCategory = .other,
                     source: MemorySource = .extracted,
                     confidence: Double = 1,
                     importance: Int = 3,
                     pinned: Bool = false) -> MemoryItem {
        MemoryItem(content: text, category: category, importance: importance,
                   source: source, confidence: confidence,
                   createdAt: "2026-08-19T10:00:00", pinned: pinned)
    }

    // MARK: - Worth remembering?

    func testDurableFactsAreKept() {
        for fact in ["From now on I use PostgreSQL for my projects",
                     "My main project is MyOS, a second brain",
                     "I always train in the morning before work",
                     "I decided to drop Tauri and go native Swift"] {
            XCTAssertNil(MemoryBank.judge(mem(fact), against: []), fact)
        }
    }

    func testTodaysDiaryIsNotAMemory() {
        for line in ["I ate dosa today", "I'm tired this morning", "I had lunch late yesterday"] {
            XCTAssertEqual(MemoryBank.judge(mem(line), against: []), .ephemeral, line)
        }
    }

    /// "I always eat dosa for breakfast" is a preference even though it mentions
    /// breakfast — a durable phrasing beats an ephemeral word.
    func testDurablePhrasingBeatsAnEphemeralWord() {
        XCTAssertNil(MemoryBank.judge(mem("I always eat dosa for breakfast, every single day"),
                                      against: []))
    }

    func testSecretsAreNeverInferred() {
        for secret in ["His password is hunter2 for everything",
                       "The API key is sk-abcdef123456",
                       "Card number ends 4242 and the pin is 1102"] {
            XCTAssertEqual(MemoryBank.judge(mem(secret), against: []), .sensitive, secret)
        }
    }

    /// …but if he explicitly asks, it is his call, not ours.
    func testStatedMemoriesBypassTheDurabilityTests() {
        let stated = mem("The garage door code is 4471", source: .stated)
        XCTAssertNil(MemoryBank.judge(stated, against: []),
                     "an explicit 'remember this' is the user's decision to make")
    }

    func testLowConfidenceGuessesAreDropped() {
        XCTAssertEqual(MemoryBank.judge(mem("He might prefer Flutter", confidence: 0.4), against: []),
                       .lowConfidence)
    }

    func testTooShortAndTooLongAreRejected() {
        XCTAssertEqual(MemoryBank.judge(mem("hi"), against: []), .tooShort)
        XCTAssertEqual(MemoryBank.judge(mem(String(repeating: "a", count: 401)), against: []), .tooLong)
    }

    func testRewordingSomethingAlreadyKnownIsADuplicate() {
        let known = [mem("Uses PostgreSQL for every project")]
        XCTAssertEqual(MemoryBank.judge(mem("Uses PostgreSQL for all his projects"), against: known),
                       .duplicate)
    }

    func testAGenuinelyNewFactIsNotADuplicate() {
        let known = [mem("Uses PostgreSQL for every project")]
        XCTAssertNil(MemoryBank.judge(mem("Deploys everything to Netlify"), against: known))
    }

    // MARK: - When to even ask the model

    func testExtractionOnlyRunsWhenSomethingLooksDurable() {
        XCTAssertTrue(MemoryBank.mightContainMemory("From now on I use Postgres"))
        XCTAssertTrue(MemoryBank.mightContainMemory("remember that my main project is MyOS"))
        XCTAssertTrue(MemoryBank.mightContainMemory("I'm building a second brain app"))

        XCTAssertFalse(MemoryBank.mightContainMemory("thanks"))
        XCTAssertFalse(MemoryBank.mightContainMemory("how do I centre a div"))
        XCTAssertFalse(MemoryBank.mightContainMemory("what's the weather like"))
    }

    /// A question about a preference is not a statement of one.
    func testQuestionsAboutPreferencesAreNotHarvested() {
        XCTAssertFalse(MemoryBank.mightContainMemory("do you remember what I always eat?"))
    }

    // MARK: - Recall

    func testRecallFindsTheRelevantMemory() {
        let bank = [
            mem("Main project is MyOS, a personal second brain", .project),
            mem("Trains for a half marathon in December", .goal),
            mem("Deploys to Netlify", .workflow)
        ]
        let hits = MemoryBank.recall(bank, for: "how is the MyOS project going?")
        XCTAssertEqual(hits.first?.content, "Main project is MyOS, a personal second brain")
    }

    /// The whole point of ranking: an unrelated question must not drag the whole
    /// bank into the prompt.
    func testUnrelatedQuestionsDoNotPullInEverything() {
        let bank = [
            mem("Deploys to Netlify", .workflow),
            mem("Trains for a half marathon in December", .goal)
        ]
        XCTAssertTrue(MemoryBank.recall(bank, for: "what is the capital of France").isEmpty)
    }

    /// Identity and preferences shape *how* to answer, so they get a small lift
    /// and survive questions they don't literally match.
    func testIdentityAndPreferencesRideAlong() {
        let bank = [mem("Prefers blunt, short answers with no preamble", .preference)]
        XCTAssertFalse(MemoryBank.recall(bank, for: "what is the capital of France").isEmpty)
    }

    func testPinnedMemoriesAlwaysComeBack() {
        let bank = [mem("Allergic to peanuts", .identity, pinned: true),
                    mem("Deploys to Netlify", .workflow)]
        let hits = MemoryBank.recall(bank, for: "something completely unrelated")
        XCTAssertEqual(hits.first?.content, "Allergic to peanuts")
    }

    func testRecallRespectsItsLimit() {
        let bank = (1...30).map { mem("Fact number \($0) about postgres", .project) }
        XCTAssertEqual(MemoryBank.recall(bank, for: "postgres", limit: 5).count, 5)
    }

    // MARK: - How memory reaches the prompt

    func testUnconfirmedMemoriesAreHedgedInThePrompt() {
        let lines = MemoryBank.promptLines([
            mem("Probably prefers Flutter", .preference, confidence: 0.7),
            mem("Main project is MyOS", .project, source: .stated)
        ])
        XCTAssertTrue(lines[0].contains("(unconfirmed)"))
        XCTAssertFalse(lines[1].contains("(unconfirmed)"))
        XCTAssertTrue(lines[1].contains("[project]"), "category is tagged so the model can weigh it")
    }
}
