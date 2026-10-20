import Foundation
import UniformTypeIdentifiers

/// Temporary copies of images dragged in from other apps (for example a
/// picture dragged out of Safari), which arrive as data rather than as a file.
///
/// Copies live in the app's own sandboxed temporary folder and are deleted
/// when removed from the list, when the app quits, and at the next launch in
/// case the app didn't quit normally.
enum DroppedFiles {
    static var folder: URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("Dropped", isDirectory: true)
    }

    static func isCopy(_ url: URL) -> Bool {
        url.standardizedFileURL.path.hasPrefix(folder.standardizedFileURL.path + "/")
    }

    /// Copies a file handed over by drag and drop. Must be called before the
    /// drop handler returns, because the system deletes its file afterwards.
    static func keep(_ source: URL, suggestedName: String?, type: UTType) throws -> URL {
        let directory = folder.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        var name = sanitised(suggestedName ?? source.deletingPathExtension().lastPathComponent)
        if name.isEmpty { name = "Dragged image" }
        let ext = type.preferredFilenameExtension ?? source.pathExtension
        let destination = directory.appendingPathComponent(name).appendingPathExtension(ext)
        try FileManager.default.copyItem(at: source, to: destination)
        return destination
    }

    static func delete(_ url: URL) {
        guard isCopy(url) else { return }
        try? FileManager.default.removeItem(at: url.deletingLastPathComponent())
    }

    static func deleteAll() {
        try? FileManager.default.removeItem(at: folder)
    }

    /// Keeps a suggested name to plain characters so it can't form a path.
    private static func sanitised(_ name: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: " -_.()"))
        let cleaned = String(name.unicodeScalars.map { allowed.contains($0) ? Character($0) : "-" })
        return String(cleaned.trimmingCharacters(in: CharacterSet(charactersIn: ". ")).prefix(100))
    }
}
