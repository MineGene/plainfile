import Darwin
import Foundation

/// Reads metadata macOS attaches to a file from outside its contents:
/// extended attributes (download source, quarantine, Finder tags), dates and name.
///
/// Runs in the main app, which holds the user's permission to the file.
public enum FilesystemScanner {
    public static let whereFroms = "com.apple.metadata:kMDItemWhereFroms"
    public static let quarantine = "com.apple.quarantine"
    public static let userTags = "com.apple.metadata:_kMDItemUserTags"
    public static let finderInfo = "com.apple.FinderInfo"
    public static let finderComment = "com.apple.metadata:kMDItemFinderComment"

    public static func scan(_ url: URL) -> [MetadataField] {
        var fields: [MetadataField] = []

        fields.append(
            MetadataField(
                id: "fs.name", group: .other, name: "File name", value: url.lastPathComponent,
                source: "File system", risk: .medium, removeByDefault: false))

        let keys: Set<URLResourceKey> = [.creationDateKey, .contentModificationDateKey]
        if let values = try? url.resourceValues(forKeys: keys) {
            if let created = values.creationDate {
                fields.append(
                    MetadataField(
                        id: "fs.created", group: .dates, name: "Created",
                        value: ValueFormatter.string(created), source: "File system",
                        risk: .low, removeByDefault: false))
            }
            if let modified = values.contentModificationDate {
                fields.append(
                    MetadataField(
                        id: "fs.modified", group: .dates, name: "Modified",
                        value: ValueFormatter.string(modified), source: "File system",
                        risk: .low, removeByDefault: false))
            }
        }

        for name in attributeNames(url) {
            fields.append(field(forAttribute: name, data: attribute(name, of: url)))
        }
        return fields
    }

    static func field(forAttribute name: String, data: Data?) -> MetadataField {
        let id = "xattr.\(name)"
        let source = "File attributes"
        switch name {
        case whereFroms:
            let urls = decodedStrings(data)
            return MetadataField(
                id: id, group: .downloadedFrom, name: "Download source",
                value: urls.isEmpty ? "Unreadable" : urls.joined(separator: "\n"),
                source: source, risk: .high)
        case quarantine:
            let parts = data.flatMap { String(data: $0, encoding: .utf8) }?
                .split(separator: ";", omittingEmptySubsequences: false) ?? []
            let app = parts.count > 2 && !parts[2].isEmpty ? String(parts[2]) : "unknown app"
            return MetadataField(
                id: id, group: .downloadedFrom, name: "Downloaded with (Gatekeeper flag)",
                value: app, source: source, risk: .medium, removeByDefault: false)
        case userTags:
            let tags = decodedStrings(data).map { $0.split(separator: "\n").first.map(String.init) ?? $0 }
            return MetadataField(
                id: id, group: .people, name: "Finder tags", value: tags.joined(separator: ", "),
                source: source, risk: .medium)
        case finderComment:
            return MetadataField(
                id: id, group: .people, name: "Finder comment",
                value: decodedStrings(data).joined(separator: " "), source: source, risk: .medium)
        case finderInfo:
            return MetadataField(
                id: id, group: .other, name: "Finder info", value: "\(data?.count ?? 0) bytes",
                source: source, risk: .low)
        default:
            return MetadataField(
                id: id, group: .other, name: name, value: "\(data?.count ?? 0) bytes",
                source: source, risk: .low)
        }
    }

    /// Decodes a property-list attribute holding a string or an array of strings.
    static func decodedStrings(_ data: Data?) -> [String] {
        guard let data,
            let object = try? PropertyListSerialization.propertyList(from: data, format: nil)
        else { return [] }
        if let array = object as? [String] { return array.filter { !$0.isEmpty } }
        if let string = object as? String { return [string] }
        return []
    }

    // MARK: - xattr syscalls

    public static func attributeNames(_ url: URL) -> [String] {
        url.withUnsafeFileSystemRepresentation { path -> [String] in
            guard let path else { return [] }
            let size = listxattr(path, nil, 0, XATTR_NOFOLLOW)
            guard size > 0 else { return [] }
            var buffer = [CChar](repeating: 0, count: size)
            let read = listxattr(path, &buffer, size, XATTR_NOFOLLOW)
            guard read > 0 else { return [] }
            return buffer[0..<read].split(separator: 0).map {
                String(decoding: $0.map { UInt8(bitPattern: $0) }, as: UTF8.self)
            }
        }
    }

    public static func attribute(_ name: String, of url: URL) -> Data? {
        url.withUnsafeFileSystemRepresentation { path -> Data? in
            guard let path else { return nil }
            let size = getxattr(path, name, nil, 0, 0, XATTR_NOFOLLOW)
            guard size >= 0 else { return nil }
            var data = Data(count: size)
            let read = data.withUnsafeMutableBytes {
                getxattr(path, name, $0.baseAddress, size, 0, XATTR_NOFOLLOW)
            }
            return read >= 0 ? data.prefix(read) : nil
        }
    }
}
