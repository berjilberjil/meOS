#if os(macOS)
import AppKit
import SwiftUI
import UniformTypeIdentifiers

// The Me* screens are written once, against the iPhone's API surface. This file
// is the only place the Mac translates that surface, so the screens stay a
// single source of truth instead of growing #if branches everywhere.

typealias UIImage = NSImage

extension NSImage {
    var scale: CGFloat { 1 }

    func jpegData(compressionQuality q: CGFloat) -> Data? {
        guard let cg = cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
        return NSBitmapImageRep(cgImage: cg).representation(using: .jpeg, properties: [.compressionFactor: q])
    }

    func preparingThumbnail(of target: CGSize) -> NSImage? {
        let scale = min(1, min(target.width / max(size.width, 1), target.height / max(size.height, 1)))
        return resized(to: CGSize(width: size.width * scale, height: size.height * scale))
    }

    func resized(to s: CGSize) -> NSImage {
        let out = NSImage(size: s)
        out.lockFocus()
        draw(in: CGRect(origin: .zero, size: s), from: .zero, operation: .copy, fraction: 1)
        out.unlockFocus()
        return out
    }
}

extension Image {
    init(uiImage: NSImage) { self.init(nsImage: uiImage) }
}

enum UIPasteboard {
    static let general = Board()
    struct Board {
        var string: String? {
            get { NSPasteboard.general.string(forType: .string) }
            nonmutating set {
                NSPasteboard.general.clearContents()
                if let newValue { NSPasteboard.general.setString(newValue, forType: .string) }
            }
        }
    }
}

// iPhone-only text and bar modifiers: meaningless with a hardware keyboard and
// a window title bar, so they are accepted and ignored.
enum TextInputAutocapitalization { case never, words, sentences, characters }
enum UIKeyboardType { case `default`, numberPad, decimalPad, emailAddress, URL, phonePad, asciiCapable, numbersAndPunctuation }
enum NavigationBarTitleDisplayMode { case automatic, inline, large }

extension View {
    func textInputAutocapitalization(_: TextInputAutocapitalization?) -> some View { self }
    func keyboardType(_: UIKeyboardType) -> some View { self }
    func navigationBarTitleDisplayMode(_: NavigationBarTitleDisplayMode) -> some View { self }

    /// A Mac window has no full-screen cover; a sheet is the native equivalent.
    func fullScreenCover<Content: View>(isPresented: Binding<Bool>, onDismiss: (() -> Void)? = nil,
                                        @ViewBuilder content: @escaping () -> Content) -> some View {
        sheet(isPresented: isPresented, onDismiss: onDismiss) { content().frame(minWidth: 560, minHeight: 620) }
    }

    func fullScreenCover<Item: Identifiable, Content: View>(item: Binding<Item?>, onDismiss: (() -> Void)? = nil,
                                                             @ViewBuilder content: @escaping (Item) -> Content) -> some View {
        sheet(item: item, onDismiss: onDismiss) { content($0).frame(minWidth: 560, minHeight: 620) }
    }
}

/// The phone opens its camera; the Mac picks an image file. Same call site.
struct CameraPicker: View {
    let done: (UIImage?) -> Void
    var body: some View {
        VStack(spacing: 18) {
            BigIcon(name: "photo.badge.plus", size: 32, inverted: true)
            Text("Choose an image").font(.title2.bold())
            MButton(title: "Browse…", icon: "folder") {
                let panel = NSOpenPanel()
                panel.allowedContentTypes = [.image]
                panel.allowsMultipleSelection = false
                done(panel.runModal() == .OK ? panel.url.flatMap { NSImage(contentsOf: $0) } : nil)
            }
            Button("Cancel") { done(nil) }.buttonStyle(.press).foregroundStyle(Color.dim)
        }
        .padding(40).frame(width: 420)
    }
}
#endif
