import PlainfileCore
import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @Environment(SessionModel.self) private var model

    var body: some View {
        @Bindable var model = model
        NavigationSplitView {
            FileList()
                .navigationSplitViewColumnWidth(min: 200, ideal: 240)
        } detail: {
            if let id = model.selection, let file = model.files.first(where: { $0.id == id }) {
                MetadataList(file: file)
            } else {
                ContentUnavailableView {
                    Label("Drop Files to See Their Hidden Information", systemImage: "doc.viewfinder")
                } description: {
                    Text("Nothing is changed. This preview version only shows metadata.")
                } actions: {
                    Button("Open…") { model.isImporting = true }
                }
            }
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Add Files", systemImage: "plus") { model.isImporting = true }
            }
        }
        // Files from Finder, and pictures dragged from other apps such as a
        // browser, which arrive as image data rather than as a file.
        .onDrop(of: [.fileURL, .image], isTargeted: nil) { providers in
            model.handleDrop(providers)
        }
        .fileImporter(
            isPresented: $model.isImporting, allowedContentTypes: [.item],
            allowsMultipleSelection: true
        ) { result in
            if case .success(let urls) = result { model.add(urls) }
        }
    }
}

private struct FileList: View {
    @Environment(SessionModel.self) private var model

    var body: some View {
        @Bindable var model = model
        List(selection: $model.selection) {
            ForEach(model.files) { file in
                Label {
                    Text(file.name).lineLimit(1).truncationMode(.middle)
                } icon: {
                    StatusIcon(file: file)
                }
                .tag(file.id)
                .contextMenu {
                    Button("Remove from List") { model.remove(file.id) }
                }
            }
        }
        .navigationTitle("Files")
    }
}

private struct StatusIcon: View {
    let file: InspectedFile

    var body: some View {
        switch file.status {
        case .scanning:
            ProgressView().controlSize(.small)
        case .failed:
            Image(systemName: "exclamationmark.triangle")
                .foregroundStyle(.yellow)
                .accessibilityLabel("Needs attention")
        case .scanned:
            if let risk = file.highestRisk, risk >= .high {
                Image(systemName: "eye.trianglebadge.exclamationmark")
                    .foregroundStyle(.orange)
                    .accessibilityLabel("Has identifying metadata")
            } else {
                Image(systemName: "doc")
                    .accessibilityLabel("Scanned")
            }
        }
    }
}

private struct MetadataList: View {
    let file: InspectedFile

    var body: some View {
        List {
            if case .failed(let message) = file.status {
                Section {
                    Label(message, systemImage: "exclamationmark.triangle")
                }
            }
            ForEach(file.groups, id: \.group) { entry in
                Section(entry.group.title) {
                    ForEach(entry.fields) { field in
                        MetadataRow(field: field)
                    }
                }
            }
            if !file.notes.isEmpty {
                Section("Notes") {
                    ForEach(file.notes, id: \.self) { note in
                        Label(note, systemImage: "info.circle")
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .navigationTitle(file.name)
        .navigationSubtitle(subtitle)
        .overlay {
            if case .scanning = file.status { ProgressView("Reading…") }
        }
    }

    private var subtitle: String {
        let count = file.fields.count
        return count == 1 ? "1 item found" : "\(count) items found"
    }
}

private struct MetadataRow: View {
    let field: MetadataField

    var body: some View {
        LabeledContent {
            Text(field.value)
                .textSelection(.enabled)
                .multilineTextAlignment(.trailing)
        } label: {
            VStack(alignment: .leading, spacing: 2) {
                Text(field.name)
                HStack(spacing: 6) {
                    RiskLabel(risk: field.risk)
                    Text(field.source)
                    if !field.removeByDefault { Text("· Kept by default") }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
    }
}

private struct RiskLabel: View {
    let risk: Risk

    var body: some View {
        Label(risk.title, systemImage: symbol)
            .labelStyle(.titleAndIcon)
            .foregroundStyle(color)
    }

    private var symbol: String {
        switch risk {
        case .critical: "exclamationmark.octagon.fill"
        case .high: "exclamationmark.triangle.fill"
        case .medium: "circle.fill"
        case .low: "circle"
        }
    }

    private var color: Color {
        switch risk {
        case .critical: .red
        case .high: .orange
        case .medium: .secondary
        case .low: .secondary
        }
    }
}
