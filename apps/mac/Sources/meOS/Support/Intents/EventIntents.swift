import AppIntents
import Foundation
import SwiftUI

// Siri reads `errorDescription` back verbatim when an intent throws.
extension EventIntentError: CustomLocalizedStringResourceConvertible {
    var localizedStringResource: LocalizedStringResource {
        LocalizedStringResource(stringLiteral: errorDescription ?? "Something went wrong.")
    }
}

// MARK: - Queries

/// "Hey Siri, what's coming up in meOS?"
struct UpcomingEventsIntent: AppIntent {
    static var title: LocalizedStringResource = "Upcoming Events"
    static var description = IntentDescription(
        "Hear the next events logged in meOS, with how far away each one is.")
    /// The whole point is a spoken answer without meOS appearing.
    static var openAppWhenRun = false

    @Parameter(title: "How many", default: 3, inclusiveRange: (1, 10))
    var count: Int

    static var parameterSummary: some ParameterSummary {
        Summary("Get the next \(\.$count) events from meOS")
    }

    func perform() async throws -> some IntentResult & ProvidesDialog & ShowsSnippetView {
        let today = EventVoice.key(from: Date())
        let picked = EventVoice.upcoming(try await EventIntentStore().loadEvents(),
                                         today: today, limit: count)
        let line = EventVoice.spokenUpcoming(picked, today: today)
        return .result(dialog: IntentDialog(stringLiteral: line),
                       view: EventSnippet(heading: "Coming up", events: picked, today: today))
    }
}

/// "Hey Siri, what were my recent events in meOS?"
struct PastEventsIntent: AppIntent {
    static var title: LocalizedStringResource = "Past Events"
    static var description = IntentDescription(
        "Hear the events most recently logged in meOS, newest first.")
    static var openAppWhenRun = false

    @Parameter(title: "How many", default: 3, inclusiveRange: (1, 10))
    var count: Int

    static var parameterSummary: some ParameterSummary {
        Summary("Get the last \(\.$count) events from meOS")
    }

    func perform() async throws -> some IntentResult & ProvidesDialog & ShowsSnippetView {
        let today = EventVoice.key(from: Date())
        let picked = EventVoice.past(try await EventIntentStore().loadEvents(),
                                     today: today, limit: count)
        let line = EventVoice.spokenPast(picked, today: today)
        return .result(dialog: IntentDialog(stringLiteral: line),
                       view: EventSnippet(heading: "Recently", events: picked, today: today))
    }
}

// MARK: - Create

/// "Hey Siri, add an event to meOS" → asks for the title and the date.
struct CreateEventIntent: AppIntent {
    static var title: LocalizedStringResource = "Add Event"
    static var description = IntentDescription("Log a new event in meOS.")
    static var openAppWhenRun = false

    @Parameter(title: "Event", requestValueDialog: "What's the event?")
    var eventTitle: String

    /// Siri resolves the spoken date ("next Friday", "March 12") before we see it.
    /// Only the day is kept — events are day-keyed, not timed.
    @Parameter(title: "Date", requestValueDialog: "When is it?")
    var date: Date

    static var parameterSummary: some ParameterSummary {
        Summary("Add \(\.$eventTitle) to meOS on \(\.$date)")
    }

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let clean = EventVoice.cleanTitle(eventTitle)
        guard !clean.isEmpty else { throw $eventTitle.needsValueError("What's the event?") }

        let today = EventVoice.key(from: Date())
        let key = EventVoice.key(from: date)

        // Siri's date grammar is the weak link — "next week Friday" has come back as
        // 1 January the following year. Anything years off is a parse failure, not a
        // plan, so refuse it outright and make the user say it again.
        guard EventVoice.isPlausible(key, today: today) else {
            throw $date.needsValueError(
                "I heard \(EventVoice.spokenDate(key, today: today)), which doesn't look right. When is it?")
        }

        // Read the resolved date back before writing. A silent wrong write is the
        // failure worth designing out — the year is spoken whenever it isn't this
        // one, so a mis-parse is audible rather than plausible-sounding.
        try await requestConfirmation(
            result: .result(dialog: IntentDialog(stringLiteral:
                "Add \(clean) on \(EventVoice.spokenDate(key, today: today))?")))

        let item = try await EventIntentStore().addEvent(title: clean, dateKey: key)
        let tag = item.tagIDs.first.flatMap { id in
            ["travel": "travel", "family": "family", "work": "work",
             "personal": "personal", "milestone": "a milestone",
             "reminder": "a reminder", "other": "other"][id]
        } ?? "personal"
        let spoken = EventVoice.spokenCreated(title: clean, date: key, today: today)
            .dropLast() // strip trailing period
        return .result(dialog: IntentDialog(stringLiteral: "\(spoken) as \(tag)."))
    }
}

// MARK: - Snippet

/// The little card Siri shows alongside the spoken answer. Plain system styling —
/// it renders inside Siri's own chrome, not the app's theme.
struct EventSnippet: View {
    let heading: String
    let events: [EventItem]
    let today: String

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(heading.uppercased())
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)

            if events.isEmpty {
                Text("Nothing here yet.").font(.body).foregroundStyle(.secondary)
            } else {
                ForEach(events) { e in
                    HStack(alignment: .firstTextBaseline) {
                        Text(e.title).font(.body.weight(.medium))
                        Spacer(minLength: 12)
                        Text(EventVoice.relativePhrase(from: today, to: e.date))
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .padding(16)
    }
}

// MARK: - Siri phrases

/// Registered automatically once the app is installed and launched once — these
/// show up in Siri and in the Shortcuts app with no setup.
///
/// `\(.applicationName)` resolves to the app name *and* every alternative name in
/// Info.plist — which is "Catherine" here, because "meOS" spoken aloud is a
/// homophone of "iOS" and Siri transcribes it that way. So each phrase has to read
/// naturally with a person's name in the slot ("Ask Catherine what's coming up"),
/// not just with a product name ("...in meOS"). Both forms are kept.
struct meOSAppShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: UpcomingEventsIntent(),
            phrases: [
                "Ask \(.applicationName) what's coming up",
                "Ask \(.applicationName) for my upcoming events",
                "\(.applicationName) what's coming up",
                "What's coming up in \(.applicationName)",
                "What's next in \(.applicationName)",
                "Upcoming events in \(.applicationName)"
            ],
            shortTitle: "Upcoming Events",
            systemImageName: "calendar")

        AppShortcut(
            intent: PastEventsIntent(),
            phrases: [
                "Ask \(.applicationName) for my recent events",
                "Ask \(.applicationName) what happened recently",
                "\(.applicationName) recent events",
                "My recent events in \(.applicationName)",
                "Past events in \(.applicationName)"
            ],
            shortTitle: "Past Events",
            systemImageName: "clock.arrow.circlepath")

        AppShortcut(
            intent: CreateEventIntent(),
            phrases: [
                "Ask \(.applicationName) to add an event",
                "Tell \(.applicationName) to add an event",
                "\(.applicationName) add an event",
                "Add an event to \(.applicationName)",
                "New event in \(.applicationName)",
                "Log an event in \(.applicationName)"
            ],
            shortTitle: "Add Event",
            systemImageName: "calendar.badge.plus")
    }
}
