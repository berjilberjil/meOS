import SwiftUI
import PhotosUI
import UIKit

/// iOS Events — the memory log Berjil adds to most. Image-first: an event has a
/// date, a tag, a note and photos (video is Mac-only for now). Upcoming events sit
/// on top, then past. Backed by the shared `myos.events` store, so it syncs with the
/// Mac Events tab.
struct EventsView: View {
    @EnvironmentObject var state: AppState
    @ObservedObject private var signals = UISignals.shared
    @State private var editing: EventItem?
    @State private var showNew = false

    private var sorted: [EventItem] { state.events.sorted { $0.date > $1.date } }
    private var upcoming: [EventItem] { sorted.filter { $0.date >= state.todayKey } }
    private var past: [EventItem] { sorted.filter { $0.date < state.todayKey } }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if state.events.isEmpty {
                Card {
                    Text("No events yet. Double-tap the Journal tab to add a memory — a trip, a milestone, a moment.")
                        .font(.system(size: 13)).foregroundStyle(Palette.faint)
                }
            } else {
                if !upcoming.isEmpty { section("Upcoming", Array(upcoming.reversed())) }
                if !past.isEmpty { section("Past", past) }
            }
        }
        .sheet(isPresented: $showNew) { EventEditorSheet(event: nil) }
        .sheet(item: $editing) { e in EventEditorSheet(event: e) }
        .onChange(of: signals.pendingNewEvent) { _, now in if now { consumeNewEvent() } }
        .onAppear { if signals.pendingNewEvent { consumeNewEvent() } }
    }

    /// Open a fresh event editor in response to a double-tap on the Journal tab.
    private func consumeNewEvent() {
        signals.pendingNewEvent = false
        showNew = true
    }

    private func section(_ title: String, _ items: [EventItem]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionTitle(text: title)
            ForEach(items) { eventRow($0) }
        }
    }

    private func eventRow(_ e: EventItem) -> some View {
        Button { editing = e } label: {
            Card {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 8) {
                        if let tag = state.primaryTag(for: e) {
                            Image(systemName: tag.symbol).font(.system(size: 11, weight: .bold)).foregroundStyle(tag.color)
                        }
                        Text(e.title.isEmpty ? "Untitled" : e.title)
                            .font(.system(size: 15, weight: .semibold)).foregroundStyle(Palette.text).lineLimit(1)
                        if e.special { Image(systemName: "star.fill").font(.system(size: 10)).foregroundStyle(Palette.amber) }
                        Spacer()
                        Text(Fmt.day(e.date)).font(.system(size: 11)).foregroundStyle(Palette.faint)
                    }
                    if !e.media.isEmpty {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 6) { ForEach(e.media) { thumb($0) } }
                        }
                    }
                    if !e.note.isEmpty {
                        Text(e.note).font(.system(size: 12)).foregroundStyle(Palette.muted).lineLimit(2)
                    }
                }
            }
        }
        .buttonStyle(KPressStyle())
        .contextMenu {
            Button(role: .destructive) { state.deleteEvent(e.id) } label: { Label("Delete", systemImage: "trash") }
        }
    }

    private func thumb(_ m: EventMedia) -> some View {
        Group {
            if m.kind == .image, let img = eventImage(m.data) {
                Image(uiImage: img).resizable().scaledToFill()
            } else if m.kind == .video, let p = m.poster, let img = eventImage(p) {
                Image(uiImage: img).resizable().scaledToFill()
                    .overlay(Image(systemName: "play.circle.fill").font(.system(size: 18)).foregroundStyle(.white))
            } else {
                Palette.surface2
            }
        }
        .frame(width: 64, height: 64)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}

func eventImage(_ base64: String) -> UIImage? {
    guard let d = Data(base64Encoded: base64) else { return nil }
    return UIImage(data: d)
}

/// Add / edit one event (iOS). Image-first via PhotosPicker.
private struct EventEditorSheet: View {
    @EnvironmentObject var state: AppState
    @Environment(\.dismiss) private var dismiss
    let event: EventItem?

    @State private var title = ""
    @State private var date = Date()
    @State private var note = ""
    @State private var tagID = ""
    @State private var special = false
    @State private var media: [EventMedia] = []
    @State private var pickerItems: [PhotosPickerItem] = []
    @State private var loaded = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    KLabeledField(label: "Title", placeholder: "What happened?", text: $title)

                    VStack(alignment: .leading, spacing: 5) {
                        KFieldLabel(text: "Date")
                        DatePicker("", selection: $date, displayedComponents: .date)
                            .labelsHidden().tint(Palette.brand)
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        KFieldLabel(text: "Tag")
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) { ForEach(state.eventTags) { tagChip($0) } }
                        }
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        KFieldLabel(text: "Note")
                        TextEditor(text: $note)
                            .frame(height: 96).scrollContentBackground(.hidden)
                            .padding(8).foregroundStyle(Palette.text)
                            .background(Palette.bg, in: RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).strokeBorder(Palette.border, lineWidth: 1))
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            KFieldLabel(text: "Photos")
                            Spacer()
                            PhotosPicker(selection: $pickerItems, maxSelectionCount: 8, matching: .images) {
                                Label("Add", systemImage: "photo.badge.plus")
                                    .font(.system(size: 12, weight: .semibold)).foregroundStyle(Palette.brand)
                            }
                        }
                        if !media.isEmpty {
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 8) {
                                    ForEach(media) { m in
                                        ZStack(alignment: .topTrailing) {
                                            if let img = eventImage(m.data) {
                                                Image(uiImage: img).resizable().scaledToFill()
                                                    .frame(width: 72, height: 72)
                                                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                                            }
                                            Button { media.removeAll { $0.id == m.id } } label: {
                                                Image(systemName: "xmark.circle.fill").font(.system(size: 16))
                                                    .foregroundStyle(.white).background(Circle().fill(.black.opacity(0.4)))
                                            }
                                            .padding(3)
                                        }
                                    }
                                }
                            }
                        }
                    }

                    Toggle(isOn: $special) {
                        Text("Special — highlight this one").font(.system(size: 13)).foregroundStyle(Palette.text)
                    }
                    .tint(Palette.brand)
                }
                .padding(16)
            }
            .background(Palette.bg.ignoresSafeArea())
            .navigationTitle(event == nil ? "New event" : "Edit event")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }.disabled(title.trimmingCharacters(in: .whitespaces).isEmpty)
                }
                if event != nil {
                    ToolbarItem(placement: .destructiveAction) {
                        Button(role: .destructive) { if let e = event { state.deleteEvent(e.id) }; dismiss() } label: {
                            Image(systemName: "trash")
                        }
                    }
                }
            }
            .onChange(of: pickerItems) { _, items in Task { await loadPicked(items) } }
            .onAppear {
                guard !loaded else { return }
                loaded = true
                if let e = event {
                    title = e.title; note = e.note; special = e.special; media = e.media
                    tagID = e.tagIDs.first ?? ""
                    if let d = AppState.date(fromKey: e.date) { date = d }
                } else {
                    tagID = state.eventTags.first?.id ?? ""
                }
            }
        }
    }

    private func tagChip(_ tag: EventTag) -> some View {
        let on = tagID == tag.id
        return Button { tagID = on ? "" : tag.id } label: {
            HStack(spacing: 5) {
                Image(systemName: tag.symbol).font(.system(size: 10, weight: .bold))
                Text(tag.name).font(.system(size: 12, weight: .semibold))
            }
            .foregroundStyle(on ? Palette.bg : tag.color)
            .padding(.horizontal, 11).padding(.vertical, 7)
            .background(on ? AnyShapeStyle(tag.color) : AnyShapeStyle(tag.color.opacity(0.14)), in: Capsule())
        }
        .buttonStyle(KPressStyle())
    }

    private func loadPicked(_ items: [PhotosPickerItem]) async {
        for item in items {
            if let data = try? await item.loadTransferable(type: Data.self),
               let ui = UIImage(data: data),
               let jpeg = ui.jpegData(compressionQuality: 0.7) {
                let b64 = jpeg.base64EncodedString()
                await MainActor.run { media.append(EventMedia(kind: .image, data: b64)) }
            }
        }
        await MainActor.run { pickerItems = [] }
    }

    private func save() {
        let key = AppState.dateKey(date)
        let tagIDs = tagID.isEmpty ? [] : [tagID]
        let t = title.trimmingCharacters(in: .whitespaces)
        if var e = event {
            e.title = t; e.date = key; e.note = note; e.tagIDs = tagIDs; e.special = special; e.media = media
            state.updateEvent(e)
        } else {
            state.addEvent(date: key, title: t, tagIDs: tagIDs, note: note, special: special, media: media)
        }
        dismiss()
    }
}
