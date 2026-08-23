import Observation
import PippinCore
import PippinServer

/// One presentation mirror shared by the menu-bar and Settings scenes.
/// The resident actors remain authoritative for server and permission state.
@MainActor
@Observable
final class PippinPresentationModel {
    private let runtime: any ServerRuntimeServing

    private(set) var state: AppRuntimeState = .starting
    private(set) var host = "127.0.0.1"
    private(set) var port = 0
    private(set) var sessionCount = 0
    private(set) var config = Config()
    private(set) var permissions = PermissionSnapshot(
        reminders: .unknown,
        mailAutomation: .unavailable,
        fullDiskAccess: .unknown
    )
    private(set) var isApplyingConfig = false
    private(set) var errorMessage: String?

    init(runtime: any ServerRuntimeServing) {
        self.runtime = runtime
    }

    func start() async {
        do {
            apply(try await runtime.start())
            errorMessage = nil
        } catch is CancellationError {
            return
        } catch {
            apply(await runtime.snapshot())
            errorMessage = Self.userFacingDescription(for: error)
        }
    }

    func refresh() async {
        apply(await runtime.snapshot())
    }

    func setModuleEnabled(_ enabled: Bool, module: String) async {
        var candidate = config
        guard candidate.modules[module] != nil else { return }
        candidate.modules[module]?.enabled = enabled
        await applyConfig(candidate)
    }

    func setModuleWrites(_ writes: Bool, module: String) async {
        var candidate = config
        guard candidate.modules[module] != nil else { return }
        candidate.modules[module]?.writes = writes
        await applyConfig(candidate)
    }

    private func applyConfig(_ candidate: Config) async {
        guard candidate != config, !isApplyingConfig else { return }
        isApplyingConfig = true
        defer { isApplyingConfig = false }

        do {
            // Do not mutate `config` before both persistence and host update
            // succeed inside the runtime.
            apply(try await runtime.updateConfig(candidate))
            errorMessage = nil
        } catch is CancellationError {
            return
        } catch {
            errorMessage = Self.userFacingDescription(for: error)
        }
    }

    private func apply(_ snapshot: AppRuntimeSnapshot) {
        state = snapshot.state
        if let server = snapshot.server {
            host = server.host
            port = server.port
            sessionCount = server.sessionCount
            config = server.config
            permissions = server.permissions
        }
        if snapshot.state == .failed, let detail = snapshot.detail {
            errorMessage = detail
        }
    }

    private static func userFacingDescription(for error: any Error) -> String {
        if let error = error as? PippinError {
            return error.hint
        }
        return error.localizedDescription
    }
}
