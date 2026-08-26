import Foundation

/// The controlled reasoning loop behind one chat message.
///
///   understand → is context enough? → call a tool → read the result →
///   still not enough? → answer
///
/// Deliberately bounded rather than autonomous. Every knob has a ceiling: how
/// many times it may go round, how many tools it may run in total, how long the
/// whole turn may take, and how many times a failed request is retried. The last
/// round always runs with tools switched off, so the turn cannot end with the
/// model asking for another lookup instead of answering.
extension AppState {

    /// Round trips to the model. Three means: look something up, look something
    /// else up in light of that, then answer.
    static let catrineMaxRounds = 3
    /// Total tool executions per message, across all rounds.
    static let catrineMaxToolCalls = 6
    /// Whole-turn ceiling. Past this the loop stops and answers with what it has.
    static let catrineTurnTimeout: TimeInterval = 55

    struct AgentOutcome {
        var reply: String
        var trace: CatrineTrace
    }

    /// `maxRounds` is overridable because a voice call cannot afford the full
    /// three rounds: each one is a sequential model round trip, and 35 seconds
    /// of silence on a phone call reads as broken. Voice trades one round of
    /// follow-up lookups for an answer that arrives while he is still listening.
    func runCatrineTurn(query: String,
                        turns: [APIClient.ChatTurn],
                        agent: APIClient.AgentInfo,
                        maxRounds: Int = AppState.catrineMaxRounds,
                        timeout: TimeInterval = AppState.catrineTurnTimeout) async throws -> AgentOutcome {
        var trace = CatrineTrace(query: query)
        let started = Date()
        var toolResults: [String] = []
        var executed = 0
        let toolWire = CatrineToolbox.wireFormat()

        for round in 1...max(1, maxRounds) {
            try Task.checkCancellation()
            trace.steps = round

            // Out of time switches tools off, and that IS the exit: with
            // `allowTools` false the `!allowTools` branch below returns this
            // round's answer, so the loop runs at most one more request.
            //
            // A previous attempt at "enforcing" the deadline broke out of the
            // loop here instead, which falls through to the empty-reply return
            // at the bottom — so a slow turn ended with a blank message in the
            // chat rather than a tool-less answer. The deadline was already
            // doing its job; the loop is bounded by `maxRounds` regardless.
            let outOfTime = Date().timeIntervalSince(started) > timeout
            let allowTools = round < max(1, maxRounds)
                && executed < Self.catrineMaxToolCalls
                && !outOfTime

            let ctx = catrineContext(for: query, toolResults: toolResults)
            trace.contextCharacters = ctx.assembly.characters
            trace.includedSections = ctx.assembly.includedHeadings
            trace.droppedSections = ctx.assembly.droppedHeadings
            trace.memories = ctx.memories.map(\.content)
            trace.documents = ctx.documents.map { "\($0.doc.kind.label): \($0.doc.title)" }

            let answer = try await chatWithRetry(messages: turns, context: ctx.text,
                                                 agent: agent,
                                                 tools: allowTools ? toolWire : [])
            trace.model = answer.model

            let wanted = answer.toolCalls.prefix(Self.catrineMaxToolCalls - executed)
            if !allowTools || wanted.isEmpty {
                trace.latencyMs = Int(Date().timeIntervalSince(started) * 1000)
                return AgentOutcome(reply: answer.reply, trace: trace)
            }

            for call in wanted {
                try Task.checkCancellation()
                executed += 1
                let result = runCatrineTool(call.name, call.args)
                trace.toolCalls.append("\(call.name)(\(Self.brief(call.args)))")
                toolResults.append(Self.render(call: call, result: result))
            }
        }

        // Unreachable: the final round runs with tools off and returns above.
        trace.latencyMs = Int(Date().timeIntervalSince(started) * 1000)
        return AgentOutcome(reply: "", trace: trace)
    }

    /// One request, retried once on a server-side or transport failure. A 4xx is
    /// our own bug and is not worth repeating.
    private func chatWithRetry(messages: [APIClient.ChatTurn], context: String,
                               agent: APIClient.AgentInfo,
                               tools: [[String: Any]]) async throws -> APIClient.ChatAnswer {
        var lastError: Error?
        for attempt in 1...2 {
            do {
                return try await api.chat(messages: messages, context: context,
                                          agent: agent, tools: tools)
            } catch {
                lastError = error
                let status = (error as? APIError)?.status ?? 0
                guard attempt == 1, status >= 500 || status == -1 else { throw error }
                try? await Task.sleep(nanoseconds: 800_000_000)
            }
        }
        throw lastError ?? APIError(status: -1, message: "Chat failed")
    }

    /// A tool result as the model sees it on the next round.
    private static func render(call: APIClient.ToolCall, result: [String: Any]) -> String {
        let body = (try? JSONSerialization.data(withJSONObject: result, options: [.sortedKeys]))
            .flatMap { String(data: $0, encoding: .utf8) } ?? "{}"
        return "\(call.name)(\(brief(call.args))) → \(body)"
    }

    /// Arguments, short enough to sit in a prompt line or a debug row.
    private static func brief(_ args: [String: Any]) -> String {
        args.keys.sorted().map { "\($0)=\(String(describing: args[$0] ?? "").prefix(60))" }
            .joined(separator: ", ")
    }
}
