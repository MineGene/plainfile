import SwiftUI

@main
struct PlainfileApp: App {
    @State private var model = SessionModel()

    var body: some Scene {
        Window("Plainfile", id: "main") {
            ContentView()
                .environment(model)
                .frame(minWidth: 760, minHeight: 460)
        }
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("Open…") { model.isImporting = true }
                    .keyboardShortcut("o")
            }
        }
    }
}
