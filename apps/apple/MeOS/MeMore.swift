import SwiftUI
import PhotosUI

struct MeMore: View {
    @EnvironmentObject var state: AppState
    @Namespace private var ns

    private struct Item: Identifiable { let id: String; let icon: String; let dest: AnyView }
    private var items: [Item] {
        [
            .init(id: "Catherine", icon: "sparkles", dest: AnyView(MeAssistant())),
            .init(id: "Events", icon: "calendar", dest: AnyView(MeEvents())),
            .init(id: "Watch log", icon: "play.rectangle", dest: AnyView(MeWatch())),
            .init(id: "Scan", icon: "camera.viewfinder", dest: AnyView(MeScan())),
            .init(id: "Productivity", icon: "chart.bar", dest: AnyView(MeProductivity())),
            .init(id: "Stuff", icon: "shippingbox", dest: AnyView(MeStuff())),
            .init(id: "Money", icon: "indianrupeesign", dest: AnyView(MeMoney())),
            .init(id: "Macro", icon: "chart.line.uptrend.xyaxis", dest: AnyView(MeMacro())),
            .init(id: "Gallery", icon: "photo.on.rectangle", dest: AnyView(MeGallery())),
            .init(id: "Recycle bin", icon: "trash", dest: AnyView(MeBin())),
            .init(id: "Settings", icon: "gearshape", dest: AnyView(MeSettings())),
        ]
    }

    var body: some View {
        Screen(title: "More") {
            LazyVGrid(columns: [.init(spacing: DS.gap), .init()], spacing: DS.gap) {
                ForEach(Array(items.enumerated()), id: \.element.id) { i, item in
                    NavigationLink { item.dest.zoomFrom(item.id, in: ns) } label: {
                        VStack(alignment: .leading, spacing: 30) {
                            Image(systemName: item.icon).font(.system(size: 34, weight: .semibold))
                            Text(item.id).font(.title3.bold()).lineLimit(1).minimumScaleFactor(0.8)
                        }
                        .padding(DS.pad).frame(maxWidth: .infinity, alignment: .leading)
                        .foregroundStyle(i == 0 ? Color.paper : .ink)
                        .background(i == 0 ? Color.ink : Color.card, in: .rect(cornerRadius: DS.radius))
                        .matchedTransitionSource(id: item.id, in: ns)
                    }
                    .buttonStyle(.press).appear(i)
                }
            }
        }
    }
}

// MARK: - Catherine

struct MeAssistant: View {
    @EnvironmentObject var state: AppState
    @State private var draft = ""
    @State private var voice = false

    var body: some View {
        let msgs = state.activeThread?.messages ?? []
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        Title(text: AgentConfig.shared.name, sub: state.activeThread?.title ?? "New chat").padding(.bottom, 8)
                        ForEach(msgs) { m in
                            let mine = m.role == "user"
                            Text(LocalizedStringKey(m.content)).font(.title3).textSelection(.enabled)
                                .padding(16)
                                .foregroundStyle(mine ? Color.paper : .ink)
                                .background(mine ? Color.ink : Color.card, in: .rect(cornerRadius: 22))
                                .frame(maxWidth: .infinity, alignment: mine ? .trailing : .leading)
                                .transition(.move(edge: .bottom).combined(with: .opacity))
                                .id(m.id)
                        }
                        if state.chatBusy {
                            Image(systemName: "ellipsis").font(.title).symbolEffect(.variableColor.iterative)
                                .padding(16).background(Color.card, in: .capsule).id("busy")
                        }
                        if let err = state.chatError {
                            Button { Task { await state.retryLastChat() } } label: { Label(err, systemImage: "arrow.clockwise").font(.subheadline) }
                        }
                        if msgs.isEmpty {
                            ForEach(["Plan my dinner", "How was my week?", "What should I focus on today?"], id: \.self) { p in
                                Button { send(p) } label: { Chip(text: p) }.buttonStyle(.press)
                            }
                        }
                    }
                    .padding(DS.pad)
                }
                .scrollDismissesKeyboard(.interactively)
                .onChange(of: msgs.count) { withAnimation(DS.spring) { proxy.scrollTo(msgs.last?.id) } }
                .onChange(of: state.chatBusy) { withAnimation(DS.spring) { proxy.scrollTo("busy") } }
            }
            HStack(spacing: 10) {
                TextField("Ask anything", text: $draft, axis: .vertical).font(.title3).lineLimit(1...4)
                    .padding(.horizontal, 20).padding(.vertical, 16).background(Color.card, in: .rect(cornerRadius: 28))
                Button { draft.isEmpty ? (voice = true) : send(draft) } label: {
                    Image(systemName: draft.isEmpty ? "waveform" : "arrow.up").font(.title2.weight(.bold))
                        .frame(width: 56, height: 56).foregroundStyle(Color.paper).background(Color.ink, in: .circle)
                        .contentTransition(.symbolEffect(.replace))
                }
                .buttonStyle(.press)
            }
            .padding(DS.pad)
        }
        .meActions {
            MeModelMenu(feature: .chat) { model in
                HStack(spacing: 6) {
                    Image(systemName: "cpu")
                    Text(model).font(.subheadline.weight(.semibold)).lineLimit(1)
                }
                .padding(.horizontal, 12)
            }
            Menu {
                Button("New chat", systemImage: "plus") { state.newChat() }
                Divider()
                ForEach(state.chat.threads) { t in Button(t.title) { state.selectChat(t.id) } }
            } label: { Image(systemName: "bubble.left.and.bubble.right") }
            .menuIndicator(.hidden)
        }
        .fullScreenCover(isPresented: $voice) { MeVoiceCall { voice = false } }
        .onAppear { if let p = state.pendingChatPrompt { state.pendingChatPrompt = nil; send(p) } }
    }

    private func send(_ text: String) {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return }
        draft = ""
        Task { await state.sendChat(t) }
    }
}

// MARK: - Events

struct MeEvents: View {
    @EnvironmentObject var state: AppState
    @State private var adding = false
    @State private var past = false

    var body: some View {
        let upcoming = state.upcoming(limit: 100)
        let history = state.events.filter { $0.date < state.todayKey && !$0.recurrence.repeats }.sorted { $0.date > $1.date }
        Screen(title: "Events", sub: "Memories & plans") {
            HStack { Button { withAnimation(DS.spring) { past = false } } label: { Chip(text: "Upcoming", on: !past) }
                     Button { withAnimation(DS.spring) { past = true } } label: { Chip(text: "Past", on: past) } }
                .buttonStyle(.press)
            if past {
                ForEach(history) { e in row(e, e.date) }
            } else {
                ForEach(upcoming, id: \.event.id) { row($0.event, $0.date) }
            }
            NavigationLink { MeCalendar() } label: { Row(icon: "calendar", title: "Calendar") }
            .buttonStyle(.press)
        }
        .meActions { Button { adding = true } label: { Image(systemName: "plus") } }
        .sheet(isPresented: $adding) { MeAddEvent().presentationDetents([.medium, .large]) }
    }

    private func row(_ e: EventItem, _ key: String) -> some View {
        NavigationLink { MeEventDetail(id: e.id) } label: { MCard(inverted: e.special) {
            HStack(spacing: 16) {
                VStack {
                    Text(String(key.suffix(2))).font(.system(size: 30, weight: .bold, design: .rounded))
                    Text(AppState.date(fromKey: key)?.formatted(.dateTime.month()) ?? "").font(.caption.weight(.bold)).textCase(.uppercase)
                }
                .frame(width: 56)
                VStack(alignment: .leading, spacing: 4) {
                    Text(e.title).font(.title3.bold())
                    Text(state.tags(for: e).map(\.name).joined(separator: " · ")).font(.subheadline).opacity(0.6)
                }
                Spacer()
                if let n = state.daysUntil(key), n >= 0 { Text(n == 0 ? "Today" : "\(n)d").font(.headline) }
            }
        } }
        .buttonStyle(.press)
        .contextMenu { Button("Delete", systemImage: "trash", role: .destructive) { withAnimation(DS.spring) { state.deleteEvent(e.id) } } }
    }
}

struct MeAddEvent: View {
    @EnvironmentObject var state: AppState
    @Environment(\.dismiss) private var dismiss
    var initialDate = Date.now
    @State private var title = ""
    @State private var date = Date.now
    @State private var tags: Set<String> = []
    @State private var special = false
    @State private var note = ""
    @State private var unit: Recurrence.Unit = .none
    @State private var pick: [PhotosPickerItem] = []
    @State private var photos: [Data] = []

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("New event").font(.largeTitle.bold()).padding(.top, 24)
                MField(icon: "textformat", placeholder: "Title", text: $title)
                DatePicker("Date", selection: $date, displayedComponents: .date).font(.title3)
                ScrollView(.horizontal) {
                    HStack { ForEach(state.eventTags) { t in Button { if tags.contains(t.id) { tags.remove(t.id) } else { tags.insert(t.id) } } label: { Chip(text: t.name, on: tags.contains(t.id)) } } }
                }
                .scrollIndicators(.hidden).buttonStyle(.press)
                Picker("Repeat", selection: $unit) { ForEach(Recurrence.Unit.allCases) { Text($0.label).tag($0) } }.pickerStyle(.segmented)
                Toggle("Special", isOn: $special).font(.title3)
                MField(icon: "text.alignleft", placeholder: "Note", text: $note)
                PhotosPicker(selection: $pick, maxSelectionCount: 10, matching: .images) { Row(icon: "photo.badge.plus", title: photos.isEmpty ? "Add photos" : "\(photos.count) photos") }
                    .buttonStyle(.press)
                MButton(title: "Save", icon: "checkmark") {
                    var rec = Recurrence.none; rec.unit = unit
                    state.addEvent(date: AppState.dateKey(date), title: title, tagIDs: Array(tags), note: note, special: special,
                                   media: photos.map { EventMedia(kind: .image, data: $0.base64EncodedString()) },
                                   recurrence: rec, reminders: [.sameDay])
                    Task { await state.migrateEventMediaToR2() }
                    Haptics.success(); dismiss()
                }
                .disabled(title.isEmpty).opacity(title.isEmpty ? 0.3 : 1)
            }
            .padding(DS.pad)
        }
        .onAppear { date = initialDate }
        .onChange(of: pick) { _, items in
            Task {
                for it in items { if let d = try? await it.loadTransferable(type: Data.self), let img = UIImage(data: d), let j = PhotoSource.jpeg(img) { photos.append(j) } }
                pick = []
            }
        }
    }
}

// MARK: - Watch log

struct MeWatch: View {
    @EnvironmentObject var state: AppState
    @State private var link = ""
    @State private var filter: WatchCategory?
    @State private var error: String?

    var body: some View {
        let list = state.watch.filter { filter == nil || $0.category == filter }.sorted { $0.addedAt > $1.addedAt }
        Screen(title: "Watch log", sub: "\(state.watch.filter { $0.takeaway.isEmpty }.count) need a takeaway") {
            MField(icon: "link", placeholder: "Paste a YouTube link", text: $link).onSubmit(add)
            if let error { Text(error).font(.subheadline.weight(.semibold)) }
            ScrollView(.horizontal) {
                HStack {
                    Button { withAnimation(DS.spring) { filter = nil } } label: { Chip(text: "All", on: filter == nil) }
                    ForEach(WatchCategory.allCases, id: \.self) { c in Button { withAnimation(DS.spring) { filter = c } } label: { Chip(text: c.label, on: filter == c) } }
                }
            }
            .scrollIndicators(.hidden).buttonStyle(.press)
            ForEach(list) { v in MeWatchRow(item: v).transition(.scale(0.96).combined(with: .opacity)) }
        }
    }

    private func add() {
        let raw = link.trimmingCharacters(in: .whitespaces)
        guard !raw.isEmpty else { return }
        guard let id = YouTube.videoID(from: raw) else { error = "That doesn’t look like a YouTube link."; return }
        if state.watch.contains(where: { $0.videoId == id }) { error = "Already in your list."; link = ""; return }
        error = nil; link = ""
        let saved = withAnimation(DS.spring) { state.addWatchItem(WatchItem(url: raw, videoId: id, thumbUrl: YouTube.thumbURL(id)), on: state.todayKey) }
        Task { @MainActor in
            let meta = await YouTube.fetchMeta(id: id)
            state.enrichWatchItem(id: saved.id, title: meta.title, channel: meta.channel, thumbUrl: meta.thumbUrl.isEmpty ? nil : meta.thumbUrl)
            if let cat = await state.categorizeVideo(title: meta.title, channel: meta.channel) { state.enrichWatchItem(id: saved.id, category: cat) }
        }
    }
}

struct MeWatchRow: View {
    @EnvironmentObject var state: AppState
    let item: WatchItem
    @State private var takeaway = ""
    var body: some View {
        MCard {
            HStack(spacing: 14) {
                AsyncImage(url: URL(string: item.thumbUrl)) { $0.resizable().scaledToFill() } placeholder: { Color.hairline }
                    .frame(width: 96, height: 60).clipShape(.rect(cornerRadius: 14))
                    .overlay(alignment: .bottomTrailing) {
                        if item.watched { Image(systemName: "checkmark.circle.fill").font(.title3).foregroundStyle(.white).padding(4) }
                    }
                VStack(alignment: .leading) {
                    Text(item.title.isEmpty ? "Loading…" : item.title).font(.headline).lineLimit(2)
                    Text("\(item.channel) · \(item.category.label)").font(.subheadline).foregroundStyle(Color.dim)
                }
            }
            TextField("What I learned…", text: $takeaway, axis: .vertical).font(.body)
                .onSubmit { save() }
        }
        .onTapGesture(count: 2) { withAnimation(DS.bouncy) { state.toggleWatched(item.id) } }
        .contextMenu {
            Button(item.watched ? "Mark unwatched" : "Mark watched", systemImage: "checkmark") { state.toggleWatched(item.id) }
            if let u = URL(string: item.url) { Link(destination: u) { Label("Open", systemImage: "play") } }
            Button("Delete", systemImage: "trash", role: .destructive) { state.deleteWatchItem(item.id) }
        }
        .onAppear { takeaway = item.takeaway }
        .onDisappear { save() }
    }
    private func save() {
        guard takeaway != item.takeaway else { return }
        var v = item; v.takeaway = takeaway; state.updateWatchItem(v)
    }
}

// MARK: - Settings

struct MeSettings: View {
    @EnvironmentObject var state: AppState
    @EnvironmentObject private var mio: MioController
    @State private var faceID = BiometricLock.isEnabled
    @State private var exportURL: URL?

    var body: some View {
        Screen(title: "Settings", sub: state.username) {
            MCard {
                Toggle(isOn: $faceID) { Label("\(BiometricLock.biometryName) lock", systemImage: "faceid") }.font(.title3.weight(.semibold))
                    .onChange(of: faceID) { _, v in UserDefaults.standard.set(v, forKey: BiometricLock.key) }
                    .disabled(!BiometricLock.isAvailable)
            }
            MCard {
                HStack(spacing: 14) {
                    MioCharacter(expression: .peaceful, form: .companion, size: 48)
                    Toggle("Mio companion", isOn: $mio.isVisible).font(.title3.weight(.semibold))
                }
                Text("Mio celebrates progress and offers gentle check-ins. You can turn it off anytime.")
                    .font(.subheadline).foregroundStyle(Color.dim)
            }
            MCard {
                HStack {
                    Label("Sync", systemImage: "arrow.triangle.2.circlepath").font(.title3.weight(.semibold))
                    Spacer()
                    Button("Refresh") { Task { await state.syncNow() } }.font(.headline)
                }
                if let err = state.lastSyncError { Text(err).font(.subheadline).foregroundStyle(Color.dim) }
            }
            group("Profile", "person.crop.circle") { MeProfile() }
            group("AI & keys", "key") { MeAI() }
            group("AI connections (MCP)", "link") { MeConnections() }
            group("Memory", "brain") { MeMemory() }
            group("Reminders", "bell") { MeReminders() }
            group("Change password", "key.viewfinder") { MeChangePassword() }
            MCard {
                Button { Task { await state.regenerateRecoveryCode() } } label: { Label("New recovery code", systemImage: "key.horizontal").font(.headline) }
                Divider()
                Button {
                    guard let data = state.exportJSON() else { return }
                    let url = FileManager.default.temporaryDirectory.appendingPathComponent("MeOS-backup.json")
                    try? data.write(to: url); exportURL = url
                } label: { Label("Export backup (JSON)", systemImage: "square.and.arrow.up").font(.headline) }
                if let exportURL { ShareLink(item: exportURL) { Label("Share backup", systemImage: "doc").font(.headline) } }
            }
            Button { Task { await state.logout() } } label: {
                Text("Log out").font(.title3.weight(.semibold)).frame(maxWidth: .infinity).frame(height: 62).background(Color.card, in: .rect(cornerRadius: 22))
            }
            .buttonStyle(.press)
        }
    }

    private func group<D: View>(_ title: String, _ icon: String, @ViewBuilder dest: @escaping () -> D) -> some View {
        NavigationLink { dest() } label: {
            MCard { HStack { Label(title, systemImage: icon).font(.title3.weight(.semibold)); Spacer(); Image(systemName: "chevron.right") } }
        }
        .buttonStyle(.press)
    }
}

struct MeChangePassword: View {
    @EnvironmentObject var state: AppState
    @Environment(\.dismiss) private var dismiss
    @State private var current = ""
    @State private var next = ""
    @State private var confirm = ""
    @State private var busy = false
    @State private var message: String?
    @State private var done = false

    var body: some View {
        Screen(title: "Change password", sub: "Login only") {
            Text("This changes how you sign in. Your encryption passphrase stays the same. Other devices get signed out.")
                .foregroundStyle(Color.dim)
            MField(icon: "key", placeholder: "Current password", text: $current, secure: true)
            MField(icon: "key.fill", placeholder: "New password (8+)", text: $next, secure: true)
            MField(icon: "checkmark.shield", placeholder: "Confirm new password", text: $confirm, secure: true)
            if let message { Text(message).font(.subheadline.weight(.semibold)).transition(.opacity) }
            MButton(title: busy ? "Saving…" : done ? "Changed" : "Change password", icon: done ? "checkmark" : "arrow.right") { Task { await save() } }
                .disabled(busy || done)
        }
        .sensoryFeedback(.success, trigger: done)
    }

    private func save() async {
        guard next.count >= 8 else { message = "New password must be at least 8 characters."; return }
        guard next == confirm else { message = "The new passwords don’t match."; return }
        busy = true; defer { busy = false }
        do {
            try await state.api.changePassword(current: current, next: next)
            withAnimation(DS.spring) { done = true; message = "Password changed." }
            try? await Task.sleep(for: .seconds(1)); dismiss()
        } catch let e as APIError where e.status == 404 {
            message = "Server doesn’t support this yet — deploy the API update first."
        } catch {
            withAnimation(DS.spring) { message = error.localizedDescription }
        }
    }
}
