import SwiftUI

/// The whole person in one place — identity, body, career, goals, achievements,
/// health, links. Every field edits in place and autosaves to `myos.profile`.
struct ProfileView: View {
    @EnvironmentObject var state: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            headerCard.knRise(0)
            identityCard.knRise(1)
            bodyCard.knRise(2)
            careerCard.knRise(3)
            goalsCard.knRise(4)
            achievementsCard.knRise(5)
            healthCard.knRise(6)
            linksCard.knRise(7)
        }
    }

    // MARK: - Header

    private var headerCard: some View {
        Card {
            HStack(spacing: 16) {
                ZStack {
                    Circle()
                        .fill(LinearGradient(colors: [Palette.brand, Palette.brandDeep],
                                             startPoint: .top, endPoint: .bottom))
                    Text(initials)
                        .font(.system(size: 24, weight: .bold))
                        .foregroundStyle(.white)
                }
                .frame(width: 64, height: 64)
                .knShadow()

                VStack(alignment: .leading, spacing: 5) {
                    Text(state.profile.name.isEmpty ? "Your name" : state.profile.name)
                        .font(.system(size: 24, weight: .semibold)).foregroundStyle(Palette.text)
                    Text(state.profile.role)
                        .font(.system(size: 13)).foregroundStyle(Palette.muted)
                    HStack(spacing: 8) {
                        if let age = state.profile.age { factChip("number", "\(age) yrs") }
                        if !state.profile.bloodGroup.isEmpty { factChip("drop.fill", state.profile.bloodGroup) }
                        if !state.profile.city.isEmpty { factChip("mappin.and.ellipse", state.profile.city) }
                        if !state.profile.relationship.isEmpty { factChip("heart.fill", state.profile.relationship) }
                    }
                    .padding(.top, 2)
                }
                Spacer()
            }
        }
    }

    private func factChip(_ icon: String, _ text: String) -> some View {
        HStack(spacing: 5) {
            Image(systemName: icon).font(.system(size: 9, weight: .semibold))
            Text(text).font(.system(size: 11, weight: .medium)).lineLimit(1)
        }
        .foregroundStyle(Palette.muted)
        .padding(.horizontal, 9).padding(.vertical, 4)
        .background(Palette.surface2.opacity(0.7), in: Capsule())
        .overlay(Capsule().strokeBorder(Palette.border, lineWidth: 1))
    }

    private var initials: String {
        let parts = state.profile.name.split(separator: " ").prefix(2)
        let letters = parts.compactMap { $0.first.map(String.init) }.joined()
        return letters.isEmpty ? "?" : letters.uppercased()
    }

    // MARK: - Identity

    private let fieldCols = [GridItem(.adaptive(minimum: 230), spacing: 12)]

    private var identityCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 14) {
                SectionTitle(text: "Identity")
                LazyVGrid(columns: fieldCols, spacing: 12) {
                    field("Full name", \.name, "Your name")
                    field("Date of birth", \.dob, "yyyy-mm-dd")
                    intField("Age", get: { state.profile.age },
                             set: { v in state.updateProfile { $0.age = v } }, placeholder: "Age")
                    field("Blood group", \.bloodGroup, "O+ / A+ / B+ …")
                    field("Relationship", \.relationship, "Single / …")
                    field("Phone", \.phone, "+91 …")
                    field("Email", \.email, "you@mail.com")
                    field("City", \.city, "City")
                    field("Hometown", \.hometown, "Hometown")
                    field("Education", \.education, "College, year")
                }
            }
        }
    }

    // MARK: - Body

    private var bodyCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 14) {
                SectionTitle(text: "Body")
                LazyVGrid(columns: fieldCols, spacing: 12) {
                    doubleField("Height (cm)", get: { state.profile.heightCm },
                                set: { v in state.updateProfile { $0.heightCm = v } }, placeholder: "172")
                    // Editable — writes today's Fitness log, so the two tabs stay in sync.
                    doubleField("Weight (kg)", get: { state.latestWeightKg },
                                set: { v in state.setTodayWeight(v) }, placeholder: "72")
                    readOnly("BMI", bmiText, hint: bmiCategory)
                }
            }
        }
    }

    private var bmiText: String {
        guard let h = state.profile.heightCm, h > 0, let w = state.latestWeightKg else { return "—" }
        let m = h / 100
        return String(format: "%.1f", w / (m * m))
    }

    private var bmiCategory: String {
        guard let h = state.profile.heightCm, h > 0, let w = state.latestWeightKg else {
            return "needs height + weight"
        }
        let bmi = w / ((h / 100) * (h / 100))
        switch bmi {
        case ..<18.5: return "underweight"
        case ..<25:   return "normal range"
        case ..<30:   return "overweight"
        default:      return "obese range"
        }
    }

    // MARK: - Career

    private var careerCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 14) {
                SectionTitle(text: "Career")
                LazyVGrid(columns: fieldCols, spacing: 12) {
                    field("Role", \.role, "Title — Company")
                    // Editable — writes Finance meta, so the Finance tab stays in sync.
                    moneyField("Monthly income (₹)", get: { state.finance.meta.monthlyIncomeInr },
                               set: { v in var m = state.finance.meta; m.monthlyIncomeInr = v
                                          state.saveFinanceMeta(m) }, placeholder: "40000")
                }
                labelled("What I do") {
                    TextField("", text: bind(\.work),
                              prompt: Text("One line on the work…").foregroundColor(Palette.faint))
                        .textFieldStyle(.plain).font(.system(size: 13)).foregroundStyle(Palette.text)
                        .knField()
                }
            }
        }
    }

    // MARK: - Goals

    private var goalsCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 16) {
                SectionTitle(text: "Goals")
                GoalList(title: "Short term", color: Palette.green, items: state.profile.goalsShort,
                         add: { s in state.updateProfile { $0.goalsShort.append(s) } },
                         remove: { i in state.updateProfile { $0.goalsShort.remove(at: i) } })
                GoalList(title: "Mid term", color: Palette.blue, items: state.profile.goalsMid,
                         add: { s in state.updateProfile { $0.goalsMid.append(s) } },
                         remove: { i in state.updateProfile { $0.goalsMid.remove(at: i) } })
                GoalList(title: "Long term", color: Palette.purple, items: state.profile.goalsLong,
                         add: { s in state.updateProfile { $0.goalsLong.append(s) } },
                         remove: { i in state.updateProfile { $0.goalsLong.remove(at: i) } })
            }
        }
    }

    // MARK: - Achievements

    private var achievementsCard: some View {
        Card {
            AchievementsEditor()
        }
    }

    // MARK: - Health

    private var healthCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 10) {
                SectionTitle(text: "Health notes")
                HealthEditor()
            }
        }
    }

    // MARK: - Links

    private var linksCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 12) {
                SectionTitle(text: "Links")
                linkRow("globe", "Website", \.website)
                linkRow("camera.fill", "Instagram", \.instagram)
                linkRow("chevron.left.forwardslash.chevron.right", "GitHub", \.github)
            }
        }
    }

    private func linkRow(_ icon: String, _ label: String,
                         _ keyPath: WritableKeyPath<Profile, String>) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .semibold)).foregroundStyle(Palette.muted)
                .frame(width: 22)
            Text(label).font(.system(size: 12, weight: .medium)).foregroundStyle(Palette.muted)
                .frame(width: 74, alignment: .leading)
            TextField("", text: bind(keyPath),
                      prompt: Text("https://…").foregroundColor(Palette.faint))
                .textFieldStyle(.plain).font(.system(size: 13)).foregroundStyle(Palette.text)
            if let url = URL(string: state.profile[keyPath: keyPath]),
               url.scheme?.hasPrefix("http") == true {
                Button { NSWorkspace.shared.open(url) } label: {
                    Image(systemName: "arrow.up.right").font(.system(size: 11, weight: .bold))
                }
                .buttonStyle(KIconButtonStyle(size: 24))
                .help("Open \(label)")
            }
        }
    }

    // MARK: - Field helpers

    private func bind(_ keyPath: WritableKeyPath<Profile, String>) -> Binding<String> {
        Binding(get: { state.profile[keyPath: keyPath] },
                set: { v in state.updateProfile { $0[keyPath: keyPath] = v } })
    }

    private func field(_ label: String, _ keyPath: WritableKeyPath<Profile, String>,
                       _ placeholder: String) -> some View {
        labelled(label) {
            TextField("", text: bind(keyPath),
                      prompt: Text(placeholder).foregroundColor(Palette.faint))
                .textFieldStyle(.plain).font(.system(size: 13)).foregroundStyle(Palette.text)
                .knField()
        }
    }

    private func intField(_ label: String, get: @escaping () -> Int?,
                          set: @escaping (Int?) -> Void, placeholder: String) -> some View {
        labelled(label) {
            TextField("", text: Binding(get: { get().map(String.init) ?? "" },
                                        set: { set(Int($0.trimmingCharacters(in: .whitespaces))) }),
                      prompt: Text(placeholder).foregroundColor(Palette.faint))
                .textFieldStyle(.plain).font(.system(size: 13)).foregroundStyle(Palette.text)
                .knField()
        }
    }

    private func doubleField(_ label: String, get: @escaping () -> Double?,
                             set: @escaping (Double?) -> Void, placeholder: String) -> some View {
        labelled(label) {
            TextField("", text: Binding(get: { get().map { Fmt.trimKg($0) } ?? "" },
                                        set: { set(Double($0.trimmingCharacters(in: .whitespaces))) }),
                      prompt: Text(placeholder).foregroundColor(Palette.faint))
                .textFieldStyle(.plain).font(.system(size: 13)).foregroundStyle(Palette.text)
                .knField()
        }
    }

    /// Whole-rupee money field (no decimals) — writes 0 when cleared.
    private func moneyField(_ label: String, get: @escaping () -> Double,
                            set: @escaping (Double) -> Void, placeholder: String) -> some View {
        labelled(label) {
            TextField("", text: Binding(get: { get() == 0 ? "" : String(Int(get().rounded())) },
                                        set: { set(Double($0.filter { $0.isNumber }) ?? 0) }),
                      prompt: Text(placeholder).foregroundColor(Palette.faint))
                .textFieldStyle(.plain).font(.system(size: 13)).foregroundStyle(Palette.text)
                .monospacedDigit()
                .knField()
        }
    }

    private func readOnly(_ label: String, _ value: String, hint: String) -> some View {
        labelled(label) {
            HStack(spacing: 8) {
                Text(value)
                    .font(.system(size: 13, weight: .semibold)).monospacedDigit()
                    .foregroundStyle(Palette.text)
                Spacer()
                Text(hint).font(.system(size: 10)).foregroundStyle(Palette.faint)
            }
            .padding(.horizontal, 12).padding(.vertical, 10)
            .background(Palette.surface2.opacity(0.35),
                        in: RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                .strokeBorder(Palette.border, lineWidth: 1))
        }
    }

    private func labelled<V: View>(_ label: String, @ViewBuilder content: () -> V) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(label.uppercased())
                .font(.system(size: 9, weight: .semibold)).tracking(0.7)
                .foregroundStyle(Palette.faint)
            content()
        }
    }
}

// MARK: - Goal list (add / remove, colored bullets)

private struct GoalList: View {
    let title: String
    let color: Color
    let items: [String]
    let add: (String) -> Void
    let remove: (Int) -> Void
    @State private var text = ""
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 7) {
                Circle().fill(color).frame(width: 7, height: 7)
                Text(title).font(.system(size: 12, weight: .semibold)).foregroundStyle(Palette.text)
            }
            ForEach(Array(items.enumerated()), id: \.offset) { i, item in
                HStack(spacing: 9) {
                    Image(systemName: "target").font(.system(size: 10)).foregroundStyle(color)
                    Text(item).font(.system(size: 13)).foregroundStyle(Palette.text)
                    Spacer()
                    Button { remove(i) } label: {
                        Image(systemName: "xmark").font(.system(size: 10, weight: .bold))
                    }
                    .buttonStyle(KIconButtonStyle(size: 22))
                }
                .padding(.leading, 2)
            }
            HStack(spacing: 8) {
                TextField("", text: $text,
                          prompt: Text("Add a \(title.lowercased()) goal…").foregroundColor(Palette.faint))
                    .textFieldStyle(.plain).font(.system(size: 13)).foregroundStyle(Palette.text)
                    .focused($focused)
                    .onSubmit(commit)
                Button(action: commit) {
                    Image(systemName: "plus.circle.fill").font(.system(size: 16)).foregroundStyle(color)
                }
                .buttonStyle(KPressStyle())
                .opacity(text.isEmpty ? 0.35 : 1)
                .disabled(text.isEmpty)
            }
            .knField(focused: focused)
            // No-data-loss: typed-but-unsubmitted text is saved when the field
            // loses focus or the view goes away (tab switch), not just on Enter.
            .onChange(of: focused) { _, now in if !now { commit() } }
            .onDisappear { commit() }
        }
    }

    private func commit() {
        let t = text.trimmingCharacters(in: .whitespaces)
        guard !t.isEmpty else { return }
        add(t); text = ""
    }
}

// MARK: - Achievements timeline editor

private struct AchievementsEditor: View {
    @EnvironmentObject var state: AppState
    @State private var year = ""
    @State private var title = ""
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionTitle(text: "Achievements")

            if state.profile.achievements.isEmpty {
                Text("Nothing yet — log the wins as they land.")
                    .font(.system(size: 13)).foregroundStyle(Palette.faint)
            }

            ForEach(state.profile.achievements) { m in
                HStack(alignment: .top, spacing: 11) {
                    Text(m.year.isEmpty ? "—" : m.year)
                        .font(.system(size: 11, weight: .bold)).monospacedDigit()
                        .foregroundStyle(Palette.amber)
                        .padding(.horizontal, 8).padding(.vertical, 3)
                        .background(Palette.amber.opacity(0.12), in: Capsule())
                    VStack(alignment: .leading, spacing: 2) {
                        Text(m.title).font(.system(size: 13, weight: .semibold)).foregroundStyle(Palette.text)
                        if !m.note.isEmpty {
                            Text(m.note).font(.system(size: 12)).foregroundStyle(Palette.muted)
                        }
                    }
                    Spacer()
                    Button {
                        state.updateProfile { $0.achievements.removeAll { $0.id == m.id } }
                    } label: {
                        Image(systemName: "xmark").font(.system(size: 10, weight: .bold))
                    }
                    .buttonStyle(KIconButtonStyle(size: 22))
                }
            }

            HStack(spacing: 8) {
                TextField("", text: $year, prompt: Text("Year").foregroundColor(Palette.faint))
                    .textFieldStyle(.plain).font(.system(size: 13)).foregroundStyle(Palette.text)
                    .frame(width: 52)
                Rectangle().fill(Palette.border).frame(width: 1, height: 16)
                TextField("", text: $title,
                          prompt: Text("What did you achieve?").foregroundColor(Palette.faint))
                    .textFieldStyle(.plain).font(.system(size: 13)).foregroundStyle(Palette.text)
                    .focused($focused)
                    .onSubmit(commit)
                Button(action: commit) {
                    Image(systemName: "plus.circle.fill").font(.system(size: 16)).foregroundStyle(Palette.amber)
                }
                .buttonStyle(KPressStyle())
                .opacity(title.isEmpty ? 0.35 : 1)
                .disabled(title.isEmpty)
            }
            .knField(focused: focused)
            // No-data-loss: a typed-but-unsubmitted achievement is saved on blur
            // or when the view goes away.
            .onChange(of: focused) { _, now in if !now { commit() } }
            .onDisappear { commit() }
        }
    }

    private func commit() {
        let t = title.trimmingCharacters(in: .whitespaces)
        guard !t.isEmpty else { return }
        let y = year.trimmingCharacters(in: .whitespaces)
        state.updateProfile { $0.achievements.insert(Milestone(year: y, title: t), at: 0) }
        title = ""; year = ""
    }
}

// MARK: - Health notes editor

private struct HealthEditor: View {
    @EnvironmentObject var state: AppState
    @FocusState private var focused: Bool

    var body: some View {
        TextEditor(text: Binding(get: { state.profile.healthNotes },
                                 set: { v in state.updateProfile { $0.healthNotes = v } }))
            .font(.system(size: 13)).foregroundStyle(Palette.text)
            .scrollContentBackground(.hidden)
            .focused($focused)
            .frame(minHeight: 64)
            .padding(10)
            .background(Palette.surface2.opacity(0.6),
                        in: RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                .strokeBorder(focused ? Palette.brand.opacity(0.7) : Palette.border, lineWidth: 1))
            .animation(.knFast, value: focused)
    }
}
