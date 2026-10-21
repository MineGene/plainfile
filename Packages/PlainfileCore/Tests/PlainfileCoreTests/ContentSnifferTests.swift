import Foundation
import XCTest

@testable import PlainfileCore

final class ContentSnifferTests: XCTestCase {
    private func kind(_ bytes: [UInt8]) -> ContentKind { ContentSniffer.kind(of: Data(bytes)) }
    private func kind(_ text: String) -> ContentKind { ContentSniffer.kind(of: Data(text.utf8)) }

    func testRecognisesImageSignatures() throws {
        XCTAssertEqual(kind([0xFF, 0xD8, 0xFF, 0xE0, 0, 0x10]), .jpeg)
        XCTAssertEqual(kind([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0]), .png)
        XCTAssertEqual(kind("GIF89a......"), .gif)
        XCTAssertEqual(kind("RIFF\u{0}\u{0}\u{0}\u{0}WEBPVP8 "), .webp)
        XCTAssertEqual(kind([0, 0, 0, 0x18] + Array("ftypheic".utf8) + [0, 0, 0, 0]), .heif)
        XCTAssertEqual(kind([0, 0, 0, 0x1C] + Array("ftypavif".utf8) + [0, 0, 0, 0]), .avif)
        XCTAssertEqual(kind([0x49, 0x49, 0x2A, 0x00, 8, 0, 0, 0]), .tiff)
        XCTAssertEqual(ContentSniffer.kind(of: try TestImages.planted(.jpeg)), .jpeg)
        XCTAssertEqual(ContentSniffer.kind(of: try TestImages.planted(.png)), .png)
    }

    func testRecognisesWebPagesAndDocuments() {
        XCTAssertEqual(kind("\n  <!DOCTYPE html><html>"), .html)
        XCTAssertEqual(kind("\u{FEFF}<html lang=\"en\">"), .html)
        XCTAssertEqual(kind("<?xml version=\"1.0\"?><svg xmlns=\"http://www.w3.org/2000/svg\">"), .svg)
        XCTAssertEqual(kind("%PDF-1.7\n"), .pdf)
        XCTAssertEqual(kind([0x50, 0x4B, 0x03, 0x04, 0x14, 0]), .zip)
        XCTAssertEqual(kind([]), .empty)
        XCTAssertEqual(kind("just some text"), .unknown)
    }

    func testOnlyImagesAreImages() {
        XCTAssertTrue(ContentKind.webp.isImage)
        XCTAssertFalse(ContentKind.html.isImage)
        XCTAssertFalse(ContentKind.pdf.isImage)
    }
}
