import AppKit
import Foundation
import Observation
import PlainfileCore
import UniformTypeIdentifiers

struct InspectedFile: Identifiable {
    enum Status {
        case scanning
        case scanned
        case failed(String)
    }

    let id = UUID()
    let url: URL
    /// A temporary copy of an image dragged in from another app.
    let isDroppedCopy: Bool
    var status: Status = .scanning
    var fields: [MetadataField] = []
    var notes: [String] = []

    var name: String { url.lastPathComponent }

    var groups: [(group: MetadataGroup, fields: [MetadataField])] {
        Dictionary(grouping: fields, by: \.group)
            .sorted { $0.key < $1.key }
            .map { (group: $0.key, fields: $0.value) }
    }

    var highestRisk: Risk? { fields.map(\.risk).max() }
}

/// In-memory only. Nothing about scanned files is ever written to disk.
@MainActor
@Observable
final class SessionModel {
    var files: [InspectedFile] = []
    var selection: InspectedFile.ID?
    var isImporting = false

    private let parser = ParserClient()

    init() {
        // Copies left behind if the app didn't quit normally.
        DroppedFiles.deleteAll()
    }

    func add(_ urls: [URL]) {
        for url in urls where !files.contains(where: { $0.url == url }) {
            let file = InspectedFile(url: url, isDroppedCopy: DroppedFiles.isCopy(url))
            files.append(file)
            selection = selection ?? file.id
            Task { await self.scan(file.id) }
        }
    }

    func remove(_ id: InspectedFile.ID) {
        if let file = files.first(where: { $0.id == id }), file.isDroppedCopy {
            DroppedFiles.delete(file.url)
        }
        files.removeAll { $0.id == id }
        if selection == id { selection = files.first?.id }
    }

    /// Accepts files from Finder and pictures dragged from other apps, such as
    /// a browser, which hand over image data instead of a file.
    func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        var accepted = false
        for provider in providers {
            if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
                accepted = true
                _ = provider.loadObject(ofClass: URL.self) { url, _ in
                    guard let url, url.isFileURL else { return }
                    Task { @MainActor in self.add([url]) }
                }
            } else if let type = provider.registeredContentTypes.first(where: { $0.conforms(to: .image) }) {
                accepted = true
                let suggestedName = provider.suggestedName
                _ = provider.loadFileRepresentation(for: type, openInPlace: false) { url, _, _ in
                    guard let url,
                        let copy = try? DroppedFiles.keep(url, suggestedName: suggestedName, type: type)
                    else { return }
                    Task { @MainActor in self.add([copy]) }
                }
            }
        }
        return accepted
    }

    private func scan(_ id: InspectedFile.ID) async {
        guard let file = files.first(where: { $0.id == id }) else { return }
        let url = file.url
        let accessing = url.startAccessingSecurityScopedResource()
        defer { if accessing { url.stopAccessingSecurityScopedResource() } }

        var fields: [MetadataField] = []
        var notes: [String] = []
        var status = InspectedFile.Status.scanned

        if file.isDroppedCopy {
            notes.append(
                "This is a temporary copy of an image dragged in from another app. File details such as where it was downloaded from belong to the original and aren't available. The copy is deleted when you remove it or quit."
            )
        } else {
            fields = FilesystemScanner.scan(url)
        }

        let named = (try? url.resourceValues(forKeys: [.contentTypeKey]))?.contentType
        let namedAsImage = named?.conforms(to: .image) ?? false
        let contents = (try? ContentSniffer.kind(ofFileAt: url)) ?? .unknown

        if contents.isImage {
            if !namedAsImage || !(named.map { matches($0, contents) } ?? false) {
                notes.append("Despite its name, this file contains \(contents.description).")
            }
            do {
                let size = (try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0
                guard size <= ImageScanner.maxBytes else {
                    throw ScanError.tooLarge(limit: ImageScanner.maxBytes)
                }
                let data = try Data(contentsOf: url, options: .mappedIfSafe)
                let report = try await parser.scanImage(data)
                fields += report.fields
                notes += report.notes
            } catch {
                let reason = (error as? ScanError)?.description ?? error.localizedDescription
                status = .failed("\(reason) File details are still shown below.")
            }
        } else if namedAsImage {
            status = .failed(
                "This file is named like an image, but it contains \(contents.description), so there's no picture to read. File details are still shown below."
            )
        } else {
            notes.append(
                "Only file details are shown for this type of file. Reading its contents is coming in a later version."
            )
        }

        guard let index = files.firstIndex(where: { $0.id == id }) else { return }
        files[index].fields = fields
        files[index].notes = notes
        files[index].status = status
    }

    /// Whether a file's name-based type agrees with what it contains.
    private func matches(_ named: UTType, _ contents: ContentKind) -> Bool {
        switch contents {
        case .jpeg: named.conforms(to: .jpeg)
        case .png: named.conforms(to: .png)
        case .gif: named.conforms(to: .gif)
        case .webp: named.conforms(to: .webP)
        case .heif: named.conforms(to: .heic) || named.conforms(to: .heif)
        case .tiff: named.conforms(to: .tiff)
        case .bmp: named.conforms(to: .bmp)
        case .avif: named.preferredFilenameExtension == "avif"
        default: true
        }
    }
}
