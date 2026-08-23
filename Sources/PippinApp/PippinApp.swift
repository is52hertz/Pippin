import AppKit
import Logging
import PippinCore
import SwiftUI

@main
struct PippinApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    var body: some Scene {
        MenuBarExtra("Pippin", systemImage: "apple.logo") {
            PippinMenuView(model: delegate.model)
        }
        .menuBarExtraStyle(.window)

        Settings {
            PippinSettingsView(model: delegate.model)
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let model: PippinPresentationModel

    private let logger = Logger(label: "pippin.app")
    private let runtime: ServerRuntime

    override init() {
        let runtime = ServerRuntime()
        self.runtime = runtime
        self.model = PippinPresentationModel(runtime: runtime)
        super.init()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        Task {
            await model.start()
            if model.state == .failed {
                logger.error("Startup failed: \(model.errorMessage ?? "unknown error")")
            }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        // Remove discovery immediately; process teardown closes the listener.
        Endpoint.remove()
    }
}
