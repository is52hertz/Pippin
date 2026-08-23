import AppKit
import PippinCore
import PippinServer
import SwiftUI

struct PippinMenuView: View {
    let model: PippinPresentationModel

    var body: some View {
        Form {
            ServerStatusSection(model: model)

            Section("Permissions") {
                PermissionStatusRow(
                    title: "Reminders",
                    state: model.permissions.reminders,
                    permission: .reminders,
                    model: model
                )
                PermissionStatusRow(
                    title: "Mail Automation",
                    state: model.permissions.mailAutomation,
                    permission: .mailAutomation,
                    model: model
                )
                PermissionStatusRow(
                    title: "Mail Data",
                    state: model.permissions.fullDiskAccess,
                    permission: .mailData,
                    model: model
                )
            }

            Section("Modules") {
                ForEach(model.config.modules.keys.sorted(), id: \.self) { module in
                    LabeledContent(Self.title(for: module)) {
                        Text(Self.moduleStatus(model.config.modules[module]))
                            .foregroundStyle(.secondary)
                    }
                }
            }

            if let error = model.errorMessage {
                Section("Error") {
                    Text(error)
                        .foregroundStyle(.red)
                        .textSelection(.enabled)
                }
            }

            Section {
                HStack {
                    PippinSettingsButton()
                    Button("Refresh", systemImage: "arrow.clockwise") {
                        Task { await model.refresh() }
                    }
                    Spacer()
                    Button("Quit Pippin") {
                        NSApplication.shared.terminate(nil)
                    }
                    .keyboardShortcut("q")
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 390, height: 440)
        .task { await model.refresh() }
    }

    static func title(for module: String) -> String {
        module.replacingOccurrences(of: "_", with: " ").capitalized
    }

    static func moduleStatus(_ module: Config.ModuleConfig?) -> String {
        guard let module, module.enabled else { return "Disabled" }
        return module.writes ? "Enabled · Writes on" : "Enabled · Read only"
    }
}

struct PippinSettingsView: View {
    @Bindable var model: PippinPresentationModel

    var body: some View {
        Form {
            Section("Modules") {
                ForEach(model.config.modules.keys.sorted(), id: \.self) { module in
                    ModuleSettingsRow(model: model, module: module)
                }
            }

            Section("Permissions") {
                PermissionSettingsRow(
                    title: "Reminders",
                    detail: "Pippin reports EventKit's current Reminders authorization.",
                    state: model.permissions.reminders,
                    permission: .reminders,
                    model: model
                )
                PermissionSettingsRow(
                    title: "Mail Automation",
                    detail: "Target-specific Apple Events access, checked only while Mail is running.",
                    state: model.permissions.mailAutomation,
                    permission: .mailAutomation,
                    model: model
                )
                PermissionSettingsRow(
                    title: "Mail Data",
                    detail: "Effective read access to ~/Library/Mail. Add Pippin manually in Full Disk Access; macOS provides no prompt.",
                    state: model.permissions.fullDiskAccess,
                    permission: .mailData,
                    model: model
                )
            }

            Section("Server") {
                ServerStatusRows(model: model)
            }

            if let error = model.errorMessage {
                Section("Action Needed") {
                    Text(error)
                        .foregroundStyle(.red)
                        .textSelection(.enabled)
                }
            }
        }
        .formStyle(.grouped)
        .frame(minWidth: 560, minHeight: 480)
        .toolbar {
            Button("Refresh", systemImage: "arrow.clockwise") {
                Task { await model.refresh() }
            }
        }
        .task { await model.refresh() }
    }
}

private struct ServerStatusSection: View {
    let model: PippinPresentationModel

    var body: some View {
        Section("Server") {
            ServerStatusRows(model: model)
        }
    }
}

private struct ServerStatusRows: View {
    let model: PippinPresentationModel

    var body: some View {
        LabeledContent("State", value: model.state.displayName)
        LabeledContent("Address", value: model.port == 0 ? "—" : "\(model.host):\(model.port)")
        LabeledContent("Sessions", value: model.sessionCount.formatted())
    }
}

private struct PermissionStatusRow: View {
    let title: String
    let state: PermissionState
    let permission: PresentedPermission
    let model: PippinPresentationModel

    var body: some View {
        LabeledContent(title) {
            HStack {
                Text(state.displayName)
                    .foregroundStyle(.secondary)
                PermissionActionControl(
                    model: model,
                    presentation: model.permissionAction(for: permission)
                )
            }
        }
    }
}

private struct PermissionSettingsRow: View {
    let title: String
    let detail: String
    let state: PermissionState
    let permission: PresentedPermission
    let model: PippinPresentationModel

    var body: some View {
        LabeledContent {
            HStack {
                Text(state.displayName)
                    .foregroundStyle(.secondary)
                PermissionActionControl(
                    model: model,
                    presentation: model.permissionAction(for: permission)
                )
            }
        } label: {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

private struct PermissionActionControl: View {
    let model: PippinPresentationModel
    let presentation: PermissionActionPresentation?

    var body: some View {
        if let presentation {
            if model.permissionActionInProgress == presentation.action {
                ProgressView()
                    .controlSize(.small)
                    .accessibilityLabel("Permission action in progress")
            }
            Button(presentation.title, action: perform)
                .disabled(model.permissionActionInProgress != nil)
        }
    }

    private func perform() {
        guard let presentation else { return }
        Task { await model.performPermissionAction(presentation.action) }
    }
}

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

private struct ModuleSettingsRow: View {
    let model: PippinPresentationModel
    let module: String

    private var moduleConfig: Config.ModuleConfig {
        model.config.modules[module] ?? .init()
    }

    var body: some View {
        LabeledContent(PippinMenuView.title(for: module)) {
            HStack {
                Toggle("Enabled", isOn: enabledBinding)
                Toggle("Writes", isOn: writesBinding)
                    .disabled(!moduleConfig.enabled)
            }
            .disabled(model.isApplyingConfig)
        }
    }

    private var enabledBinding: Binding<Bool> {
        Binding(
            get: { moduleConfig.enabled },
            set: { enabled in
                Task { await model.setModuleEnabled(enabled, module: module) }
            }
        )
    }

    private var writesBinding: Binding<Bool> {
        Binding(
            get: { moduleConfig.writes },
            set: { writes in
                Task { await model.setModuleWrites(writes, module: module) }
            }
        )
    }
}

private extension AppRuntimeState {
    var displayName: String {
        switch self {
        case .starting: "Starting"
        case .running: "Running"
        case .stopped: "Stopped"
        case .failed: "Not running"
        }
    }
}

private extension PermissionState {
    var displayName: String {
        switch self {
        case .notDetermined: "Not determined"
        case .denied: "Denied"
        case .restricted: "Restricted"
        case .writeOnly: "Write only"
        case .granted: "Granted"
        case .unavailable: "Unavailable"
        case .unknown: "Unknown"
        }
    }
}
