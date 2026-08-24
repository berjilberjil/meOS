import SwiftUI
#if os(iOS)
import PhotosUI
#endif

// Reusable editor blocks shared by the primary tabs and Settings, so a value
// edited in either place writes the same underlying state and stays in sync.

// MARK: - Fitness profile editor

/// Goal + targets. Height writes `Profile.heightCm` (identical to the Profile
/// tab); the rest writes `fitnessProfile`. Used in the Fitness tab and Settings.
struct FitnessProfileEditor: View {
    @EnvironmentObject var state: AppState
    private let cols = [GridItem(.adaptive(minimum: 150), spacing: 12)]

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 16) {
                VStack(alignment: .leading, spacing: 6) {
                    KFieldLabel(text: "Goal")
                    Segmented(options: FitnessGoal.allCases.map { ($0, $0.label) },
                              selection: Binding(get: { state.fitnessProfile.goal },
                                                 set: { g in state.updateFitnessProfile { $0.goal = g } }))
                }
                VStack(alignment: .leading, spacing: 6) {
                    KFieldLabel(text: "Sex")
                    Segmented(options: Sex.allCases.map { ($0, $0.label) },
                              selection: Binding(get: { state.fitnessProfile.sex },
                                                 set: { s in state.updateFitnessProfile { $0.sex = s } }))
                }
            }
            VStack(alignment: .leading, spacing: 6) {
                KFieldLabel(text: "Activity")
                activityMenu
            }
            LazyVGrid(columns: cols, spacing: 12) {
                KLabeledNumberField(label: "Height (cm)", placeholder: "172", decimals: 0,
                    value: Binding(get: { state.profile.heightCm },
                                   set: { v in state.updateProfile { $0.heightCm = v } }))
                KLabeledNumberField(label: "Target weight (kg)", placeholder: "72", decimals: 1,
                    value: Binding(get: { state.fitnessProfile.targetWeightKg },
                                   set: { v in state.updateFitnessProfile { $0.targetWeightKg = v } }))
                KLabeledNumberField(label: "Calorie target", placeholder: "2200", decimals: 0,
                    value: Binding(get: { state.fitnessProfile.calorieTargetKcal },
                                   set: { v in state.updateFitnessProfile { $0.calorieTargetKcal = v } }))
                KLabeledNumberField(label: "Protein target (g)", placeholder: "140", decimals: 0,
                    value: Binding(get: { state.fitnessProfile.proteinTargetG },
                                   set: { v in state.updateFitnessProfile { $0.proteinTargetG = v } }))
                KLabeledNumberField(label: "Water target (L)", placeholder: "3", decimals: 2,
                    value: Binding(get: { state.fitnessProfile.waterTargetMl.map { $0 / 1000 } },
                                   set: { v in state.updateFitnessProfile { $0.waterTargetMl = v.map { $0 * 1000 } } }))
            }
        }
    }

    private var activityMenu: some View {
        Menu {
            ForEach(ActivityLevel.allCases, id: \.self) { a in
                Button { state.updateFitnessProfile { $0.activity = a } } label: {
                    Text("\(a.label) — \(a.hint)")
                }
            }
        } label: {
            HStack(spacing: 6) {
                Text(state.fitnessProfile.activity.label)
                    .font(.footnote.weight(.semibold)).foregroundStyle(Palette.text)
                Text("· \(state.fitnessProfile.activity.hint)")
                    .font(.caption2).foregroundStyle(Palette.faint)
                Spacer()
                Image(systemName: "chevron.down").font(.caption2.weight(.bold)).foregroundStyle(Palette.faint)
            }
            .padding(.horizontal, 13).padding(.vertical, 10)
            .background(Palette.bg, in: RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).strokeBorder(Palette.border, lineWidth: 2))
        }
        .menuStyle(.borderlessButton).menuIndicator(.hidden)
    }
}

// MARK: - Personal details (Settings + iPhone)

/// Settings → You. The facts Catherine works from.
///
/// This used to be seven full-width boxes stacked down the screen, which is a
/// registration form, not a profile. It reads as who you are first — name, what
/// you do, where you are — and the same facts are editable underneath as label /
/// value rows, so a filled-in profile is something you skim rather than a column
/// of inputs. Every field and binding is unchanged.
struct PersonDetailsEditor: View {
    @EnvironmentObject var state: AppState
    #if os(iOS)
    @State private var picking = false
    @State private var picked: PhotosPickerItem?
    #endif

    var body: some View {
        SettingsPage {
            identity

            SettingsGroup(title: "Identity") {
                SettingsFieldRow(label: "Name", placeholder: "Your name", text: name)
                SettingsDivider(inset: SettingsMetrics.plainInset)
                SettingsFieldRow(label: "Age", placeholder: "—", numeric: true, text: age)
                SettingsDivider(inset: SettingsMetrics.plainInset)
                SettingsFieldRow(label: "City", placeholder: "Where you live", text: city)
                SettingsDivider(inset: SettingsMetrics.plainInset)
                SettingsFieldRow(label: "Hometown", placeholder: "Where you're from", text: hometown)
            }

            SettingsGroup(title: "Work") {
                SettingsFieldRow(label: "Role", placeholder: "What you do", text: role)
                SettingsDivider(inset: SettingsMetrics.plainInset)
                SettingsFieldRow(label: "Work", placeholder: "Where you do it", text: work)
            }

            SettingsGroup(title: "About",
                          footer: "Catherine reads this when she judges a scan or answers you.") {
                SettingsTextArea(
                    placeholder: "A few lines — what you’re building, what you care about, anything she should hold on to.",
                    text: about)
            }
        }
        #if os(iOS)
        .photosPicker(isPresented: $picking, selection: $picked, matching: .images)
        .onChange(of: picked) { _, item in Task { await usePicked(item) } }
        #endif
    }

    #if os(iOS)
    /// Downscaled to 320px before it goes anywhere: the profile rides inside the
    /// synced state blob, and a full camera frame in there would be felt on
    /// every sync, not just this screen.
    private func usePicked(_ item: PhotosPickerItem?) async {
        guard let item else { return }
        defer { picked = nil }
        guard let data = try? await item.loadTransferable(type: Data.self),
              let small = MediaJPEG.downscale(data, maxSide: 320, quality: 0.8)
        else { return }
        state.updateProfile { $0.photoBase64 = small.base64EncodedString() }
        Haptics.success()
    }
    #endif

    private var hasPhoto: Bool { !state.profile.photoBase64.isEmpty }

    // MARK: Who you are

    private var identity: some View {
        HStack(spacing: 16) {
            avatarButton

            VStack(alignment: .leading, spacing: 4) {
                Text(displayName)
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(hasName ? Palette.text : Palette.faint)
                    .lineLimit(2).minimumScaleFactor(0.75)
                if !workLine.isEmpty {
                    Text(workLine)
                        .font(.subheadline).foregroundStyle(Palette.muted)
                        .lineLimit(1).truncationMode(.tail)
                }
                if !placeLine.isEmpty {
                    Text(placeLine)
                        .font(.footnote).foregroundStyle(Palette.faint)
                        .lineLimit(1).truncationMode(.tail)
                }
                if workLine.isEmpty && placeLine.isEmpty {
                    Text("Fill this in and she stops guessing.")
                        .font(.footnote).foregroundStyle(Palette.faint)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 4)
    }

    /// Tap to set a photo. Once there is one, tapping offers to replace or
    /// remove it — a photo you cannot get rid of is a trap.
    @ViewBuilder
    private var avatarButton: some View {
        #if os(iOS)
        if hasPhoto {
            Menu {
                Button { picking = true } label: { Label("Change photo", systemImage: "photo") }
                Button(role: .destructive) {
                    state.updateProfile { $0.photoBase64 = "" }
                } label: { Label("Remove photo", systemImage: "trash") }
            } label: { avatar }
        } else {
            Button { picking = true } label: { avatar }
                .buttonStyle(.plain)
        }
        #else
        avatar
        #endif
    }

    private var avatar: some View {
        ZStack {
            Circle().fill(Palette.teal.opacity(0.18))
            if let photo = MediaJPEG.image(fromBase64: state.profile.photoBase64) {
                photo.resizable().scaledToFill()
            } else {
                Text(initials)
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(Palette.teal)
            }
        }
        .frame(width: 64, height: 64)
        .clipShape(Circle())
        #if os(iOS)
        .overlay(alignment: .bottomTrailing) {
            // Without this the avatar looks like decoration rather than a control.
            Image(systemName: "camera.fill")
                .font(.caption2.weight(.bold))
                .foregroundStyle(Palette.text)
                .frame(width: 22, height: 22)
                .background(Palette.surface2, in: Circle())
                .overlay(Circle().strokeBorder(Palette.bg, lineWidth: 2))
                .offset(x: 2, y: 2)
        }
        .accessibilityLabel(hasPhoto ? "Change profile photo" : "Add a profile photo")
        #endif
    }

    private var hasName: Bool { !state.profile.name.trimmingCharacters(in: .whitespaces).isEmpty }

    private var displayName: String {
        let n = state.profile.name.trimmingCharacters(in: .whitespaces)
        if !n.isEmpty { return n }
        return state.username.isEmpty ? "Add your name" : "@\(state.username)"
    }

    private var initials: String {
        let letters = state.profile.name
            .split(separator: " ").prefix(2)
            .compactMap { $0.first }
            .map(String.init).joined().uppercased()
        return letters.isEmpty ? "·" : letters
    }

    /// "Opportunist · SKCRIPT" — either half alone is fine.
    private var workLine: String {
        [state.profile.role, state.profile.work]
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .joined(separator: " · ")
    }

    /// Where you are, and where you are from when that is somewhere else.
    private var placeLine: String {
        let city = state.profile.city.trimmingCharacters(in: .whitespaces)
        let home = state.profile.hometown.trimmingCharacters(in: .whitespaces)
        if city.isEmpty { return home }
        if home.isEmpty || home.caseInsensitiveCompare(city) == .orderedSame { return city }
        return "\(city) · from \(home)"
    }

    // MARK: Bindings (unchanged)

    private var name: Binding<String> {
        Binding(get: { state.profile.name }, set: { v in state.updateProfile { $0.name = v } })
    }
    private var city: Binding<String> {
        Binding(get: { state.profile.city }, set: { v in state.updateProfile { $0.city = v } })
    }
    private var hometown: Binding<String> {
        Binding(get: { state.profile.hometown }, set: { v in state.updateProfile { $0.hometown = v } })
    }
    private var role: Binding<String> {
        Binding(get: { state.profile.role }, set: { v in state.updateProfile { $0.role = v } })
    }
    private var work: Binding<String> {
        Binding(get: { state.profile.work }, set: { v in state.updateProfile { $0.work = v } })
    }
    private var about: Binding<String> {
        Binding(get: { state.profile.about }, set: { v in state.updateProfile { $0.about = v } })
    }
    private var age: Binding<String> {
        Binding(
            get: { state.profile.age.map(String.init) ?? "" },
            set: { v in state.updateProfile { $0.age = Int(v.filter(\.isNumber)) } }
        )
    }
}

// MARK: - Journal presets editor (manage the quick-add chips)

/// Edit the six journal preset sets. Each section shows its chips (removable)
/// plus an add field. Writes `journalPresets`.
struct JournalPresetsEditor: View {
    @EnvironmentObject var state: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            section("Morning reflection", Palette.amber, \.morning)
            section("Night reflection", Palette.blue, \.night)
            section("Wins", Palette.green, \.wins)
            section("Mistakes", Palette.red, \.mistakes)
            section("Lessons", Palette.blue, \.lessons)
            section("Gratitude", Palette.purple, \.gratitude)
        }
    }

    private func section(_ title: String, _ tint: Color,
                         _ kp: WritableKeyPath<JournalPresets, [String]>) -> some View {
        JournalPresetSection(
            title: title, tint: tint, items: state.journalPresets[keyPath: kp],
            add: { s in state.updateJournalPresets { $0[keyPath: kp].append(s) } },
            remove: { i in state.updateJournalPresets { $0[keyPath: kp].remove(at: i) } })
    }
}

/// One preset section — removable chips + an add field (add-on-blur too).
private struct JournalPresetSection: View {
    let title: String
    let tint: Color
    let items: [String]
    let add: (String) -> Void
    let remove: (Int) -> Void
    @State private var text = ""
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 7) {
                Circle().fill(tint).frame(width: 7, height: 7)
                Text(title).font(.caption.weight(.semibold)).foregroundStyle(Palette.text)
            }
            if !items.isEmpty {
                FlowLayout(spacing: 7, runSpacing: 7) {
                    ForEach(Array(items.enumerated()), id: \.offset) { i, item in
                        RemovableChip(text: item, tint: tint) { remove(i) }
                    }
                }
            }
            HStack(spacing: 8) {
                TextField("", text: $text,
                          prompt: Text("Add a chip…").foregroundColor(Palette.faint))
                    .textFieldStyle(.plain).font(.footnote).foregroundStyle(Palette.text)
                    .focused($focused)
                    .onSubmit(commit)
                Button(action: commit) {
                    Image(systemName: "plus.circle.fill").font(.callout).foregroundStyle(tint)
                }
                .buttonStyle(.plain)
                .opacity(text.isEmpty ? 0.35 : 1)
                .disabled(text.isEmpty)
            }
            .knField(focused: focused)
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
