import SwiftUI

/// Settings card for bring-your-own AI: add keys for Gemini / Claude / OpenAI, check
/// them (which lists their real models), enable/disable them, and route each feature
/// in the app to a specific key + model. Keys are validated + stored server-side
/// (encrypted) via `AISettingsStore`, so the setup follows the account across devices.
struct AIProvidersCard: View {
    @ObservedObject private var store = AISettingsStore.shared

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    SectionTitle(text: "AI providers & models")
                    Spacer()
                    Text("bring your own keys").font(.system(size: 10)).foregroundStyle(Palette.faint)
                }
                Text("Add keys for Gemini, Claude or OpenAI, then pick which model powers each feature. Keys are validated, encrypted and synced to your account — never stored in the app.")
                    .font(.system(size: 12)).foregroundStyle(Palette.muted)
                    .fixedSize(horizontal: false, vertical: true)

                if let e = store.loadError {
                    HStack {
                        Label(e, systemImage: "exclamationmark.triangle.fill")
                            .font(.system(size: 12)).foregroundStyle(Palette.amber)
                        Spacer()
                        Button("Retry") { Task { await store.load() } }.buttonStyle(KGhostButtonStyle())
                    }
                }

                AddKeyForm(store: store)

                if !store.keys.isEmpty {
                    Divider().overlay(Palette.border)
                    VStack(spacing: 4) {
                        ForEach(store.keys) { key in AIKeyRow(store: store, key: key) }
                    }
                }

                Divider().overlay(Palette.border)
                VStack(alignment: .leading, spacing: 6) {
                    KFieldLabel(text: "Route features to models")
                    if store.enabledKeys.isEmpty {
                        Text("Add and enable a key above to route features. Until then everything uses the server default.")
                            .font(.system(size: 11)).foregroundStyle(Palette.faint)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    ModelPickerRow(store: store, feature: nil)
                    ForEach(AIFeature.allCases) { f in ModelPickerRow(store: store, feature: f) }
                }
            }
        }
        .task { await store.loadIfNeeded() }
    }
}

// MARK: - Add key

private struct AddKeyForm: View {
    @ObservedObject var store: AISettingsStore
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
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Segmented(options: AIProvider.allCases.map { ($0, $0.label) }, selection: $provider)
                Spacer()
                if let url = provider.getKeyURL {
                    Button { openURL(url) } label: {
                        Label("Get key", systemImage: "arrow.up.right")
                    }
                    .buttonStyle(KGhostButtonStyle())
                }
            }

            HStack(alignment: .top, spacing: 10) {
                VStack(alignment: .leading, spacing: 5) {
                    KFieldLabel(text: "Label")
                    TextField("", text: $label,
                              prompt: Text("e.g. Personal \(provider.label)").foregroundColor(Palette.faint))
                        .textFieldStyle(.plain).font(.system(size: 13)).foregroundStyle(Palette.text)
                        .focused($labelFocused).knField(focused: labelFocused)
                }
                .frame(width: 190)

                VStack(alignment: .leading, spacing: 5) {
                    KFieldLabel(text: "API key")
                    SecureField("", text: $keyText,
                                prompt: Text(provider.keyPlaceholder).foregroundColor(Palette.faint))
                        .textFieldStyle(.plain).font(.system(size: 13)).monospaced().foregroundStyle(Palette.text)
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
                .buttonStyle(KPrimaryButtonStyle())
                .disabled(!canAdd)

                if let err = store.actionError {
                    Label(err, systemImage: "exclamationmark.triangle.fill")
                        .font(.system(size: 11)).foregroundStyle(Palette.amber)
                        .lineLimit(2).fixedSize(horizontal: false, vertical: true)
                }
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
    @State private var showDelete = false

    private var provider: AIProvider { AIProvider(rawValue: key.provider) ?? .gemini }

    var body: some View {
        HStack(spacing: 12) {
            Text(provider.label)
                .font(.system(size: 10, weight: .heavy, design: .rounded))
                .padding(.horizontal, 8).padding(.vertical, 4)
                .background(provider.accent.opacity(0.18), in: Capsule())
                .foregroundStyle(provider.accent)

            VStack(alignment: .leading, spacing: 2) {
                Text(key.label).font(.system(size: 13, weight: .semibold)).foregroundStyle(Palette.text)
                Text("\(key.masked)  ·  \(key.models.count) models")
                    .font(.system(size: 11)).monospaced().foregroundStyle(Palette.faint)
            }

            Spacer()

            Toggle("", isOn: Binding(get: { key.enabled },
                                     set: { on in Task { await store.setEnabled(key, on) } }))
                .labelsHidden().toggleStyle(.switch).tint(Palette.green)

            Button { Task { await store.recheck(key) } } label: { Text("Check") }
                .buttonStyle(KGhostButtonStyle())
                .disabled(store.busy)

            Button { showDelete = true } label: { Image(systemName: "trash") }
                .buttonStyle(KIconButtonStyle(size: 15, color: Palette.faint))
                .holdToDelete(isPresented: $showDelete,
                              title: "Remove \(key.label)?",
                              message: "Deletes this key from your account. Any feature using it falls back to your default.",
                              confirmLabel: "Hold to remove") { Task { await store.delete(key) } }
        }
        .padding(.vertical, 5)
    }
}

// MARK: - Route one feature to a key + model

private struct ModelPickerRow: View {
    @ObservedObject var store: AISettingsStore
    let feature: AIFeature?   // nil = the default route

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
                Text(feature?.label ?? "Default (everything else)")
                    .font(.system(size: 13, weight: feature == nil ? .bold : .regular))
                    .foregroundStyle(Palette.text)
                if let note = feature?.note {
                    Text(note).font(.system(size: 10)).foregroundStyle(Palette.faint)
                }
            }
            Spacer()
            menu
        }
        .padding(.vertical, 5)
    }

    @ViewBuilder private var menu: some View {
        if candidates.isEmpty {
            Text(feature?.geminiOnly == true ? "Needs a Gemini key" : "Add a key first")
                .font(.system(size: 11)).foregroundStyle(Palette.faint)
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
                        .font(.system(size: 12, weight: .semibold)).lineLimit(1)
                        .foregroundStyle(current == nil ? Palette.muted : Palette.text)
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.system(size: 9, weight: .bold)).foregroundStyle(Palette.faint)
                }
                .padding(.horizontal, 12).padding(.vertical, 8)
                .background(Palette.bg, in: RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                    .strokeBorder(Palette.border, lineWidth: 2))
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .frame(maxWidth: 280, alignment: .trailing)
        }
    }
}
