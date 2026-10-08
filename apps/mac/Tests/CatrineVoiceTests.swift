import XCTest
@testable import meOS

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

/// Speaks its sentence, then interrupts the router the way a real voice would.
private final class InterruptingSynth: SpeechSynth, @unchecked Sendable {
    var spoken: [String] = []
    weak var router: VoiceRouter?
    func speak(_ text: String) async -> Bool {
        spoken.append(text)
        router?.stop()
        return true
    }
    func stop() {}
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

    /// Real barge-in: he interrupts WHILE she is on the first sentence.
    func testStopMidReplyDropsTheQueuedSentences() async {
        let local = FakeSynth()
        let remote = InterruptingSynth()
        let router = VoiceRouter(remote: remote, local: local)
        remote.router = router
        await router.speak(reply: "One. Two. Three.")
        XCTAssertEqual(remote.spoken, ["One."], "barge-in must drop what was queued behind it")
        XCTAssertTrue(local.spoken.isEmpty, "and must not reroute the dropped sentences")
    }

    /// ...but a stop must not mute her forever. The next reply speaks normally,
    /// which is the whole point: he interrupts, she stops, he asks, she answers.
    func testANewReplyAfterAStopSpeaksAgain() async {
        let remote = FakeSynth(), local = FakeSynth()
        let router = VoiceRouter(remote: remote, local: local)
        router.stop()
        await router.speak(reply: "Still here.")
        XCTAssertEqual(remote.spoken, ["Still here."])
    }
}
