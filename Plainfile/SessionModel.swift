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

    func add(_ urls: [URL]) {
        for url in urls where !files.contains(where: { $0.url == url }) {
            let file = InspectedFile(url: url)
            files.append(file)
            selection = selection ?? file.id
            Task { await self.scan(file.id) }
        }
    }

    func remove(_ id: InspectedFile.ID) {
        files.removeAll { $0.id == id }
        if selection == id { selection = files.first?.id }
    }

    private func scan(_ id: InspectedFile.ID) async {
        guard let url = files.first(where: { $0.id == id })?.url else { return }
        let accessing = url.startAccessingSecurityScopedResource()
        defer { if accessing { url.stopAccessingSecurityScopedResource() } }

        var fields = FilesystemScanner.scan(url)
        var notes: [String] = []
        var status = InspectedFile.Status.scanned

        let type = (try? url.resourceValues(forKeys: [.contentTypeKey]))?.contentType
        if let type, type.conforms(to: .image) {
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
                status = .failed(
                    (error as? ScanError)?.description ?? error.localizedDescription)
            }
        } else {
            notes.append(
                "Only file attributes are shown for this type of file. Reading its contents is coming in a later version."
            )
        }

        guard let index = files.firstIndex(where: { $0.id == id }) else { return }
        files[index].fields = fields
        files[index].notes = notes
        files[index].status = status
    }
}
