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
    /// Event media loads from R2 asynchronously; without observing the store the
    /// bytes land in cache and the view never re-renders — which is exactly why
    /// thumbnails stayed grey placeholders on iPhone.
    @ObservedObject private var mediaStore = EventMediaStore.shared
    /// ONE presentation for both "new" and "edit". Two `.sheet` modifiers on the
    /// same view is a SwiftUI trap — only one of them ever presents, which is why
    /// tapping an event stopped opening it.
    @State private var editTarget: EditTarget?
    @State private var pendingDelete: EventItem?
    @State private var viewingMedia: EventMedia?
    @State private var viewingAll: [EventMedia] = []

    /// The day an event next happens, or nil if it is behind us for good.
    ///
    /// A repeating event always has a next one, which is why the split below is
    /// on this rather than on `date`: a birthday anchored in 1965 is not a past
    /// memory, it is the thing coming up in March.
    private func nextDay(_ e: EventItem) -> String? {
        EventRecurrence.next(e, onOrAfter: state.todayKey)
    }

    /// Soonest first, each paired with the occurrence it is showing.
    private var upcoming: [(event: EventItem, day: String)] {
        state.events.compactMap { e in nextDay(e).map { (event: e, day: $0) } }
            .sorted { $0.day == $1.day ? $0.event.title < $1.event.title : $0.day < $1.day }
    }

    /// Only things that will not come round again.
    private var past: [EventItem] {
        state.events.filter { nextDay($0) == nil }.sorted { $0.date > $1.date }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Gap.screen) {
            // No "New" button here. `JournalView` puts it in the navigation bar
            // for both halves of the tab, which is where iOS puts a screen's
            // action and the only way the two halves look like one screen.
            if state.events.isEmpty {
                Card {
                    Text("Nothing yet. Tap New to add a trip, a shoot, or any moment.")
                        .font(.footnote).foregroundStyle(Palette.faint)
                }
                .onTapGesture(count: 2) { editTarget = EditTarget(nil) }
            } else {
                if !upcoming.isEmpty {
                    section("Upcoming", upcoming.map { ($0.event, $0.day) })
                }
                if !past.isEmpty {
                    section("Past", past.map { ($0, $0.date) })
                }
            }
        }
        .sheet(item: $editTarget) { target in EventEditorSheet(event: target.event) }
        .fullScreenCover(item: $viewingMedia) { m in
            EventMediaViewer(media: viewingAll, start: m, onClose: { viewingMedia = nil })
        }
        .holdToDelete(
            isPresented: Binding(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } }),
            title: pendingDelete.map { "Delete \($0.title.isEmpty ? "this event" : $0.title)?" } ?? "Delete this event?",
            message: "This can't be undone."
        ) {
            if let e = pendingDelete { state.deleteEvent(e.id) }
            pendingDelete = nil
        }
        .onChange(of: signals.pendingNewEvent) { _, now in if now { consumeNewEvent() } }
        .onAppear { if signals.pendingNewEvent { consumeNewEvent() } }
    }

    /// Open a fresh event editor in response to a double-tap on the Journal tab.
    private func consumeNewEvent() {
        signals.pendingNewEvent = false
        editTarget = EditTarget(nil)
    }

    private func section(_ title: String, _ items: [(EventItem, String)]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionTitle(text: title)
            ForEach(items, id: \.0.id) { pair in eventRow(pair.0, on: pair.1) }
        }
    }

    private func eventRow(_ e: EventItem, on day: String) -> some View {
        Button { Haptics.tap(); editTarget = EditTarget(e) } label: {
            Card {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 8) {
                        if let tag = state.primaryTag(for: e) {
                            Image(systemName: tag.symbol).font(.caption2.weight(.bold)).foregroundStyle(tag.color)
                        }
                        Text(e.title.isEmpty ? "Untitled" : e.title)
                            .font(.subheadline.weight(.semibold)).foregroundStyle(Palette.text).lineLimit(1)
                        if e.special { Image(systemName: "star.fill").font(.caption2).foregroundStyle(Palette.attention) }
                        Spacer()
                        // The day it NEXT happens, not the day it was anchored.
                        // A birthday row reading "12 Mar 1965" is a row about
                        // the wrong thing.
                        Text(Fmt.day(day)).font(.caption2).foregroundStyle(Palette.faint)
                    }
                    if e.recurrence.repeats || !e.reminders.isEmpty {
                        HStack(spacing: 6) {
                            if e.recurrence.repeats {
                                chip(EventRecurrence.shortDescribe(e.recurrence),
                                     "repeat", Palette.action)
                            }
                            if let n = EventRecurrence.ordinal(e, on: day) {
                                chip(EventRecurrence.ordinalLabel(n), "gift", Palette.attention)
                            }
                            if let soonest = e.reminders.max(by: { $0.days < $1.days }) {
                                chip(e.reminders.count == 1
                                     ? soonest.shortLabel
                                     : "\(soonest.shortLabel) +\(e.reminders.count - 1)",
                                     "bell.fill", Palette.blue)
                            }
                        }
                    }
                    if !e.media.isEmpty {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 6) {
                                ForEach(e.media) { m in
                                    thumb(m)
                                        .onTapGesture {
                                            viewingAll = e.media
                                            viewingMedia = m
                                        }
                                }
                            }
                        }
                    }
                    if !e.note.isEmpty {
                        Text(e.note).font(.caption).foregroundStyle(Palette.muted).lineLimit(2)
                    }
                }
            }
        }
        .fluidPressable(scale: 0.99)
        .contextMenu {
            Button(role: .destructive) { pendingDelete = e } label: { Label("Delete", systemImage: "trash") }
        }
    }

    private func chip(_ text: String, _ symbol: String, _ tint: Color) -> some View {
        HStack(spacing: 3) {
            Image(systemName: symbol).font(.system(size: 8, weight: .bold))
            Text(text).font(.caption2.weight(.semibold))
        }
        .foregroundStyle(tint)
        .padding(.horizontal, 7).padding(.vertical, 3)
        .background(tint.opacity(0.14), in: Capsule())
    }

    private func thumb(_ m: EventMedia) -> some View {
        ZStack {
            EventThumb(media: m, width: 64, height: 64) {
                Palette.surfaceElevated
            }
            if m.kind == .video {
                Image(systemName: "play.circle.fill").font(.body).foregroundStyle(.white)
            }
        }
        .frame(width: 64, height: 64)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
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
    /// Which tag the single-select picker was seeded with, so a deselect removes
    /// that one rather than every tag the event has.
    @State private var originalTagID = ""
    @State private var special = false
    @State private var time: String?
    @State private var recurrence: Recurrence = .none
    @State private var reminders: [ReminderLead] = []
    @State private var media: [EventMedia] = []
    @State private var pickerItems: [PhotosPickerItem] = []
    @State private var loaded = false
    @State private var showDelete = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    KLabeledField(label: "Title", placeholder: "What happened?", text: $title)

                    VStack(alignment: .leading, spacing: 5) {
                        KFieldLabel(text: "Date")
                        DatePicker("", selection: $date, displayedComponents: .date)
                            .labelsHidden().tint(Palette.action)
                    }

                    // Straight after the date, because "when" is one question
                    // and this is the rest of the answer to it.
                    EventScheduleEditor(time: $time, recurrence: $recurrence,
                                        reminders: $reminders)

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
                            .background(Palette.background, in: RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).strokeBorder(Palette.border, lineWidth: 1))
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            KFieldLabel(text: "Photos")
                            Spacer()
                            PhotosPicker(selection: $pickerItems, maxSelectionCount: 8, matching: .images) {
                                Label("Add", systemImage: "photo.badge.plus")
                                    .font(.caption.weight(.semibold)).foregroundStyle(Palette.action)
                            }
                        }
                        if !media.isEmpty {
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 8) {
                                    ForEach(media) { m in
                                        ZStack(alignment: .topTrailing) {
                                            EventThumb(media: m, width: 72, height: 72) {
                                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                                    .fill(Palette.surfaceElevated)
                                            }
                                            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                                            Button { media.removeAll { $0.id == m.id } } label: {
                                                Image(systemName: "xmark.circle.fill").font(.callout)
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
                        Text("Special — highlight this one").font(.footnote).foregroundStyle(Palette.text)
                    }
                    .tint(Palette.action)
                }
                .padding(16)
            }
            .background(Palette.background)
            .navigationTitle(event == nil ? "New event" : "Edit event")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }.disabled(title.trimmingCharacters(in: .whitespaces).isEmpty)
                }
                if event != nil {
                    ToolbarItem(placement: .destructiveAction) {
                        Button(role: .destructive) { showDelete = true } label: {
                            Image(systemName: "trash")
                        }
                        .holdToDelete(isPresented: $showDelete,
                                      title: "Delete this event?",
                                      message: "It goes to the recycle bin for \(TrashRetention.days) days.") {
                            if let e = event { state.deleteEvent(e.id) }
                            dismiss()
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
                    time = e.time; recurrence = e.recurrence; reminders = e.reminders
                    tagID = e.tagIDs.first ?? ""
                    originalTagID = tagID
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
                Image(systemName: tag.symbol).font(.caption2.weight(.bold))
                Text(tag.name).font(.caption.weight(.semibold))
            }
            .foregroundStyle(on ? Palette.background : tag.color)
            .padding(.horizontal, 11).padding(.vertical, 7)
            .background(on ? AnyShapeStyle(tag.color) : AnyShapeStyle(tag.color.opacity(0.14)), in: Capsule())
        }
        .buttonStyle(.plain)
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
        // Keep the tags this editor never showed. It binds only `tagIDs.first`,
        // so writing `[tagID]` silently dropped the rest: tag a memory Travel +
        // Family + Milestone on the Mac, change only its title on the phone, and
        // it came back with just Travel.
        let existing = event?.tagIDs ?? []
        let tagIDs: [String]
        if tagID.isEmpty {
            tagIDs = existing.filter { $0 != originalTagID }          // deselected the primary
        } else if existing.contains(tagID) {
            // Already on the event — the picker moved to a tag it already had,
            // which is a reorder, not a replacement. Dropping the old primary
            // here lost a tag the user never touched.
            tagIDs = [tagID] + existing.filter { $0 != tagID }
        } else {
            tagIDs = [tagID] + existing.filter { $0 != originalTagID && $0 != tagID }
        }
        let t = title.trimmingCharacters(in: .whitespaces)
        if var e = event {
            e.title = t; e.date = key; e.note = note; e.tagIDs = tagIDs; e.special = special; e.media = media
            e.time = time; e.recurrence = recurrence; e.reminders = reminders
            state.updateEvent(e)
        } else {
            state.addEvent(date: key, title: t, tagIDs: tagIDs, note: note, special: special,
                           media: media, time: time, recurrence: recurrence, reminders: reminders)
        }
        dismiss()
    }
}


/// Identifies a single event-editor presentation. `nil` event means "new".
private struct EditTarget: Identifiable {
    let event: EventItem?
    var id: String { event?.id ?? "__new__" }
    init(_ event: EventItem?) { self.event = event }
}
