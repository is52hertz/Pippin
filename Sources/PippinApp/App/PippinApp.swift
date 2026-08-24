import SwiftUI

@main
struct PippinApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    var body: some Scene {
        MenuBarExtra("Pippin", systemImage: "apple.logo") {
            PippinMenuView(model: delegate.model)
        }
        .menuBarExtraStyle(.window)
        .commands {
            CommandGroup(replacing: .appSettings) {
                PippinSettingsButton()
                    .keyboardShortcut(",", modifiers: .command)
            }
        }

        Settings {
            PippinSettingsView(model: delegate.model)
        }
    }
}
