import SwiftUI
import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationWillTerminate(_ notification: Notification) {
        // Temporary copies of dragged-in images never outlive the session.
        DroppedFiles.deleteAll()
    }
}

@main
struct PlainfileApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
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
