import UIKit
import UniformTypeIdentifiers

/// "Share → meOS", from the YouTube app or anywhere else that shares a link.
///
/// There is nothing to fill in. It reads the link, checks it really is a
/// YouTube video, queues it for the Productivity log and dismisses itself.
/// Title, channel, thumbnail and category are filled in by the app when it
/// picks the item up — this process stays deliberately dumb, because it holds
/// neither the vault key nor the app's session.
final class ShareViewController: UIViewController {

    // Fold-dark, hardcoded: pulling in `Theme.swift` would drag SwiftUI and the
    // whole settings stack into an extension that shows one line of text.
    private static let ink   = UIColor(red: 0.04, green: 0.05, blue: 0.05, alpha: 1)
    private static let green = UIColor(red: 0.12, green: 0.83, blue: 0.48, alpha: 1)
    private static let amber = UIColor(red: 0.98, green: 0.72, blue: 0.24, alpha: 1)

    private let card = UIView()
    private let icon = UIImageView()
    private let label = UILabel()

    override func viewDidLoad() {
        super.viewDidLoad()
        buildCard()
        Task { await handleShare() }
    }

    // MARK: - The one-line confirmation

    private func buildCard() {
        view.backgroundColor = .clear

        card.backgroundColor = Self.ink
        card.layer.cornerRadius = 18
        card.layer.cornerCurve = .continuous
        card.layer.borderWidth = 1
        card.layer.borderColor = UIColor.white.withAlphaComponent(0.10).cgColor
        card.alpha = 0
        card.transform = CGAffineTransform(scaleX: 0.94, y: 0.94)
        card.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(card)

        icon.contentMode = .scaleAspectFit
        icon.tintColor = Self.green
        icon.translatesAutoresizingMaskIntoConstraints = false

        label.text = "Saving to meOS…"
        label.textColor = .white
        label.font = .systemFont(ofSize: 15, weight: .semibold)
        label.translatesAutoresizingMaskIntoConstraints = false

        let row = UIStackView(arrangedSubviews: [icon, label])
        row.axis = .horizontal
        row.spacing = 10
        row.alignment = .center
        row.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(row)

        NSLayoutConstraint.activate([
            card.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            card.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            row.topAnchor.constraint(equalTo: card.topAnchor, constant: 18),
            row.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -18),
            row.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 22),
            row.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -22),
            icon.widthAnchor.constraint(equalToConstant: 22),
            icon.heightAnchor.constraint(equalToConstant: 22)
        ])
    }

    // MARK: - Work

    private func handleShare() async {
        guard let raw = await sharedText() else {
            return await finish(ok: false, message: "Nothing to save")
        }
        guard let (id, link) = YouTube.sharedLink(in: raw) else {
            return await finish(ok: false, message: "Not a YouTube link")
        }
        let saved = ShareInbox.add(videoId: id, url: link)
        await finish(ok: saved, message: saved ? "Saved to meOS" : "Couldn’t save")
    }

    /// What the host handed over, URLs first.
    ///
    /// Two passes on purpose: a share often carries a plain-text blurb *and* the
    /// link, in whichever order the sending app felt like. Taking the first
    /// attachment of either kind meant a leading "Check this out" beat the URL
    /// sitting right behind it.
    private func sharedText() async -> String? {
        let providers = (extensionContext?.inputItems as? [NSExtensionItem] ?? [])
            .flatMap { $0.attachments ?? [] }

        for provider in providers where provider.hasItemConformingToTypeIdentifier(UTType.url.identifier) {
            if let loaded = try? await provider.loadItem(forTypeIdentifier: UTType.url.identifier),
               let url = loaded as? URL {
                return url.absoluteString
            }
        }
        for provider in providers where provider.hasItemConformingToTypeIdentifier(UTType.plainText.identifier) {
            if let loaded = try? await provider.loadItem(forTypeIdentifier: UTType.plainText.identifier),
               let text = loaded as? String {
                return text
            }
        }
        return nil
    }

    private func finish(ok: Bool, message: String) async {
        icon.image = UIImage(systemName: ok ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
        icon.tintColor = ok ? Self.green : Self.amber
        label.text = message
        UIView.animate(withDuration: 0.18) {
            self.card.alpha = 1
            self.card.transform = .identity
        }
        // Long enough to read, short enough that it never feels like a step.
        try? await Task.sleep(nanoseconds: ok ? 750_000_000 : 1_500_000_000)
        extensionContext?.completeRequest(returningItems: nil)
    }
}
