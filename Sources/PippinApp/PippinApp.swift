import PippinServer
import SwiftUI

/// Menu-bar host process. Owns server lifetime.
///
/// The real status UI, permission rows, and module toggles belong to step 8; this
/// is the minimum launchable bundle that step 2's packaging can build and sign.
@main
struct PippinApp: App {
    var body: some Scene {
        MenuBarExtra("Pippin", systemImage: "apple.logo") {
            Button("Quit Pippin") { NSApplication.shared.terminate(nil) }
                .keyboardShortcut("q")
        }
    }
}
