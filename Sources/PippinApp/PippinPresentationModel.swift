import Observation
import PippinCore
import PippinServer

enum PresentedPermission: Sendable {
    case reminders
    case mailAutomation
    case mailData
}

struct PermissionActionPresentation: Equatable, Sendable {
    let action: PermissionAction
    let title: String
}

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
    private(set) var permissionActionInProgress: PermissionAction?
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

    func permissionAction(
        for permission: PresentedPermission
    ) -> PermissionActionPresentation? {
        switch permission {
        case .reminders:
            switch permissions.reminders {
            case .notDetermined:
                PermissionActionPresentation(
                    action: .requestRemindersAccess,
                    title: "Request Access…"
                )
            case .denied, .restricted, .writeOnly:
                PermissionActionPresentation(
                    action: .openRemindersSettings,
                    title: "Open Reminders…"
                )
            case .granted, .unavailable, .unknown:
                nil
            }
        case .mailAutomation:
            switch permissions.mailAutomation {
            case .unavailable:
                PermissionActionPresentation(action: .openMail, title: "Open Mail…")
            case .notDetermined:
                PermissionActionPresentation(
                    action: .requestMailAutomationAccess,
                    title: "Request Access…"
                )
            case .denied, .restricted:
                PermissionActionPresentation(
                    action: .openAutomationSettings,
                    title: "Open Automation…"
                )
            case .writeOnly, .granted, .unknown:
                nil
            }
        case .mailData:
            PermissionActionPresentation(
                action: .openFullDiskAccessSettings,
                title: "Open Full Disk Access…"
            )
        }
    }

    func performPermissionAction(_ action: PermissionAction) async {
        guard permissionActionInProgress == nil else { return }
        permissionActionInProgress = action
        defer { permissionActionInProgress = nil }

        do {
            apply(try await runtime.performPermissionAction(action))
            errorMessage = nil
        } catch is CancellationError {
            apply(await runtime.snapshot())
        } catch {
            // Always refresh through the read-only path. A request result is not
            // itself proof of the current permission state.
            apply(await runtime.snapshot())
            errorMessage = Self.userFacingDescription(for: error)
        }
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
