import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers
import XCTest

/// Small test images carrying planted (fake) location, camera and author data.
enum TestImages {
    static let author = "Planted Author"
    static let make = "PlantedCam"

    static func planted(_ type: UTType, imageCount: Int = 1, side: Int = 16) throws -> Data {
        let context = try XCTUnwrap(
            CGContext(
                data: nil, width: side, height: side, bitsPerComponent: 8, bytesPerRow: 0,
                space: CGColorSpace(name: CGColorSpace.sRGB)!,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        // A simple gradient, so a changed pixel would be noticed.
        for y in 0..<side {
            for x in 0..<side {
                context.setFillColor(
                    CGColor(
                        red: CGFloat(x) / CGFloat(side), green: CGFloat(y) / CGFloat(side),
                        blue: 0.5, alpha: 1))
                context.fill(CGRect(x: x, y: y, width: 1, height: 1))
            }
        }
        let image = try XCTUnwrap(context.makeImage())

        let output = NSMutableData()
        let destination = try XCTUnwrap(
            CGImageDestinationCreateWithData(output, type.identifier as CFString, imageCount, nil))
        let properties: [String: Any] = [
            kCGImagePropertyGPSDictionary as String: [
                kCGImagePropertyGPSLatitude as String: 26.6181,
                kCGImagePropertyGPSLatitudeRef as String: "S",
                kCGImagePropertyGPSLongitude as String: 153.0868,
                kCGImagePropertyGPSLongitudeRef as String: "E",
            ] as [String: Any],
            kCGImagePropertyTIFFDictionary as String: [
                kCGImagePropertyTIFFMake as String: make,
                kCGImagePropertyTIFFModel as String: "Model Z",
                kCGImagePropertyTIFFArtist as String: author,
            ] as [String: Any],
            kCGImagePropertyOrientation as String: 1,
        ]
        for _ in 0..<imageCount {
            CGImageDestinationAddImage(destination, image, properties as CFDictionary)
        }
        guard CGImageDestinationFinalize(destination) else {
            throw CocoaError(.fileWriteUnknown)
        }
        return output as Data
    }
}
