import XCTest
@testable import MyOS

/// Searching the second brain, and packing the result into a bounded prompt.
///
/// The hallucination tests are the important ones here: retrieval returning
/// *nothing* is what lets Catherine say "that isn't in your notes" instead of
/// inventing a decision you never made.
final class CatrineRetrievalTests: XCTestCase {

    private let today = "2026-08-19"

    private func doc(_ id: String, _ kind: DocKind, _ title: String, _ body: String,
                     _ date: String = "2026-08-01", pinned: Bool = false) -> RetrievalDoc {
        RetrievalDoc(id: id, kind: kind, title: title, body: body, date: date, pinned: pinned)
    }

    private var corpus: [RetrievalDoc] {
        [
            doc("n1", .note, "PartApp architecture",
                "Decided to go with a single Postgres database and server-side rendering. Rejected the microservices split — too much overhead for one developer.",
                "2026-03-12"),
            doc("n2", .note, "Grocery list", "Milk, eggs, coffee, oats.", "2026-08-18"),
            doc("n3", .note, "Camera settings", "Shoot at 4K 24fps, shutter 1/50, ISO under 800.", "2026-05-02"),
            doc("j1", .journal, "Journal 2026-04-02",
                "Wins: shipped the PartApp migration. Mistakes: skipped the gym again.", "2026-04-02"),
            doc("e1", .event, "Goa trip", "Five days, went with Ravi.", "2026-01-20")
        ]
    }

    // MARK: - Finding the right thing

    func testFindsTheArchitectureDecision() {
        let hits = Retriever.search("what architecture did I choose for PartApp",
                                    in: corpus, today: today)
        XCTAssertEqual(hits.first?.doc.id, "n1")
        XCTAssertTrue(hits.first!.doc.snippet().contains("Postgres"))
    }

    /// The question that must NOT invent an answer.
    func testNothingMatchesReturnsNothing() {
        XCTAssertTrue(Retriever.search("what did I decide about the Kubernetes cluster",
                                       in: corpus, today: today).isEmpty,
                      "no match must mean no results, so the model is told to say it doesn't know")
    }

    func testAnEmptyQueryRetrievesNothing() {
        XCTAssertTrue(Retriever.search("", in: corpus, today: today).isEmpty)
        XCTAssertTrue(Retriever.search("the and of is", in: corpus, today: today).isEmpty,
                      "stop words alone carry no signal")
    }

    func testTitleMatchesOutrankBodyMatches() {
        let docs = [
            doc("body", .note, "Random thoughts", "I was thinking about the camera and the camera bag."),
            doc("title", .note, "Camera", "Notes about something else entirely.")
        ]
        XCTAssertEqual(Retriever.search("camera", in: docs, today: today).first?.doc.id, "title")
    }

    func testSearchCanBeScopedToOneKind() {
        let journalOnly = corpus.filter { $0.kind == .journal }
        let hits = Retriever.search("PartApp", in: journalOnly, today: today)
        XCTAssertEqual(hits.count, 1)
        XCTAssertEqual(hits.first?.doc.kind, .journal)
    }

    func testResultsAreCapped() {
        let many = (1...40).map { doc("d\($0)", .note, "Postgres note \($0)", "postgres postgres") }
        XCTAssertEqual(Retriever.search("postgres", in: many, limit: 3, today: today).count, 3)
    }

    // MARK: - Recency

    func testRecentBeatsOldWhenBothMatchEqually() {
        let docs = [
            doc("old", .note, "Deploy plan", "Deploy to Netlify.", "2024-01-01"),
            doc("new", .note, "Deploy plan", "Deploy to Netlify.", "2026-08-18")
        ]
        XCTAssertEqual(Retriever.search("deploy netlify", in: docs, today: today).first?.doc.id, "new")
    }

    /// But an old decision is still the decision — recency lifts, it never erases.
    func testOldDocumentsAreStillFound() {
        let docs = [doc("ancient", .note, "The big decision", "We chose Postgres.", "2019-06-01")]
        XCTAssertFalse(Retriever.search("postgres decision", in: docs, today: today).isEmpty)
    }

    func testRecencyLiftIsBounded() {
        XCTAssertEqual(Retriever.recencyLift(today, today: today), 1.5, accuracy: 0.01)
        XCTAssertEqual(Retriever.recencyLift("2010-01-01", today: today), 1.0, accuracy: 0.01)
        XCTAssertEqual(Retriever.recencyLift("", today: today), 1.0, "undated documents are not punished")
    }

    // MARK: - Snippets

    func testLongBodiesAreCutHonestlyRatherThanParaphrased() {
        let long = String(repeating: "Some sentence about the build. ", count: 60)
        let snippet = doc("x", .note, "Build", long).snippet(limit: 100)
        XCTAssertLessThanOrEqual(snippet.count, 110)
        XCTAssertTrue(snippet.hasSuffix("…"), "a cut is marked, so nothing reads as complete when it isn't")
    }

    func testShortBodiesAreLeftAlone() {
        XCTAssertEqual(doc("x", .note, "T", "Short.").snippet(), "Short.")
    }

    // MARK: - Tokenising

    func testStopWordsAndPluralsAreNormalised() {
        XCTAssertEqual(TextIndex.terms("What are my projects about?"), ["project"])
        XCTAssertEqual(TextIndex.terms("running builds"), ["runn", "build"])
    }

    /// Product and project names must survive intact — mangling them is how a
    /// search for "MyOS" stops finding MyOS.
    func testProperNounsSurvive() {
        XCTAssertTrue(TextIndex.terms("MyOS and PartApp").contains("myo") == false)
        XCTAssertEqual(TextIndex.terms("MyOS PartApp"), ["myos", "partapp"])
    }

    // MARK: - Context assembly

    private func section(_ heading: String, _ count: Int, _ priority: Int, minLines: Int = 1) -> ContextSection {
        ContextSection(heading: heading,
                       lines: (1...count).map { "line \($0) padded out to a reasonable length here" },
                       priority: priority, minLines: minLines)
    }

    func testEverythingFitsWhenTheBudgetIsGenerous() {
        let r = ContextBuilder.assemble([section("A", 3, 0), section("B", 3, 1)], budget: 5000)
        XCTAssertEqual(r.includedHeadings, ["A", "B"])
        XCTAssertTrue(r.droppedHeadings.isEmpty)
    }

    func testHighestPriorityWinsWhenTheBudgetIsTight() {
        let r = ContextBuilder.assemble([section("LOW", 6, 9, minLines: 6),
                                         section("HIGH", 2, 0)], budget: 240)
        XCTAssertTrue(r.includedHeadings.contains("HIGH"))
        XCTAssertTrue(r.droppedHeadings.contains("LOW"))
    }

    /// Half a list is worse than none — the model reads whatever survives as the
    /// complete picture.
    func testASectionThatCannotMeetItsMinimumIsDroppedWhole() {
        let r = ContextBuilder.assemble([section("MEMORIES", 5, 0, minLines: 5)], budget: 90)
        XCTAssertTrue(r.includedHeadings.isEmpty)
        XCTAssertEqual(r.droppedHeadings, ["MEMORIES"])
    }

    func testTruncationIsAnnounced() {
        let r = ContextBuilder.assemble([section("NOTES", 8, 0, minLines: 1)], budget: 320)
        XCTAssertTrue(r.text.contains("more not shown"),
                      "a clipped list says so rather than pretending to be everything")
    }

    func testEmptySectionsNeverReachThePrompt() {
        let r = ContextBuilder.assemble([ContextSection(heading: "EMPTY", lines: [], priority: 0),
                                         section("REAL", 1, 1)], budget: 5000)
        XCTAssertEqual(r.includedHeadings, ["REAL"])
    }

    func testAssemblyNeverExceedsItsBudget() {
        let r = ContextBuilder.assemble([section("A", 20, 0), section("B", 20, 1)], budget: 500)
        XCTAssertLessThanOrEqual(r.characters, 500)
    }

    // MARK: - Tool declarations

    func testEveryToolIsWellFormed() {
        XCTAssertFalse(CatrineToolbox.all.isEmpty)
        for t in CatrineToolbox.all {
            XCTAssertFalse(t.description.isEmpty, t.name)
            XCTAssertEqual(t.parameters["type"] as? String, "object", t.name)
            XCTAssertNotNil(t.parameters["properties"], t.name)
            // Required arguments must actually exist in the schema, or the model
            // is being asked for a field it cannot see.
            let props = t.parameters["properties"] as? [String: Any] ?? [:]
            for r in t.parameters["required"] as? [String] ?? [] {
                XCTAssertNotNil(props[r], "\(t.name) requires \(r) but doesn't declare it")
            }
        }
    }

    func testToolNamesAreUnique() {
        let names = CatrineToolbox.all.map(\.name)
        XCTAssertEqual(Set(names).count, names.count)
    }

    func testReadToolsAreNotMarkedAsMutating() {
        for name in ["search_brain", "search_notes", "search_memory", "get_todos"] {
            XCTAssertEqual(CatrineToolbox.byName(name)?.mutates, false, name)
        }
        for name in ["remember", "forget", "create_note"] {
            XCTAssertEqual(CatrineToolbox.byName(name)?.mutates, true, name)
        }
    }

    func testWireFormatCarriesTheSchema() {
        let wire = CatrineToolbox.wireFormat()
        XCTAssertEqual(wire.count, CatrineToolbox.all.count)
        let brain = wire.first { $0["name"] as? String == "search_brain" }
        XCTAssertNotNil(brain?["parameters"])
    }
}
