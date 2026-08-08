import SwiftUI

/// One place to edit everything and manage the data. Every editor here writes the
/// same state the feature tabs do, so a change in Settings shows up there and vice
/// versa. Destructive actions are guarded by a hold-to-confirm.
struct SettingsView: View {
    @EnvironmentObject var state: AppState

    private let fieldCols = [GridItem(.adaptive(minimum: 230), spacing: 12)]

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Settings").font(.system(size: 24, weight: .semibold)).foregroundStyle(Palette.text)
                .knRise(0)

            accountCard.knRise(1)
            identityCard.knRise(2)
            AgentSettingsCard().knRise(3)
            AIProvidersCard().knRise(3)
            fitnessCard.knRise(3)
            financeCard.knRise(4)
            growwCard.knRise(5)
            presetsCard.knRise(6)
            dataCard.knRise(7)
        }
    }

    // MARK: - Live prices

    private var growwCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 10) {
                SectionTitle(text: "Live prices")
                Text("Live prices come free from Yahoo Finance — no key or token needed. Set a ticker on each holding (ITC.NS for NSE, TCS.BO for BSE, AAPL for US), then tap “Live prices” in Invest. US holdings are auto-converted to INR.")
                    .font(.system(size: 12)).foregroundStyle(Palette.muted)
                    .fixedSize(horizontal: false, vertical: true)
                if let ts = state.growwLastRefresh {
                    Text("Last live refresh: \(Fmt.day(ts))").font(.system(size: 10)).foregroundStyle(Palette.green)
                }
            }
        }
    }

    // MARK: - Account

    private var accountCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 12) {
                SectionTitle(text: "Account")
                HStack(spacing: 10) {
                    Image(systemName: "person.crop.circle.fill")
                        .font(.system(size: 22)).foregroundStyle(Palette.blue)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(state.username.isEmpty ? "Signed in" : "@\(state.username)")
                            .font(.system(size: 14, weight: .semibold)).foregroundStyle(Palette.text)
                        Text("Your data syncs to your MyOS account.")
                            .font(.system(size: 11)).foregroundStyle(Palette.faint)
                    }
                    Spacer()
                    Button { Task { await state.refresh() } } label: { Text("Refresh") }
                        .buttonStyle(KSecondaryButtonStyle())
                    Button { Task { await state.logout() } } label: { Text("Log out") }
                        .buttonStyle(KGhostButtonStyle(color: Palette.faint))
                }
                if let err = state.lastSyncError ?? state.lastHydrateError {
                    Label(err, systemImage: "exclamationmark.triangle.fill")
                        .font(.system(size: 12)).foregroundStyle(Palette.amber)
                }
            }
        }
    }

    // MARK: - Profile & identity (writes state.profile — same as the Profile tab)

    private var identityCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    SectionTitle(text: "Profile & identity")
                    Spacer()
                    Text("syncs with the Profile tab").font(.system(size: 10)).foregroundStyle(Palette.faint)
                }
                LazyVGrid(columns: fieldCols, spacing: 12) {
                    KLabeledField(label: "Full name", placeholder: "Your name", text: pf(\.name))
                    KLabeledField(label: "Date of birth", placeholder: "yyyy-mm-dd", text: pf(\.dob))
                    KLabeledNumberField(label: "Age", placeholder: "Age", value: ageBinding)
                    KLabeledField(label: "Blood group", placeholder: "O+ / A+ …", text: pf(\.bloodGroup))
                    KLabeledField(label: "Relationship", placeholder: "Single / …", text: pf(\.relationship))
                    KLabeledField(label: "Phone", placeholder: "+91 …", text: pf(\.phone))
                    KLabeledField(label: "Email", placeholder: "you@mail.com", text: pf(\.email))
                    KLabeledField(label: "City", placeholder: "City", text: pf(\.city))
                    KLabeledField(label: "Hometown", placeholder: "Hometown", text: pf(\.hometown))
                    KLabeledField(label: "Education", placeholder: "College, year", text: pf(\.education))
                    KLabeledField(label: "Role", placeholder: "Title — Company", text: pf(\.role))
                    KLabeledField(label: "What I do", placeholder: "One line on the work", text: pf(\.work))
                    KLabeledField(label: "Website", placeholder: "https://…", text: pf(\.website))
                    KLabeledField(label: "Instagram", placeholder: "https://…", text: pf(\.instagram))
                    KLabeledField(label: "GitHub", placeholder: "https://…", text: pf(\.github))
                }

                VStack(alignment: .leading, spacing: 5) {
                    KFieldLabel(text: "About you — what your assistant should know")
                    TextField("", text: pf(\.about),
                              prompt: Text("Your story, work, family, goals, positioning — anything your assistant should know about you. Private: stored in your account, never in the app's code.")
                                .foregroundColor(Palette.faint),
                              axis: .vertical)
                        .textFieldStyle(.plain).font(.system(size: 13)).foregroundStyle(Palette.text)
                        .lineLimit(3...8)
                        .knField()
                }
            }
        }
    }

    // MARK: - Fitness profile (same editor as the Fitness tab)

    private var fitnessCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    SectionTitle(text: "Fitness profile")
                    Spacer()
                    Text("syncs with the Fitness tab").font(.system(size: 10)).foregroundStyle(Palette.faint)
                }
                FitnessProfileEditor()
            }
        }
    }

    // MARK: - Finance targets (same values as Finance › Edit targets)

    private var financeCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    SectionTitle(text: "Finance targets")
                    Spacer()
                    Text("syncs with the Finance tab").font(.system(size: 10)).foregroundStyle(Palette.faint)
                }
                FinanceTargetsEditor()
            }
        }
    }

    // MARK: - Journal presets

    private var presetsCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    SectionTitle(text: "Journal quick-add chips")
                    Spacer()
                    Text("shown in the Journal tab").font(.system(size: 10)).foregroundStyle(Palette.faint)
                }
                JournalPresetsEditor()
            }
        }
    }

    // MARK: - Data management (reset — hold-to-confirm)

    private var dataCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 12) {
                SectionTitle(text: "Data management")
                Text("Resets wipe that section's data on this account. Sensitive — each needs a press-and-hold to confirm.")
                    .font(.system(size: 12)).foregroundStyle(Palette.muted)
                    .fixedSize(horizontal: false, vertical: true)

                DangerResetRow(title: "Reset finance",
                               subtitle: "All transactions + targets",
                               confirmTitle: "Reset all finance data?",
                               confirmMessage: "Deletes every transaction and resets your targets. This can't be undone.") {
                    state.resetFinance()
                }
                DangerResetRow(title: "Reset portfolio",
                               subtitle: "All snapshots + holdings",
                               confirmTitle: "Reset the whole portfolio?",
                               confirmMessage: "Deletes every snapshot and holding. This can't be undone.") {
                    state.resetPortfolio()
                }
                DangerResetRow(title: "Reset journal",
                               subtitle: "Every day's entries",
                               confirmTitle: "Reset the journal?",
                               confirmMessage: "Deletes all reflections, wins, mistakes, lessons and gratitude. This can't be undone.") {
                    state.resetJournal()
                }
                DangerResetRow(title: "Reset notes",
                               subtitle: "Every note",
                               confirmTitle: "Delete all notes?",
                               confirmMessage: "Deletes every note. This can't be undone.") {
                    state.resetNotes()
                }
                DangerResetRow(title: "Reset fitness",
                               subtitle: "Logs + fitness profile",
                               confirmTitle: "Reset fitness data?",
                               confirmMessage: "Deletes every logged day and clears your fitness profile. This can't be undone.") {
                    state.resetFitness()
                }
                Divider().overlay(Palette.border).padding(.vertical, 2)
                DangerResetRow(title: "Reset everything",
                               subtitle: "All data — keeps your profile & chips",
                               confirmTitle: "Reset ALL data?",
                               confirmMessage: "Wipes finance, portfolio, journal, notes, fitness and your day plans. Your profile identity and journal chips are kept. This can't be undone.",
                               tint: Palette.red, emphatic: true) {
                    state.resetEverything()
                }
            }
        }
    }

    // MARK: - Binding helpers

    private func pf(_ kp: WritableKeyPath<Profile, String>) -> Binding<String> {
        Binding(get: { state.profile[keyPath: kp] },
                set: { v in state.updateProfile { $0[keyPath: kp] = v } })
    }
    private var ageBinding: Binding<Double?> {
        Binding(get: { state.profile.age.map(Double.init) },
                set: { v in state.updateProfile { $0.age = v.map { Int($0) } } })
    }
}

/// A destructive reset row — label + a Reset button that opens a hold-to-confirm.
private struct DangerResetRow: View {
    let title: String
    let subtitle: String
    let confirmTitle: String
    let confirmMessage: String
    var tint: Color = Palette.red
    var emphatic: Bool = false
    let action: () -> Void
    @State private var show = false

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 13, weight: emphatic ? .heavy : .semibold,
                                          design: emphatic ? .rounded : .default))
                    .foregroundStyle(emphatic ? tint : Palette.text)
                Text(subtitle).font(.system(size: 11)).foregroundStyle(Palette.faint)
            }
            Spacer()
            Button { show = true } label: {
                Label("Reset", systemImage: "trash")
            }
            .buttonStyle(KSoftButtonStyle(tint: tint))
            .holdToDelete(isPresented: $show, title: confirmTitle, message: confirmMessage,
                          confirmLabel: "Hold to reset") { action() }
        }
        .padding(.vertical, 6).padding(.horizontal, 10)
        .background(emphatic ? tint.opacity(0.06) : Color.clear,
                    in: RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
    }
}
