import SwiftUI
import AppKit

/// The whole person in one place — identity, body, career, goals, achievements,
/// health, links. Read-only by default; tap **Edit profile** to change anything, then
/// **Done**. Autosaves to `myos.profile` while editing.
struct ProfileView: View {
    @EnvironmentObject var state: AppState
    @State private var isEditing = false
    @State private var weightDraft = ""
    @State private var showRemovePhoto = false
    @FocusState private var weightFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: Gap.screen) {
            // Nine cards, nine colours — a profile is a set of unrelated
            // facets, and one tint for all of them made it read as a form.
            headerCard.knRise(0)
            identityCard.knRise(1)
            bodyCard.knRise(2)
            careerCard.knRise(3)
            aboutCard.knRise(4)
            goalsCard.knRise(5)
            achievementsCard.knRise(6)
            healthCard.knRise(7)
            linksCard.knRise(8)
        }
    }

    // MARK: - Header

    private var headerCard: some View {
        Card {
            HStack(spacing: 16) {
                avatar

                VStack(alignment: .leading, spacing: 5) {
                    Text(state.profile.name.isEmpty ? "Your name" : state.profile.name)
                        .font(.title2.weight(.semibold)).foregroundStyle(Palette.text)
                    Text(state.profile.role)
                        .font(.footnote).foregroundStyle(Palette.muted)
                    HStack(spacing: 8) {
                        if let age = state.profile.age { factChip("number", "\(age) yrs") }
                        if !state.profile.bloodGroup.isEmpty { factChip("drop.fill", state.profile.bloodGroup) }
                        if !state.profile.city.isEmpty { factChip("mappin.and.ellipse", state.profile.city) }
                        if !state.profile.relationship.isEmpty { factChip("heart.fill", state.profile.relationship) }
                    }
                    .padding(.top, 2)
                }
                Spacer()
                editButton
            }
        }
    }

    @ViewBuilder private var editButton: some View {
        if isEditing {
            Button { withAnimation(.knFast) { isEditing = false } } label: {
                Label("Done", systemImage: "checkmark")
            }
            .buttonStyle(.borderedProminent)
        } else {
            Button { withAnimation(.knFast) { isEditing = true } } label: {
                Label("Edit profile", systemImage: "pencil")
            }
            .buttonStyle(.borderless).tint(Palette.action)
        }
    }

    private func factChip(_ icon: String, _ text: String) -> some View {
        HStack(spacing: 5) {
            Image(systemName: icon).font(.caption2.weight(.semibold))
            Text(text).font(.caption2.weight(.medium)).lineLimit(1)
        }
        .foregroundStyle(Palette.muted)
        .padding(.horizontal, 9).padding(.vertical, 4)
        .background(Palette.surfaceElevated.opacity(0.7), in: Capsule())
        .overlay(Capsule().strokeBorder(Palette.border, lineWidth: 1))
    }

    private var initials: String { state.profile.initials }

    // MARK: - Avatar (tap the camera to change your photo — edit mode only)

    private var avatar: some View {
        ZStack {
            if let img = profileImage {
                Image(nsImage: img).resizable().aspectRatio(contentMode: .fill)
            } else {
                Palette.action
                Text(initials).font(.title2.weight(.bold)).foregroundStyle(.white)
            }
        }
        .frame(width: 64, height: 64)
        .clipShape(Circle())
        .overlay(Circle().strokeBorder(Palette.border, lineWidth: 2))
        .knShadow()
        .overlay(alignment: .bottomTrailing) {
            if isEditing {
                Button(action: pickPhoto) {
                    Image(systemName: "camera.fill").font(.caption2.weight(.bold))
                        .foregroundStyle(.white).frame(width: 22, height: 22)
                        .background(Palette.blue, in: Circle())
                        .overlay(Circle().strokeBorder(Palette.surface, lineWidth: 2))
                }
                .buttonStyle(.plain)
                .help("Change photo")
                .offset(x: 3, y: 3)
            }
        }
        .contextMenu {
            if isEditing {
                Button("Change photo…", action: pickPhoto)
                if profileImage != nil {
                    Button("Remove photo", role: .destructive) { showRemovePhoto = true }
                }
            }
        }
        .holdToDelete(isPresented: $showRemovePhoto, title: "Remove profile photo?",
                      message: "Your name and details stay.") {
            state.updateProfile { $0.photoBase64 = "" }
        }
    }

    private var profileImage: NSImage? {
        guard !state.profile.photoBase64.isEmpty,
              let data = Data(base64Encoded: state.profile.photoBase64),
              let img = NSImage(data: data) else { return nil }
        return img
    }

    private func pickPhoto() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.png, .jpeg, .heic, .tiff, .image]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.prompt = "Use Photo"
        guard panel.runModal() == .OK, let url = panel.url, let img = NSImage(contentsOf: url) else { return }
        if let b64 = Self.downscaledJPEGBase64(img, maxSide: 320) {
            state.updateProfile { $0.photoBase64 = b64 }
        }
    }

    /// Downscale to a square-capped JPEG and base64-encode — keeps the synced doc small.
    private static func downscaledJPEGBase64(_ image: NSImage, maxSide: CGFloat) -> String? {
        let size = image.size
        guard size.width > 0, size.height > 0 else { return nil }
        let scale = min(1, maxSide / max(size.width, size.height))
        let target = NSSize(width: (size.width * scale).rounded(), height: (size.height * scale).rounded())
        guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(target.width),
            pixelsHigh: Int(target.height), bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
            isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0) else { return nil }
        rep.size = target
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        image.draw(in: NSRect(origin: .zero, size: target))
        NSGraphicsContext.restoreGraphicsState()
        guard let data = rep.representation(using: .jpeg, properties: [.compressionFactor: 0.8]) else { return nil }
        return data.base64EncodedString()
    }

    // MARK: - Identity

    private let fieldCols = [GridItem(.adaptive(minimum: 230), spacing: 12)]

    private var identityCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 14) {
                SectionTitle(text: "Identity")
                LazyVGrid(columns: fieldCols, spacing: 12) {
                    field("Full name", \.name, "Your name")
                    dateField("Date of birth", \.dob)
                    intField("Age", get: { state.profile.age },
                             set: { v in state.updateProfile { $0.age = v } }, placeholder: "Age")
                    menuField("Blood group", Profile.bloodGroupOptions, \.bloodGroup)
                    menuField("Relationship", Profile.relationshipOptions, \.relationship)
                    phoneField("Phone", \.phone)
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
                    // Editable — commits today's Fitness log on submit/blur (not per
                    // keystroke). Prefills today's weigh-in.
                    labelledEditable("Weight (kg)", value: todayWeightText) {
                        TextField("", text: $weightDraft,
                                  prompt: Text("72").foregroundColor(Palette.faint))
                            .textFieldStyle(.plain).font(.footnote).foregroundStyle(Palette.text)
                            .knField(focused: weightFocused)
                            .focused($weightFocused)
                            .onSubmit(commitWeight)
                            .onChange(of: weightFocused) { _, now in if !now { commitWeight() } }
                    }
                    .onAppear { if !weightFocused { weightDraft = todayWeightText } }
                    .onDisappear { commitWeight() }
                    readOnly("BMI", bmiText, hint: bmiCategory)
                }
            }
        }
    }

    private var bmiText: String {
        guard let h = state.profile.heightCm, let w = state.latestWeightKg,
              let b = Profile.bmi(heightCm: h, weightKg: w) else { return "—" }
        return String(format: "%.1f", b)
    }

    private var bmiCategory: String {
        guard let h = state.profile.heightCm, let w = state.latestWeightKg,
              let b = Profile.bmi(heightCm: h, weightKg: w) else { return "needs height + weight" }
        return Profile.bmiCategory(b)
    }

    /// Today's own weigh-in (not any past day) — what the Weight field prefills with.
    private var todayWeightText: String {
        state.fitnessDay(state.todayKey).weightKg.map { Fmt.trimKg($0) } ?? ""
    }

    private func commitWeight() {
        let t = weightDraft.trimmingCharacters(in: .whitespaces)
        if t.isEmpty {
            if state.fitnessDay(state.todayKey).weightKg != nil { state.setTodayWeight(nil) }
        } else if let w = Double(t), w > 0 {
            state.setTodayWeight(w)
        }
        weightDraft = todayWeightText
        weightFocused = false
    }

    // MARK: - Career

    private var careerCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 14) {
                SectionTitle(text: "Career")
                LazyVGrid(columns: fieldCols, spacing: 12) {
                    field("Role", \.role, "Title — Company")
                }
                labelledEditable("What I do", value: state.profile.work) {
                    TextField("", text: bind(\.work),
                              prompt: Text("One line on the work…").foregroundColor(Palette.faint))
                        .textFieldStyle(.plain).font(.footnote).foregroundStyle(Palette.text)
                        .knField()
                }
            }
        }
    }

    // MARK: - About (context for the assistant)

    private var aboutCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 8) {
                SectionTitle(text: "About")
                if isEditing {
                    TextField("", text: bind(\.about),
                              prompt: Text("Your story, work, family, goals, positioning — anything your assistant should know about you. Private: stored in your account, never in the app's code.")
                                .foregroundColor(Palette.faint),
                              axis: .vertical)
                        .textFieldStyle(.plain).font(.footnote).foregroundStyle(Palette.text)
                        .lineLimit(3...10)
                        .knField()
                } else {
                    Text(state.profile.about.isEmpty ? "Nothing yet — tap Edit profile to add context for your assistant." : state.profile.about)
                        .font(.footnote)
                        .foregroundStyle(state.profile.about.isEmpty ? Palette.faint : Palette.text)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    // MARK: - Goals

    private var goalsCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 16) {
                SectionTitle(text: "Goals")
                GoalList(title: "Short term", color: Palette.green, items: state.profile.goalsShort, editing: isEditing,
                         add: { s in state.updateProfile { $0.goalsShort.append(s) } },
                         remove: { i in state.updateProfile { $0.goalsShort.remove(at: i) } })
                GoalList(title: "Mid term", color: Palette.blue, items: state.profile.goalsMid, editing: isEditing,
                         add: { s in state.updateProfile { $0.goalsMid.append(s) } },
                         remove: { i in state.updateProfile { $0.goalsMid.remove(at: i) } })
                GoalList(title: "Long term", color: Palette.information, items: state.profile.goalsLong, editing: isEditing,
                         add: { s in state.updateProfile { $0.goalsLong.append(s) } },
                         remove: { i in state.updateProfile { $0.goalsLong.remove(at: i) } })
            }
        }
    }

    // MARK: - Achievements

    private var achievementsCard: some View {
        Card {
            AchievementsEditor(editing: isEditing)
        }
    }

    // MARK: - Health

    private var healthCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 10) {
                SectionTitle(text: "Health notes")
                HealthEditor(editing: isEditing)
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
        let value = state.profile[keyPath: keyPath]
        return HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.caption.weight(.semibold)).foregroundStyle(Palette.muted)
                .frame(width: 22)
            Text(label).font(.caption.weight(.medium)).foregroundStyle(Palette.muted)
                .frame(width: 74, alignment: .leading)
            if isEditing {
                TextField("", text: bind(keyPath),
                          prompt: Text("https://…").foregroundColor(Palette.faint))
                    .textFieldStyle(.plain).font(.footnote).foregroundStyle(Palette.text)
            } else {
                Text(value.isEmpty ? "—" : value)
                    .font(.footnote).foregroundStyle(value.isEmpty ? Palette.faint : Palette.text)
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
            if let url = URL(string: value), url.scheme?.hasPrefix("http") == true {
                Button { NSWorkspace.shared.open(url) } label: {
                    Image(systemName: "arrow.up.right").font(.caption2.weight(.bold))
                }
                .buttonStyle(.borderless)
                .help("Open \(label)")
            }
        }
    }

    // MARK: - Field helpers

    private func bind(_ keyPath: WritableKeyPath<Profile, String>) -> Binding<String> {
        Binding(get: { state.profile[keyPath: keyPath] },
                set: { v in state.updateProfile { $0[keyPath: keyPath] = v } })
    }

    /// A labelled slot that shows an editable control when editing, else read-only text.
    private func labelledEditable<V: View>(_ label: String, value: String,
                                           @ViewBuilder content: () -> V) -> some View {
        labelled(label) {
            if isEditing { content() } else { readText(value) }
        }
    }

    @ViewBuilder private func readText(_ value: String) -> some View {
        Text(value.isEmpty ? "—" : value)
            .font(.footnote.weight(value.isEmpty ? .regular : .semibold))
            .foregroundStyle(value.isEmpty ? Palette.faint : Palette.text)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 12).padding(.vertical, 10)
            .background(Palette.surfaceElevated.opacity(0.25),
                        in: RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                .strokeBorder(Palette.border.opacity(0.6), lineWidth: 1))
    }

    private func readField(_ label: String, _ value: String) -> some View {
        labelled(label) { readText(value) }
    }

    private func field(_ label: String, _ keyPath: WritableKeyPath<Profile, String>,
                       _ placeholder: String) -> some View {
        labelledEditable(label, value: state.profile[keyPath: keyPath]) {
            TextField("", text: bind(keyPath),
                      prompt: Text(placeholder).foregroundColor(Palette.faint))
                .textFieldStyle(.plain).font(.footnote).foregroundStyle(Palette.text)
                .knField()
        }
    }

    // Date / menu / phone use KLabeled* (own label) when editing, plain read row otherwise.
    private func dateField(_ label: String, _ keyPath: WritableKeyPath<Profile, String>) -> some View {
        Group {
            if isEditing { KLabeledDateField(label: label, text: bind(keyPath)) }
            else { readField(label, state.profile[keyPath: keyPath]) }
        }
    }
    private func menuField(_ label: String, _ options: [String],
                           _ keyPath: WritableKeyPath<Profile, String>) -> some View {
        Group {
            if isEditing { KLabeledMenuField(label: label, options: options, text: bind(keyPath)) }
            else { readField(label, state.profile[keyPath: keyPath]) }
        }
    }
    private func phoneField(_ label: String, _ keyPath: WritableKeyPath<Profile, String>) -> some View {
        Group {
            if isEditing { KLabeledPhoneField(label: label, text: bind(keyPath)) }
            else { readField(label, state.profile[keyPath: keyPath]) }
        }
    }

    private func intField(_ label: String, get: @escaping () -> Int?,
                          set: @escaping (Int?) -> Void, placeholder: String) -> some View {
        labelledEditable(label, value: get().map(String.init) ?? "") {
            TextField("", text: Binding(get: { get().map(String.init) ?? "" },
                                        set: { set(Int($0.trimmingCharacters(in: .whitespaces))) }),
                      prompt: Text(placeholder).foregroundColor(Palette.faint))
                .textFieldStyle(.plain).font(.footnote).foregroundStyle(Palette.text)
                .knField()
        }
    }

    /// Digits and one dot only. Mirrors `KLabeledNumberField.parse`.
    static func parseDecimal(_ s: String) -> Double? {
        let t = s.trimmingCharacters(in: .whitespaces).filter { $0.isNumber || $0 == "." }
        guard !t.isEmpty, let v = Double(t), v.isFinite else { return nil }
        return v
    }

    private func doubleField(_ label: String, get: @escaping () -> Double?,
                             set: @escaping (Double?) -> Void, placeholder: String) -> some View {
        labelledEditable(label, value: get().map { Fmt.trimKg($0) } ?? "") {
            TextField("", text: Binding(get: { get().map { Fmt.trimKg($0) } ?? "" },
                                        // Filtered, not bare `Double(_:)` — that
                                        // accepts "inf", and an infinite height
                                        // crashed `Fmt.trimKg` on the next render.
                                        set: { set(Self.parseDecimal($0)) }),
                      prompt: Text(placeholder).foregroundColor(Palette.faint))
                .textFieldStyle(.plain).font(.footnote).foregroundStyle(Palette.text)
                .knField()
        }
    }

    private func readOnly(_ label: String, _ value: String, hint: String) -> some View {
        labelled(label) {
            HStack(spacing: 8) {
                Text(value)
                    .font(.footnote.weight(.semibold)).monospacedDigit()
                    .foregroundStyle(Palette.text)
                Spacer()
                Text(hint).font(.caption2).foregroundStyle(Palette.faint)
            }
            .padding(.horizontal, 12).padding(.vertical, 10)
            .background(Palette.surfaceElevated.opacity(0.35),
                        in: RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                .strokeBorder(Palette.border, lineWidth: 1))
        }
    }

    private func labelled<V: View>(_ label: String, @ViewBuilder content: () -> V) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(label.uppercased())
                .font(.caption2.weight(.semibold)).tracking(0.7)
                .foregroundStyle(Palette.faint)
            content()
        }
    }
}

// MARK: - Goal list (add / remove only in edit mode)

private struct GoalList: View {
    let title: String
    let color: Color
    let items: [String]
    let editing: Bool
    let add: (String) -> Void
    let remove: (Int) -> Void
    @State private var text = ""
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 7) {
                Circle().fill(color).frame(width: 7, height: 7)
                Text(title).font(.caption.weight(.semibold)).foregroundStyle(Palette.text)
            }
            if items.isEmpty && !editing {
                Text("—").font(.footnote).foregroundStyle(Palette.faint).padding(.leading, 2)
            }
            ForEach(Array(items.enumerated()), id: \.offset) { i, item in
                HStack(spacing: 9) {
                    Image(systemName: "target").font(.caption2).foregroundStyle(color)
                    Text(item).font(.footnote).foregroundStyle(Palette.text)
                    Spacer()
                    if editing {
                        Button { remove(i) } label: {
                            Image(systemName: "xmark").font(.caption2.weight(.bold))
                        }
                        .buttonStyle(.borderless)
                    }
                }
                .padding(.leading, 2)
            }
            if editing {
                HStack(spacing: 8) {
                    TextField("", text: $text,
                              prompt: Text("Add a \(title.lowercased()) goal…").foregroundColor(Palette.faint))
                        .textFieldStyle(.plain).font(.footnote).foregroundStyle(Palette.text)
                        .focused($focused)
                        .onSubmit(commit)
                    Button(action: commit) {
                        Image(systemName: "plus.circle.fill").font(.callout).foregroundStyle(color)
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
    let editing: Bool
    @State private var year = ""
    @State private var title = ""
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionTitle(text: "Achievements")

            if state.profile.achievements.isEmpty {
                Text("Nothing yet — log the wins as they land.")
                    .font(.footnote).foregroundStyle(Palette.faint)
            }

            ForEach(state.profile.achievements) { m in
                HStack(alignment: .top, spacing: 11) {
                    Text(m.year.isEmpty ? "—" : m.year)
                        .font(.caption2.weight(.bold)).monospacedDigit()
                        .foregroundStyle(Palette.attention)
                        .padding(.horizontal, 8).padding(.vertical, 3)
                        .background(Palette.attention.opacity(0.12), in: Capsule())
                    VStack(alignment: .leading, spacing: 2) {
                        Text(m.title).font(.footnote.weight(.semibold)).foregroundStyle(Palette.text)
                        if !m.note.isEmpty {
                            Text(m.note).font(.caption).foregroundStyle(Palette.muted)
                        }
                    }
                    Spacer()
                    if editing {
                        Button {
                            state.updateProfile { $0.achievements.removeAll { $0.id == m.id } }
                        } label: {
                            Image(systemName: "xmark").font(.caption2.weight(.bold))
                        }
                        .buttonStyle(.borderless)
                    }
                }
            }

            if editing {
                HStack(spacing: 8) {
                    TextField("", text: $year, prompt: Text("Year").foregroundColor(Palette.faint))
                        .textFieldStyle(.plain).font(.footnote).foregroundStyle(Palette.text)
                        .frame(width: 52)
                    Rectangle().fill(Palette.border).frame(width: 1, height: 16)
                    TextField("", text: $title,
                              prompt: Text("What did you achieve?").foregroundColor(Palette.faint))
                        .textFieldStyle(.plain).font(.footnote).foregroundStyle(Palette.text)
                        .focused($focused)
                        .onSubmit(commit)
                    Button(action: commit) {
                        Image(systemName: "plus.circle.fill").font(.callout).foregroundStyle(Palette.attention)
                    }
                    .buttonStyle(.plain)
                    .opacity(title.isEmpty ? 0.35 : 1)
                    .disabled(title.isEmpty)
                }
                .knField(focused: focused)
                .onChange(of: focused) { _, now in if !now { commit() } }
                .onDisappear { commit() }
            }
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
    let editing: Bool
    @FocusState private var focused: Bool

    var body: some View {
        if editing {
            TextEditor(text: Binding(get: { state.profile.healthNotes },
                                     set: { v in state.updateProfile { $0.healthNotes = v } }))
                .font(.footnote).foregroundStyle(Palette.text)
                .scrollContentBackground(.hidden)
                .focused($focused)
                .frame(minHeight: 64)
                .padding(10)
                .background(Palette.surfaceElevated.opacity(0.6),
                            in: RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                    .strokeBorder(focused ? Palette.action.opacity(0.7) : Palette.border, lineWidth: 1))
                .animation(.knFast, value: focused)
        } else {
            Text(state.profile.healthNotes.isEmpty ? "—" : state.profile.healthNotes)
                .font(.footnote)
                .foregroundStyle(state.profile.healthNotes.isEmpty ? Palette.faint : Palette.text)
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
