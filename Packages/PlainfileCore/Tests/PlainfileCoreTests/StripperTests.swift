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
