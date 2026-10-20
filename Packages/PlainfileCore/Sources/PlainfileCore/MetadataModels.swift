import Foundation

/// Plain-language groups shown in the metadata list, ordered by how much they reveal.
public enum MetadataGroup: String, Codable, Sendable, CaseIterable, Comparable {
    case location
    case people
    case device
    case downloadedFrom
    case dates
    case editHistory
    case other

    public var title: String {
        switch self {
        case .location: "Location"
        case .people: "People and authorship"
        case .device: "Device"
        case .downloadedFrom: "Downloaded from"
        case .dates: "Dates"
        case .editHistory: "Edit history"
        case .other: "Other"
        }
    }

    public static func < (lhs: MetadataGroup, rhs: MetadataGroup) -> Bool {
        allCases.firstIndex(of: lhs)! < allCases.firstIndex(of: rhs)!
    }
}

public enum Risk: Int, Codable, Sendable, Comparable {
    case low, medium, high, critical

    public var title: String {
        switch self {
        case .low: "Low"
        case .medium: "Medium"
        case .high: "High"
        case .critical: "Critical"
        }
    }

    public static func < (lhs: Risk, rhs: Risk) -> Bool { lhs.rawValue < rhs.rawValue }
}

/// One piece of metadata found in a file.
public struct MetadataField: Codable, Sendable, Identifiable, Hashable {
    /// Stable key, e.g. "{GPS}.Latitude" or "xattr.com.apple.metadata:kMDItemWhereFroms".
    public var id: String
    public var group: MetadataGroup
    public var name: String
    public var value: String
    /// Where it was found, e.g. "EXIF", "GPS", "XMP", "File attributes".
    public var source: String
    public var risk: Risk
    /// Whether removing it is offered by default. Orientation, colour profiles,
    /// Content Credentials and the quarantine flag are kept by default.
    public var removeByDefault: Bool
    /// True when `value` is the stored text itself (not a description such as
    /// "12 bytes"), so verification can search the cleaned file for it.
    public var literal: Bool

    public init(
        id: String, group: MetadataGroup, name: String, value: String,
        source: String, risk: Risk, removeByDefault: Bool = true, literal: Bool = true
    ) {
        self.id = id
        self.group = group
        self.name = name
        self.value = value
        self.source = source
        self.risk = risk
        self.removeByDefault = removeByDefault
        self.literal = literal
    }
}

public struct ScanReport: Codable, Sendable {
    public var typeIdentifier: String?
    public var imageCount: Int
    public var fields: [MetadataField]
    public var notes: [String]

    public init(typeIdentifier: String?, imageCount: Int, fields: [MetadataField], notes: [String]) {
        self.typeIdentifier = typeIdentifier
        self.imageCount = imageCount
        self.fields = fields
        self.notes = notes
    }
}

public enum ScanError: Error, Sendable, Equatable, CustomStringConvertible {
    case tooLarge(limit: Int)
    case unreadable
    case notAnImage

    public var description: String {
        switch self {
        case .tooLarge(let limit):
            "This file is larger than \(limit / 1_048_576) MB, the current limit for scanning."
        case .unreadable: "This file could not be read."
        case .notAnImage: "This file is not an image macOS can read."
        }
    }
}

enum ValueFormatter {
    static let maxLength = 200

    static func string(_ value: Any) -> String {
        let text: String
        switch value {
        case let string as String: text = string
        case let number as NSNumber: text = number.stringValue
        case let data as Data: text = "\(data.count) bytes of data"
        case let date as Date: text = date.formatted(date: .abbreviated, time: .standard)
        case let array as [Any]: text = array.map { string($0) }.joined(separator: ", ")
        case let dict as [String: Any]: text = "\(dict.count) vendor entries"
        default: text = String(describing: value)
        }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.count > maxLength ? String(trimmed.prefix(maxLength)) + "…" : trimmed
    }
}
