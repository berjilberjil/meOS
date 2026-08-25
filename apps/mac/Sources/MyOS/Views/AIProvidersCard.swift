import SwiftUI

/// Settings card for bring-your-own AI: add keys for Gemini / Claude / OpenAI, check
/// them (which lists their real models), enable/disable them, and route each feature
/// in the app to a specific key + model. Keys are validated + stored server-side
/// (encrypted) via `AISettingsStore`, so the setup follows the account across devices.
///
/// On the phone this is three questions in order — which provider, what is the key,
/// and what should use it — rather than one dense column. Nothing about validation
/// or storage changed.
struct AIProvidersCard: View {
    var boxed = true
    @ObservedObject private var store = AISettingsStore.shared

    var body: some View {
        Group {
            if boxed { Card { boxedInner } } else { page }
        }
        .task { await store.loadIfNeeded() }
    }

    // MARK: - Phone: a page

    private var page: some View {
        SettingsPage {
            SettingsIntro(text: "Add a Gemini, Claude or OpenAI key, then pick which model powers each feature.")

            if let e = store.loadError {
                SettingsNotice(text: e, actionLabel: "Retry") { Task { await store.load() } }
            }

            AddKeyForm(store: store, boxed: false)

            if !store.keys.isEmpty {
                SettingsGroup(title: "Your keys") {
                    ForEach(Array(store.keys.enumerated()), id: \.element.id) { i, key in
                        if i > 0 { SettingsDivider(inset: SettingsMetrics.plainInset) }
                        AIKeyRow(store: store, key: key, boxed: false)
                    }
                }
            } else if !store.loaded {
                SettingsGroup {
                    HStack(spacing: 10) {
                        ProgressView().controlSize(.small)
                        Text("Loading your keys…")
                            .font(.footnote).foregroundStyle(Palette.muted)
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, SettingsMetrics.rowPadH)
                    .padding(.vertical, 14)
                }
            } else if store.loadError == nil {
                SettingsGroup {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("No keys yet")
                            .font(.callout.weight(.semibold)).foregroundStyle(Palette.text)
                        Text("Add one above and Catherine runs on it. Until then everything uses the server default.")
                            .font(.footnote).foregroundStyle(Palette.faint)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, SettingsMetrics.rowPadH)
                    .padding(.vertical, 14)
                }
            }

            SettingsGroup(title: "Route features to models",
                          footer: store.enabledKeys.isEmpty
                          ? "Add and enable a key above to route features. Until then everything uses the server default."
                          : nil) {
                ModelPickerRow(store: store, feature: nil, boxed: false)
                ForEach(Array(AIFeature.allCases.enumerated()), id: \.element.id) { _, f in
                    SettingsDivider(inset: SettingsMetrics.plainInset)
                    ModelPickerRow(store: store, feature: f, boxed: false)
                }
            }
        }
    }

    // MARK: - Mac: a card

    private var boxedInner: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                SectionTitle(text: "AI providers & models")
                Spacer()
                Text("bring your own keys").font(.caption).foregroundStyle(Palette.faint)
            }
            Text("Add a Gemini, Claude or OpenAI key, then pick which model powers each feature.")
                .font(.subheadline).foregroundStyle(Palette.muted)
                .fixedSize(horizontal: false, vertical: true)

            if let e = store.loadError {
                SettingsNotice(text: e, actionLabel: "Retry") { Task { await store.load() } }
            }

            AddKeyForm(store: store, boxed: true)

            if !store.keys.isEmpty {
                Divider().overlay(Palette.border)
                VStack(spacing: 4) {
                    ForEach(store.keys) { key in AIKeyRow(store: store, key: key, boxed: true) }
                }
            }

            Divider().overlay(Palette.border)
            VStack(alignment: .leading, spacing: 6) {
                KFieldLabel(text: "Route features to models")
                if store.enabledKeys.isEmpty {
                    Text("Add and enable a key above to route features. Until then everything uses the server default.")
                        .font(.caption2).foregroundStyle(Palette.faint)
                        .fixedSize(horizontal: false, vertical: true)
                }
                ModelPickerRow(store: store, feature: nil, boxed: true)
                ForEach(AIFeature.allCases) { f in ModelPickerRow(store: store, feature: f, boxed: true) }
            }
        }
    }
}

// MARK: - Add key

private struct AddKeyForm: View {
    @ObservedObject var store: AISettingsStore
    var boxed = true
    @Environment(\.openURL) private var openURL
    @State private var provider: AIProvider = .gemini
    @State private var label = ""
    @State private var keyText = ""
    @FocusState private var labelFocused: Bool
    @FocusState private var keyFocused: Bool

    private var canAdd: Bool {
        !store.busy && keyText.trimmingCharacters(in: .whitespaces).count >= 8
    }

    var body: some View {
        if boxed { macForm } else { phoneForm }
    }

    // MARK: Phone

    private var phoneForm: some View {
        VStack(alignment: .leading, spacing: SettingsMetrics.labelGap) {
            SectionTitle(text: "Add an AI provider").padding(.leading, 4)

            Card(padding: 4) {
                VStack(spacing: 0) {
                    HStack {
                        Picker("", selection: $provider) { ForEach(AIProvider.allCases.map { ($0, $0.label) }, id: \.0) { opt in Text(opt.1).tag(opt.0) } }.pickerStyle(.segmented).labelsHidden()
                    }
                    .padding(.horizontal, SettingsMetrics.rowPadH)
                    .padding(.vertical, 10)

                    if let url = provider.getKeyURL {
                        SettingsDivider(inset: SettingsMetrics.plainInset)
                        SettingsRow(title: "Get a \(provider.label) key",
                                    subtitle: "Opens \(url.host ?? "the provider") in Safari.",
                                    action: { openURL(url) }) {
                            Image(systemName: "arrow.up.right")
                                .font(.footnote.weight(.bold)).foregroundStyle(Palette.faint)
                        }
                    }

                    SettingsDivider(inset: SettingsMetrics.plainInset)
                    SettingsFieldRow(label: "Label",
                                     placeholder: "Personal \(provider.label)",
                                     text: $label)
                    SettingsDivider(inset: SettingsMetrics.plainInset)
                    SettingsFieldRow(label: "API key",
                                     placeholder: provider.keyPlaceholder,
                                     monospaced: true, secure: true,
                                     text: $keyText)
                }
            }

            Button { add() } label: {
                HStack(spacing: 8) {
                    if store.busy { ProgressView().controlSize(.small).tint(.white) }
                    Text(store.busy ? "Checking…" : "Check & add")
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .disabled(!canAdd)
            .opacity(canAdd ? 1 : 0.5)
            .padding(.top, 2)

            if let err = store.actionError {
                SettingsNotice(text: err)
            }
        }
    }

    // MARK: Mac

    private var macForm: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Picker("", selection: $provider) { ForEach(AIProvider.allCases.map { ($0, $0.label) }, id: \.0) { opt in Text(opt.1).tag(opt.0) } }.pickerStyle(.segmented).labelsHidden()
                Spacer()
                if let url = provider.getKeyURL {
                    Button { openURL(url) } label: {
                        Label("Get key", systemImage: "arrow.up.right")
                    }
                    .buttonStyle(.borderless)
                }
            }

            HStack(alignment: .top, spacing: 10) {
                VStack(alignment: .leading, spacing: 5) {
                    KFieldLabel(text: "Label")
                    TextField("", text: $label,
                              prompt: Text("e.g. Personal \(provider.label)").foregroundColor(Palette.faint))
                        .textFieldStyle(.plain).font(.footnote).foregroundStyle(Palette.text)
                        .focused($labelFocused).knField(focused: labelFocused)
                }
                .frame(width: 190)

                VStack(alignment: .leading, spacing: 5) {
                    KFieldLabel(text: "API key")
                    SecureField("", text: $keyText,
                                prompt: Text(provider.keyPlaceholder).foregroundColor(Palette.faint))
                        .textFieldStyle(.plain).font(.footnote).monospaced().foregroundStyle(Palette.text)
                        .focused($keyFocused).knField(focused: keyFocused)
                }
            }

            HStack(spacing: 12) {
                Button { add() } label: {
                    HStack(spacing: 8) {
                        if store.busy { ProgressView().controlSize(.small) }
                        Text(store.busy ? "Checking…" : "Check & add")
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(!canAdd)
                Spacer(minLength: 0)
            }

            if let err = store.actionError {
                SettingsNotice(text: err)
            }
        }
    }

    private func add() {
        let p = provider, l = label, k = keyText
        Task {
            if await store.addKey(provider: p, label: l, key: k) {
                label = ""; keyText = ""
            }
        }
    }
}

// MARK: - One saved key

private struct AIKeyRow: View {
    @ObservedObject var store: AISettingsStore
    let key: APIClient.AIKeyDTO
    var boxed = true
    @State private var showDelete = false

    private var provider: AIProvider { AIProvider(rawValue: key.provider) ?? .gemini }

    /// Says whether the key is actually usable, not just that it exists.
    private var status: String {
        if !key.enabled { return "\(key.masked)  ·  off" }
        if key.models.isEmpty { return "\(key.masked)  ·  not checked yet" }
        return "\(key.masked)  ·  \(key.models.count) models"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Text(provider.label)
                    .font(.caption2.weight(.heavy))
                    .padding(.horizontal, 8).padding(.vertical, 4)
                    .background(provider.accent.opacity(0.18), in: Capsule())
                    .foregroundStyle(provider.accent)
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 5) {
                        if key.enabled && !key.models.isEmpty {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.caption).foregroundStyle(Palette.green)
                        }
                        Text(key.label).font(.callout.weight(.semibold)).foregroundStyle(Palette.text)
                            .lineLimit(1)
                    }
                    Text(status)
                        .font(.caption).monospaced().foregroundStyle(Palette.faint)
                        .lineLimit(1)
                }
                Spacer(minLength: 6)
                Toggle("", isOn: Binding(get: { key.enabled },
                                         set: { on in Task { await store.setEnabled(key, on) } }))
                    .labelsHidden().tint(Palette.green)
            }
            HStack(spacing: 8) {
                Spacer(minLength: 0)
                Button { Task { await store.recheck(key) } } label: { Text("Check") }
                    .buttonStyle(.borderless)
                    .disabled(store.busy)
                Button { showDelete = true } label: { Image(systemName: "trash") }
                    .buttonStyle(.borderless).tint(Palette.red)
                    .holdToDelete(isPresented: $showDelete,
                                  title: "Remove \(key.label)?",
                                  message: "Deletes this key from your account. Any feature using it falls back to your default.",
                                  confirmLabel: "Hold to remove") { Task { await store.delete(key) } }
            }
        }
        .padding(.horizontal, boxed ? 0 : SettingsMetrics.rowPadH)
        .padding(.vertical, boxed ? 8 : 12)
    }
}

// MARK: - Route one feature to a key + model

private struct ModelPickerRow: View {
    @ObservedObject var store: AISettingsStore
    let feature: AIFeature?   // nil = the default route
    var boxed = true

    private var candidates: [APIClient.AIKeyDTO] {
        store.enabledKeys.filter { key in
            guard feature?.geminiOnly == true else { return true }
            return key.provider == AIProvider.gemini.rawValue
        }
    }
    private var current: APIClient.AIRouteRef? { store.route(for: feature) }
    private var currentLabel: String {
        if let r = current, let k = store.keys.first(where: { $0.id == r.keyId }) {
            return "\(k.label) · \(r.model)"
        }
        return feature == nil ? "Server default" : "Default"
    }

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(feature?.label ?? "Everything else")
                    .font(.system(size: boxed ? 13 : 15,
                                  weight: feature == nil ? .bold : .semibold))
                    .foregroundStyle(Palette.text)
                if let note = feature?.note {
                    Text(note).font(.system(size: boxed ? 10 : 11)).foregroundStyle(Palette.faint)
                        .lineLimit(2).fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 8)
            menu
        }
        .padding(.horizontal, boxed ? 0 : SettingsMetrics.rowPadH)
        .padding(.vertical, boxed ? 5 : 11)
    }

    @ViewBuilder private var menu: some View {
        if candidates.isEmpty {
            Text(feature?.geminiOnly == true ? "Needs a Gemini key" : "Add a key first")
                .font(.caption2).foregroundStyle(Palette.faint)
        } else {
            Menu {
                Button(feature == nil ? "Server default (env)" : "Use default") {
                    Task { await store.setRoute(feature, to: nil) }
                }
                Divider()
                ForEach(candidates) { key in
                    Menu(key.label) {
                        ForEach(key.models, id: \.self) { model in
                            Button {
                                Task { await store.setRoute(feature, to: .init(keyId: key.id, model: model)) }
                            } label: {
                                if current?.keyId == key.id && current?.model == model {
                                    Label(model, systemImage: "checkmark")
                                } else {
                                    Text(model)
                                }
                            }
                        }
                    }
                }
            } label: {
                HStack(spacing: 6) {
                    Text(currentLabel)
                        .font(.caption.weight(.semibold)).lineLimit(1)
                        .foregroundStyle(current == nil ? Palette.muted : Palette.text)
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.caption2.weight(.bold)).foregroundStyle(Palette.faint)
                }
                .padding(.horizontal, 12).padding(.vertical, 8)
                .background(.hueCanvas, in: RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                    .strokeBorder(Palette.border, lineWidth: 2))
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .frame(maxWidth: 200, alignment: .trailing)
        }
    }
}
