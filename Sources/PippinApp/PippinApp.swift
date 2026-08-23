import AppKit
import Logging
import PippinCore
import PippinServer
import SwiftUI

/// Menu-bar host process. Owns server lifetime.
///
/// The real status UI, permission rows, and module toggles belong to step 8; this
/// is the minimum that runs the resident server and publishes its endpoint.
@main
struct PippinApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    var body: some Scene {
        MenuBarExtra("Pippin", systemImage: "apple.logo") {
            Text(delegate.statusLine)
            Divider()
            Button("Quit Pippin") { NSApplication.shared.terminate(nil) }
                .keyboardShortcut("q")
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, ObservableObject {
    @Published private(set) var statusLine = "Starting…"

    private let logger = Logger(label: "pippin.app")
    private var runtime: ServerRuntime?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let runtime = ServerRuntime()
        self.runtime = runtime
        Task {
            do {
                let port = try await runtime.start()
                statusLine = "Listening on 127.0.0.1:\(port)"
            } catch let error as PippinError {
                // Logged as well as shown: a startup failure that only appears in
                // a menu the user may never open is a failure that looks like a
                // hang.
                logger.error("Startup failed: \(error.description)")
                statusLine = "Not running — \(error.hint)"
            } catch {
                logger.error("Startup failed: \(error)")
                statusLine = "Not running — \(error.localizedDescription)"
            }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        // Removing the endpoint file is what tells the shim we are gone; leaving a
        // stale one behind would make every shim invocation hang on a dead port.
        Endpoint.remove()
    }
}

/// Owns the process's server objects for its lifetime.
actor ServerRuntime {
    private var host: ServerHost?
    private var listener: HTTPListener?

    func start() async throws -> Int {
        let config = try Config.load()
        let token = Token.generate()

        let host = ServerHost(
            config: config,
            tokenStore: .local(token: token),
            registry: ProductionToolCatalogue.registry
        )
        self.host = host

        let listener = HTTPListener(
            host: config.http.bind,
            port: config.http.port,
            serverHost: host
        )
        self.listener = listener

        let port = try await listener.start()
        await host.startSweeping()

        // Published only after the listener is up, so the file never advertises a
        // port that is not yet accepting connections.
        try Endpoint(port: port, host: config.http.bind, token: token).write()
        return port
    }

    func stop() async {
        await listener?.stop()
        await host?.shutdown()
        Endpoint.remove()
    }
}
