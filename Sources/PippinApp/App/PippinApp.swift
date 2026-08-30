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

        Window("Pippin Settings", id: PippinWindow.settingsID) {
            PippinSettingsView(model: delegate.model)
        }
        .defaultSize(width: 720, height: 500)
        .defaultLaunchBehavior(.suppressed)
        .windowResizability(.contentMinSize)
    }
}
