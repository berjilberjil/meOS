import SwiftUI

struct MeJournal: View {
    @EnvironmentObject var state: AppState
    @State private var offset = 0
    private let moods = ["cloud.rain", "cloud", "cloud.sun", "sun.max", "sparkles"]
    private let moodNames = ["Rough", "Meh", "Okay", "Good", "Great"]

    private var date: Date { Calendar.current.date(byAdding: .day, value: offset, to: .now)! }
    private var key: String { AppState.dateKey(date) }

    var body: some View {
        let e = state.journalEntry(key)
        let p = state.journalPresets
        Screen(title: "Journal", sub: date.formatted(.dateTime.weekday(.wide).day().month())) {
            HStack {
                Button { withAnimation(DS.spring) { offset -= 1 } } label: { BigIcon(name: "chevron.left", size: 18) }
                Spacer()
                if offset != 0 { Button { withAnimation(DS.spring) { offset = 0 } } label: { Chip(text: "Today", on: true) } }
                Spacer()
                Button { withAnimation(DS.spring) { offset += 1 } } label: { BigIcon(name: "chevron.right", size: 18) }
                    .disabled(offset >= 0).opacity(offset >= 0 ? 0.3 : 1)
            }
            .buttonStyle(.press).sensoryFeedback(.selection, trigger: offset)

            MCard {
                Text("How was the day?").font(.title2.bold())
                HStack {
                    ForEach(1...5, id: \.self) { i in
                        Button { withAnimation(DS.bouncy) { state.updateJournal(key) { $0.mood = $0.mood == i ? nil : i } } } label: {
                            Image(systemName: moods[i - 1]).font(.system(size: 26, weight: .semibold))
                                .frame(maxWidth: .infinity).frame(height: 64)
                                .foregroundStyle(e.mood == i ? Color.paper : .ink)
                                .background(e.mood == i ? Color.ink : Color.clear, in: .rect(cornerRadius: 20))
                                .scaleEffect(e.mood == i ? 1.08 : 1)
                        }
                        .buttonStyle(.press)
                    }
                }
                Text(e.mood.map { moodNames[$0 - 1] } ?? "Tap one").font(.headline).foregroundStyle(Color.dim).frame(maxWidth: .infinity)
            }
            .sensoryFeedback(.selection, trigger: e.mood)

            MeReflection(icon: "sunrise", title: "Morning", text: e.morning, presets: p.morning) { v in state.updateJournal(key) { $0.morning = v } }
            MeReflection(icon: "moon.stars", title: "Night", text: e.night, presets: p.night) { v in state.updateJournal(key) { $0.night = v } }
            MeListCard(icon: "trophy", title: "Wins", items: e.wins, presets: p.wins) { v in state.updateJournal(key) { $0.wins = v } }
            MeListCard(icon: "lightbulb", title: "Lessons", items: e.lessons, presets: p.lessons) { v in state.updateJournal(key) { $0.lessons = v } }
            MeListCard(icon: "heart", title: "Gratitude", items: e.gratitude, presets: p.gratitude) { v in state.updateJournal(key) { $0.gratitude = v } }
            MeListCard(icon: "exclamationmark.triangle", title: "Mistakes", items: e.mistakes, presets: p.mistakes) { v in state.updateJournal(key) { $0.mistakes = v } }
        }
        .id(key)
    }
}

/// Local draft, committed on submit / focus loss — so typing never fights a sync.
struct MeReflection: View {
    let icon: String
    let title: String
    let text: String
    var presets: [String] = []
    let save: (String) -> Void
    @State private var draft = ""
    @FocusState private var focused: Bool

    var body: some View {
        MCard {
            Label(title, systemImage: icon).font(.title3.bold())
            TextField("Write a line…", text: $draft, axis: .vertical).font(.title3).lineLimit(2...8)
                .focused($focused)
                .onChange(of: focused) { _, f in if !f, draft != text { save(draft) } }
            if draft.isEmpty {
                ScrollView(.horizontal) {
                    HStack { ForEach(presets, id: \.self) { s in Button { draft = s; save(s) } label: { Chip(text: s) }.buttonStyle(.press) } }
                }
                .scrollIndicators(.hidden)
            }
        }
        .onAppear { draft = text }
        .onChange(of: text) { _, t in if !focused { draft = t } }
    }
}

struct MeListCard: View {
    let icon: String
    let title: String
    let items: [String]
    var presets: [String] = []
    let save: ([String]) -> Void
    @State private var draft = ""

    var body: some View {
        MCard {
            HStack {
                Label(title, systemImage: icon).font(.title3.bold())
                Spacer()
                Text("\(items.count)").font(.title3.bold()).contentTransition(.numericText())
            }
            ForEach(items, id: \.self) { item in
                HStack {
                    Text(item).font(.title3)
                    Spacer()
                    Button { withAnimation(DS.spring) { save(items.filter { $0 != item }) } } label: { Image(systemName: "xmark").foregroundStyle(Color.dim) }
                }
                .transition(.move(edge: .top).combined(with: .opacity))
            }
            TextField("Add…", text: $draft).font(.title3).submitLabel(.done).onSubmit { add(draft); draft = "" }
            ScrollView(.horizontal) {
                HStack { ForEach(presets.filter { !items.contains($0) }, id: \.self) { p in Button { add(p) } label: { Chip(text: p) }.buttonStyle(.press) } }
            }
            .scrollIndicators(.hidden)
        }
    }
    private func add(_ s: String) {
        let t = s.trimmingCharacters(in: .whitespaces)
        guard !t.isEmpty, !items.contains(t) else { return }
        withAnimation(DS.spring) { save(items + [t]) }
    }
}
