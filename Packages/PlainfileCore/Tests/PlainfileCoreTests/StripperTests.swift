import Foundation
import UniformTypeIdentifiers
import XCTest

@testable import PlainfileCore

final class ImageStripperTests: XCTestCase {
    /// Strips the given field IDs and returns the before scan, the output and the after scan.
    private func strip(
        _ type: UTType, removing choose: (MetadataField) -> Bool
    ) throws -> (before: ScanReport, removed: Set<String>, output: Data, after: ScanReport, input: Data) {
        let input = try TestImages.planted(type)
        let before = try ImageScanner.scan(data: input)
        let removed = Set(before.fields.filter(choose).map(\.id))
        let output = try ImageStripper.strip(data: input, removing: removed)
        let after = try ImageScanner.scan(data: output)
        return (before, removed, output, after, input)
    }

    func testRemovesLocationAndKeepsTheRest() throws {
        let r = try strip(.jpeg) { $0.group == .location }
        XCTAssertFalse(r.removed.isEmpty, "Test image should carry GPS")
        XCTAssertTrue(r.after.fields.filter { $0.group == .location }.isEmpty, "GPS should be gone")
        XCTAssertTrue(r.after.fields.contains { $0.value == TestImages.author }, "Author was kept")
        XCTAssertTrue(r.after.fields.contains { $0.value == TestImages.make }, "Camera was kept")

        let result = Verifier.verify(
            before: r.before.fields, removed: r.removed, after: r.after.fields, output: r.output)
        XCTAssertTrue(result.passed, "still present: \(result.stillPresent), residue: \(result.residue)")
    }

    func testDefaultSelectionRemovesIdentifyingDataButKeepsOrientation() throws {
        let r = try strip(.jpeg) { $0.removeByDefault }
        let identifying = r.after.fields.filter { [MetadataGroup.location, .people, .device].contains($0.group) }
        XCTAssertTrue(identifying.isEmpty, "Left behind: \(identifying.map(\.name))")
        XCTAssertFalse(Verifier.contains(r.output, text: TestImages.author))
        XCTAssertFalse(Verifier.contains(r.output, text: TestImages.make))
        XCTAssertTrue(
            r.after.fields.contains { $0.name.hasSuffix("Orientation") }, "Orientation is kept by default")

        let result = Verifier.verify(
            before: r.before.fields, removed: r.removed, after: r.after.fields, output: r.output)
        XCTAssertTrue(result.passed, "still present: \(result.stillPresent), residue: \(result.residue)")
    }

    func testPictureIsUnchanged() throws {
        let r = try strip(.jpeg) { $0.removeByDefault }
        XCTAssertTrue(try ImageComparator.pixelsMatch(r.input, r.output))
    }

    func testPNG() throws {
        let input = try TestImages.planted(.png)
        let before = try ImageScanner.scan(data: input)
        guard before.fields.contains(where: { $0.value == TestImages.author }) else {
            throw XCTSkip("macOS didn't embed the planted author in the test PNG")
        }
        let removed = Set(before.fields.filter(\.removeByDefault).map(\.id))
        let output = try ImageStripper.strip(data: input, removing: removed)
        let after = try ImageScanner.scan(data: output)
        XCTAssertFalse(after.fields.contains { $0.value == TestImages.author })
        XCTAssertFalse(Verifier.contains(output, text: TestImages.author))
        XCTAssertTrue(try ImageComparator.pixelsMatch(input, output))
    }

    func testRefusesFilesWithSeveralImages() throws {
        let input = try TestImages.planted(.tiff, imageCount: 2)
        XCTAssertThrowsError(try ImageStripper.strip(data: input, removing: [])) { error in
            XCTAssertEqual(error as? StripError, .multipleImages(2))
        }
    }

    func testRefusesFormatsItCannotCopyLosslessly() throws {
        let input = try TestImages.planted(.gif)
        XCTAssertThrowsError(try ImageStripper.strip(data: input, removing: [])) { error in
            guard case .unsupportedType = error as? StripError else {
                return XCTFail("Expected unsupportedType, got \(error)")
            }
        }
    }
}

final class VerifierTests: XCTestCase {
    private func field(_ id: String, _ value: String, literal: Bool = true) -> MetadataField {
        MetadataField(
            id: id, group: .people, name: id, value: value, source: "Test", risk: .high,
            literal: literal)
    }

    func testFlagsFieldsStillPresent() {
        let author = field("a", "Someone Specific")
        let result = Verifier.verify(before: [author], removed: ["a"], after: [author], output: Data())
        XCTAssertEqual(result.stillPresent.map(\.id), ["a"])
        XCTAssertFalse(result.passed)
    }

    func testFindsResidueInBytes() {
        let author = field("a", "Someone Specific")
        for encoding in [String.Encoding.utf8, .utf16LittleEndian, .utf16BigEndian] {
            var bytes = Data([0, 1, 2])
            bytes.append("Someone Specific".data(using: encoding)!)
            let result = Verifier.verify(before: [author], removed: ["a"], after: [], output: bytes)
            XCTAssertEqual(result.residue.map(\.id), ["a"], "\(encoding)")
        }
    }

    func testIgnoresShortAndDescriptiveValues() {
        let short = field("s", "Bob")
        let described = field("d", "12 bytes of data", literal: false)
        let bytes = Data("Bob 12 bytes of data".utf8)
        let result = Verifier.verify(before: [short, described], removed: ["s", "d"], after: [], output: bytes)
        XCTAssertTrue(result.passed)
    }

    func testReportsKeptFieldsThatDisappeared() {
        let kept = field("k", "Maker note value")
        let result = Verifier.verify(before: [kept], removed: [], after: [], output: Data())
        XCTAssertEqual(result.alsoRemoved.map(\.id), ["k"])
        XCTAssertTrue(result.passed)
    }
}

final class FormatTests: XCTestCase {
    private func assertDefaultStripCleans(_ type: UTType, file: StaticString = #filePath, line: UInt = #line) throws {
        let input: Data
        do { input = try TestImages.planted(type) } catch {
            throw XCTSkip("macOS on this runner can't write \(type.identifier) test images")
        }
        let before = try ImageScanner.scan(data: input)
        guard before.fields.contains(where: { $0.value == TestImages.author }) else {
            throw XCTSkip("macOS didn't embed the planted author in the test \(type.identifier)")
        }
        let removed = Set(before.fields.filter(\.removeByDefault).map(\.id))
        let output = try ImageStripper.strip(data: input, removing: removed)
        let after = try ImageScanner.scan(data: output)
        let result = Verifier.verify(before: before.fields, removed: removed, after: after.fields, output: output)
        XCTAssertTrue(
            result.passed, "still present: \(result.stillPresent.map(\.id)), residue: \(result.residue.map(\.id))",
            file: file, line: line)
        XCTAssertTrue(try ImageComparator.pixelsMatch(input, output), "pixels changed", file: file, line: line)
    }

    func testTIFFIsRefused() throws {
        let input = try TestImages.planted(.tiff)
        XCTAssertThrowsError(try ImageStripper.strip(data: input, removing: ["img0.{TIFF}.Make"])) { error in
            guard case .unsupportedType = error as? StripError else {
                return XCTFail("Expected unsupportedType, got \(error)")
            }
        }
    }
    func testHEIC() throws { try assertDefaultStripCleans(.heic) }
}

final class PNGStripperTests: XCTestCase {
    /// Builds a chunk with a placeholder CRC (the stripper copies chunks as-is).
    private func chunk(_ type: String, _ body: Data) -> Data {
        var d = Data()
        let n = UInt32(body.count).bigEndian
        withUnsafeBytes(of: n) { d.append(contentsOf: $0) }
        d.append(Data(type.utf8))
        d.append(body)
        d.append(Data([0, 0, 0, 0]))
        return d
    }

    func testDropsMetadataChunksAndKeepsPictureChunksByteForByte() throws {
        let ihdr = chunk("IHDR", Data(repeating: 1, count: 13))
        let idat = chunk("IDAT", Data(repeating: 7, count: 40))
        let icc = chunk("iCCP", Data(repeating: 3, count: 10))
        var png = PNGStripper.signature
        png.append(ihdr)
        png.append(icc)
        png.append(chunk("tEXt", Data("Author\u{0}Planted Author".utf8)))
        png.append(chunk("iTXt", Data("XML:com.adobe.xmp".utf8)))
        png.append(chunk("eXIf", Data(repeating: 9, count: 20)))
        png.append(chunk("iDOT", Data(repeating: 2, count: 28)))
        png.append(idat)
        png.append(chunk("IEND", Data()))
        png.append(Data("trailer".utf8))

        let (output, dropped) = try PNGStripper.strip(png)
        var expected = PNGStripper.signature
        expected.append(ihdr)
        expected.append(icc)
        expected.append(idat)
        expected.append(chunk("IEND", Data()))
        XCTAssertEqual(output, expected)
        XCTAssertEqual(dropped, ["tEXt", "iTXt", "eXIf", "iDOT", "trailing data"])
    }

    func testRejectsTruncatedOrMalformedFiles() {
        var truncated = PNGStripper.signature
        truncated.append(chunk("IHDR", Data(repeating: 1, count: 13)).prefix(10))
        XCTAssertThrowsError(try PNGStripper.strip(truncated))

        var hugeLength = PNGStripper.signature
        hugeLength.append(Data([0xFF, 0xFF, 0xFF, 0xFF]))
        hugeLength.append(Data("IHDR".utf8))
        XCTAssertThrowsError(try PNGStripper.strip(hugeLength))

        var noEnd = PNGStripper.signature
        noEnd.append(chunk("IHDR", Data(repeating: 1, count: 13)))
        XCTAssertThrowsError(try PNGStripper.strip(noEnd))

        XCTAssertThrowsError(try PNGStripper.strip(Data("not a png".utf8)))
    }
}
