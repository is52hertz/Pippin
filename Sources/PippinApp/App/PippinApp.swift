import SwiftUI

@main
struct PippinApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    var body: some Scene {
        MenuBarExtra {
            PippinMenuView(model: delegate.model)
        } label: {
            Label(
                delegate.model.menuBarPresentation.accessibilityLabel,
                systemImage: delegate.model.menuBarPresentation.symbolName
            )
            .labelStyle(.iconOnly)
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
