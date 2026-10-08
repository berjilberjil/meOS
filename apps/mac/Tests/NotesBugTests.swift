import XCTest
import AppKit
@testable import meOS

/// Evidence for two reported Notes bugs: new notes vanishing, and images
/// disappearing. These tests characterize the CURRENT behaviour — a failure
/// here localizes the bug rather than guessing at it.
final class NotesBugTests: XCTestCase {

    // MARK: Bug A — "new notes are not creatable"

    /// `addBlockNote()` seeds `BlockDoc()`. NotesView.persistCurrent deletes any
    /// note whose title is blank AND whose doc `isEffectivelyEmpty`. If a fresh
    /// document reports empty, every untouched new note is deleted on the next
    /// persist — which is exactly "I can't create a note".
    func testFreshDocumentReportsItselfEmpty() {
        XCTAssertTrue(BlockDoc().isEffectivelyEmpty,
                      "a brand-new note is considered empty, so persistCurrent deletes it")
    }

    func testDocWithTypedTextIsNotEmpty() {
        XCTAssertFalse(BlockDoc(blocks: [Block.paragraph("hello")]).isEffectivelyEmpty)
    }

    /// An image-only note must NOT count as empty, or adding a picture and
    /// navigating away would delete the note along with the picture.
    func testImageOnlyDocIsNotEmpty() {
        let img = Block(type: .image, src: "AAAA")
        XCTAssertFalse(BlockDoc(blocks: [img]).isEffectivelyEmpty,
                       "an image is content; this note must survive persistCurrent")
    }

    func testImagePlusTrailingParagraphIsNotEmpty() {
        // insertMediaBlock always appends an editable paragraph after media.
        let doc = BlockDoc(blocks: [Block(type: .image, src: "AAAA"), Block.paragraph()])
        XCTAssertFalse(doc.isEffectivelyEmpty)
    }

    // MARK: Bug B — "images disappear"

    /// The editor round-trips through NSTextStorage: doc -> attributed string ->
    /// storage -> doc. If the base64 does not survive that trip, the image is
    /// gone on the next save.
    func testImageSurvivesAttributedStringRoundTrip() throws {
        let png = try XCTUnwrap(smallPNGBase64(), "could not build a test image")
        let original = BlockDoc(blocks: [Block(type: .image, src: png), Block.paragraph("caption")])

        let attributed = BlockBridge.attributedString(from: original)
        let back = BlockBridge.blockDoc(from: attributed)

        let imageBlocks = back.blocks.filter { $0.type == .image }
        XCTAssertEqual(imageBlocks.count, 1, "the image block did not survive the round trip")
        XCTAssertEqual(imageBlocks.first?.src, png, "the base64 payload was lost or altered")
    }

    /// A note that is only an image — the case most likely to be dropped.
    func testImageOnlyDocSurvivesRoundTrip() throws {
        let png = try XCTUnwrap(smallPNGBase64())
        let original = BlockDoc(blocks: [Block(type: .image, src: png)])
        let back = BlockBridge.blockDoc(from: BlockBridge.attributedString(from: original))
        XCTAssertEqual(back.blocks.filter { $0.type == .image }.count, 1)
        XCTAssertEqual(back.blocks.first(where: { $0.type == .image })?.src, png)
    }

    private func smallPNGBase64() -> String? {
        let img = NSImage(size: NSSize(width: 4, height: 4))
        img.lockFocus()
        NSColor.systemPink.drawSwatch(in: NSRect(x: 0, y: 0, width: 4, height: 4))
        img.unlockFocus()
        guard let tiff = img.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff),
              let png = rep.representation(using: .png, properties: [:]) else { return nil }
        return png.base64EncodedString()
    }
}
