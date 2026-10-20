import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers
import XCTest

@testable import PlainfileCore

final class ImageScannerTests: XCTestCase {
    /// Makes a small JPEG carrying planted GPS, camera and author values.
    private func plantedJPEG() throws -> Data {
        let context = try XCTUnwrap(
            CGContext(
                data: nil, width: 8, height: 8, bitsPerComponent: 8, bytesPerRow: 0,
                space: CGColorSpace(name: CGColorSpace.sRGB)!,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.setFillColor(CGColor(red: 0.2, green: 0.4, blue: 0.6, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 8, height: 8))
        let image = try XCTUnwrap(context.makeImage())

        let output = NSMutableData()
        let destination = try XCTUnwrap(
            CGImageDestinationCreateWithData(output, UTType.jpeg.identifier as CFString, 1, nil))
        let properties: [String: Any] = [
            kCGImagePropertyGPSDictionary as String: [
                kCGImagePropertyGPSLatitude as String: 26.6181,
                kCGImagePropertyGPSLatitudeRef as String: "S",
                kCGImagePropertyGPSLongitude as String: 153.0868,
                kCGImagePropertyGPSLongitudeRef as String: "E",
            ] as [String: Any],
            kCGImagePropertyTIFFDictionary as String: [
                kCGImagePropertyTIFFMake as String: "PlantedCam",
                kCGImagePropertyTIFFModel as String: "Model Z",
                kCGImagePropertyTIFFArtist as String: "Planted Author",
            ] as [String: Any],
            kCGImagePropertyOrientation as String: 1,
        ]
        CGImageDestinationAddImage(destination, image, properties as CFDictionary)
        XCTAssertTrue(CGImageDestinationFinalize(destination))
        return output as Data
    }

    func testFindsPlantedLocationDeviceAndAuthor() throws {
        let report = try ImageScanner.scan(data: plantedJPEG())

        XCTAssertEqual(report.typeIdentifier, UTType.jpeg.identifier)
        XCTAssertEqual(report.imageCount, 1)

        let location = report.fields.filter { $0.group == .location }
        XCTAssertFalse(location.isEmpty, "GPS should be reported")
        XCTAssertTrue(location.allSatisfy { $0.risk == .critical && $0.removeByDefault })

        let make = try XCTUnwrap(report.fields.first { $0.value == "PlantedCam" })
        XCTAssertEqual(make.group, .device)

        let artist = try XCTUnwrap(report.fields.first { $0.value == "Planted Author" })
        XCTAssertEqual(artist.group, .people)
    }

    func testOrientationIsKeptByDefault() throws {
        let report = try ImageScanner.scan(data: plantedJPEG())
        let orientation = report.fields.filter { $0.name.hasSuffix("Orientation") }
        XCTAssertFalse(orientation.isEmpty)
        XCTAssertTrue(orientation.allSatisfy { !$0.removeByDefault })
    }

    func testRejectsNonImageData() {
        XCTAssertThrowsError(try ImageScanner.scan(data: Data("not an image".utf8)))
    }

    func testRejectsOversizedInputWithoutParsing() {
        let tooBig = Data(count: ImageScanner.maxBytes + 1)
        XCTAssertThrowsError(try ImageScanner.scan(data: tooBig)) { error in
            XCTAssertEqual(error as? ScanError, .tooLarge(limit: ImageScanner.maxBytes))
        }
    }
}

final class FilesystemScannerTests: XCTestCase {
    private var fileURL: URL!

    override func setUpWithError() throws {
        fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("plainfile-test-\(UUID().uuidString).txt")
        try Data("hello".utf8).write(to: fileURL)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: fileURL)
    }

    private func set(_ name: String, _ data: Data) throws {
        let result = fileURL.withUnsafeFileSystemRepresentation { path in
            data.withUnsafeBytes { setxattr(path!, name, $0.baseAddress, data.count, 0, 0) }
        }
        XCTAssertEqual(result, 0, "setxattr failed for \(name)")
    }

    func testReportsDownloadSourceFromWhereFroms() throws {
        let plist = try PropertyListSerialization.data(
            fromPropertyList: ["https://example.com/file.zip", "https://example.com/"],
            format: .binary, options: 0)
        try set(FilesystemScanner.whereFroms, plist)

        let fields = FilesystemScanner.scan(fileURL)
        let source = try XCTUnwrap(fields.first { $0.id == "xattr.\(FilesystemScanner.whereFroms)" })
        XCTAssertEqual(source.group, .downloadedFrom)
        XCTAssertTrue(source.value.contains("https://example.com/file.zip"))
        XCTAssertTrue(source.removeByDefault)
    }

    func testQuarantineIsShownButKept() throws {
        try set(FilesystemScanner.quarantine, Data("0083;6710a3b2;Safari;".utf8))
        let fields = FilesystemScanner.scan(fileURL)
        let flag = try XCTUnwrap(fields.first { $0.id == "xattr.\(FilesystemScanner.quarantine)" })
        XCTAssertEqual(flag.value, "Safari")
        XCTAssertFalse(flag.removeByDefault)
    }

    func testOversizedAttributeIsNotRead() throws {
        let big = Data(repeating: 0x41, count: FilesystemScanner.maxAttributeBytes + 1)
        try set(FilesystemScanner.whereFroms, big)
        XCTAssertNil(FilesystemScanner.attribute(FilesystemScanner.whereFroms, of: fileURL))
        let fields = FilesystemScanner.scan(fileURL)
        let source = try XCTUnwrap(fields.first { $0.id == "xattr.\(FilesystemScanner.whereFroms)" })
        XCTAssertEqual(source.value, "Unreadable")
    }

    func testUnknownAttributeShowsSizeOnly() throws {
        try set("com.example.private", Data("secret value".utf8))
        let fields = FilesystemScanner.scan(fileURL)
        let field = try XCTUnwrap(fields.first { $0.id == "xattr.com.example.private" })
        XCTAssertEqual(field.value, "12 bytes")
    }

    func testAlwaysReportsFileName() {
        let fields = FilesystemScanner.scan(fileURL)
        XCTAssertEqual(fields.first { $0.id == "fs.name" }?.value, fileURL.lastPathComponent)
    }
}
