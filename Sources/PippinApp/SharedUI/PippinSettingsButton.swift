import AppKit
import SwiftUI

struct PippinSettingsButton: View {
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        Button("Settings…", action: open)
    }

    private func open() {
        NSApp.activate()
        openSettings()
    }
}
