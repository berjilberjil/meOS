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
                    .background(Palette.background, in: RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                        .strokeBorder(urlFocused ? Palette.action : Palette.border, lineWidth: 1.5))
                    Button { Haptics.tap(); addVideo() } label: {
                        Text("Add")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Brandmark.ink)
                            .padding(.horizontal, 14).padding(.vertical, 10)
                            .background(Palette.action, in: Capsule())
                    }
                    .fluidPressable()
                    .disabled(urlInput.trimmingCharacters(in: .whitespaces).isEmpty)
                    .opacity(urlInput.trimmingCharacters(in: .whitespaces).isEmpty ? 0.4 : 1)
                }

                if let err = addError {
                    Text(err).font(.footnote).foregroundStyle(Palette.warning)
                }

                if todayVideos.isEmpty {
                    Text("Nothing logged today.")
                        .font(.subheadline).foregroundStyle(Palette.faint)
                } else {
                    ForEach(todayVideos) { item in videoRow(item) }
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
                    default: Palette.surfaceElevated
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
        .fluidPressable(scale: 0.99)
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
        let saved = state.addWatchItem(WatchItem(url: raw, videoId: id, thumbUrl: YouTube.thumbURL(id)),
                                       on: day ?? state.todayKey)
        urlInput = ""
        Task { @MainActor in
            // Merge into the live row, never write back a snapshot taken before
            // these awaits — the lookup takes seconds, and anything ticked or
            // typed on the new card in that window was being reverted.
            let meta = await YouTube.fetchMeta(id: id)
            state.enrichWatchItem(id: saved.id, title: meta.title, channel: meta.channel,
                                  thumbUrl: meta.thumbUrl.isEmpty ? nil : meta.thumbUrl)
            if let cat = await state.categorizeVideo(title: meta.title, channel: meta.channel) {
                state.enrichWatchItem(id: saved.id, category: cat)
            }
        }
    }
}
