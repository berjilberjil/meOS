import SwiftUI
#if os(iOS)
import UIKit
#else
import AppKit
#endif

/// Paste a YouTube link, see today's videos. Shared by Mac Productivity and
/// the iPhone Today tab — no AppKit.
struct WatchLogCard: View {
    /// The day being shown. Today unless the Today page has been swiped.
    var day: String? = nil
    @EnvironmentObject var state: AppState
    @State private var urlInput = ""
    @State private var addError: String?
    @FocusState private var urlFocused: Bool

    private var todayVideos: [WatchItem] {
        state.sortedWatch.filter { $0.addedAt.hasPrefix(day ?? state.todayKey) }
    }

    var body: some View {
        Card(padding: 16) {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    SectionTitle(text: "Videos")
                    Spacer()
                    Text("\(todayVideos.count) today")
                        .font(.footnote.weight(.semibold)).foregroundStyle(Palette.faint)
                }

                HStack(spacing: 8) {
                    HStack(spacing: 8) {
                        Image(systemName: "link").font(.footnote.weight(.bold)).foregroundStyle(Palette.faint)
                        TextField("", text: $urlInput,
                                  prompt: Text("Paste a YouTube link…").foregroundColor(Palette.faint))
                            .textFieldStyle(.plain).font(.subheadline).foregroundStyle(Palette.text)
                            .focused($urlFocused)
                            .onSubmit { addVideo() }
                    }
                    .padding(.horizontal, 12).padding(.vertical, 10)
                    .background(Palette.bg, in: RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                        .strokeBorder(urlFocused ? Palette.brand : Palette.border, lineWidth: 1.5))
                    Button("Add") { addVideo() }
                        .buttonStyle(.borderedProminent)
                        .disabled(urlInput.trimmingCharacters(in: .whitespaces).isEmpty)
                }

                if let err = addError {
                    Text(err).font(.footnote).foregroundStyle(Palette.amber)
                }

                if todayVideos.isEmpty {
                    Text("Nothing logged today.")
                        .font(.subheadline).foregroundStyle(Palette.faint)
                } else {
                    ForEach(todayVideos) { item in videoRow(item) }
                }
            }
        }
    }

    private func videoRow(_ item: WatchItem) -> some View {
        let title = item.title.isEmpty ? "Fetching title…" : item.title
        return Button {
            if let u = URL(string: item.url) {
                #if os(iOS)
                UIApplication.shared.open(u)
                #else
                NSWorkspace.shared.open(u)
                #endif
            }
        } label: {
            HStack(spacing: 12) {
                AsyncImage(url: URL(string: item.thumbUrl)) { phase in
                    switch phase {
                    case .success(let img): img.resizable().scaledToFill()
                    default: Palette.surface2
                    }
                }
                .frame(width: 92, height: 56)
                .clipped()
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                VStack(alignment: .leading, spacing: 3) {
                    Text(title).font(.subheadline.weight(.semibold)).foregroundStyle(Palette.text)
                        .lineLimit(2).multilineTextAlignment(.leading)
                    Text(item.channel.isEmpty ? item.category.label : item.channel)
                        .font(.caption).foregroundStyle(Palette.faint)
                }
                Spacer(minLength: 0)
            }
        }
        .buttonStyle(.plain)
    }

    private func addVideo() {
        let raw = urlInput.trimmingCharacters(in: .whitespaces)
        guard !raw.isEmpty else { return }
        guard let id = YouTube.videoID(from: raw) else {
            addError = "That doesn’t look like a YouTube link."
            return
        }
        if state.watch.contains(where: { $0.videoId == id }) {
            addError = "Already in your list."
            urlInput = ""
            return
        }
        addError = nil
        let saved = state.addWatchItem(WatchItem(url: raw, videoId: id, thumbUrl: YouTube.thumbURL(id)))
        urlInput = ""
        Task { @MainActor in
            let meta = await YouTube.fetchMeta(id: id)
            var updated = saved
            updated.title = meta.title
            updated.channel = meta.channel
            if !meta.thumbUrl.isEmpty { updated.thumbUrl = meta.thumbUrl }
            state.updateWatchItem(updated)
            if let cat = await state.categorizeVideo(title: meta.title, channel: meta.channel) {
                updated.category = cat
                state.updateWatchItem(updated)
            }
        }
    }
}
