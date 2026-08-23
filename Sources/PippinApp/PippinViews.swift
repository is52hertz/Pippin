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
                    pane: .reminders
                )
                PermissionStatusRow(
                    title: "Mail Automation",
                    state: model.permissions.mailAutomation,
                    pane: .mailAutomation
                )
                PermissionStatusRow(
                    title: "Mail Data",
                    state: model.permissions.fullDiskAccess,
                    pane: .mailData
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
                    SettingsLink()
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
        .frame(width: 390)
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
                    pane: .reminders
                )
                PermissionSettingsRow(
                    title: "Mail Automation",
                    detail: "Target-specific Apple Events access, checked only while Mail is running.",
                    state: model.permissions.mailAutomation,
                    pane: .mailAutomation
                )
                PermissionSettingsRow(
                    title: "Mail Data",
                    detail: "Effective read access to ~/Library/Mail, not a global Full Disk Access claim.",
                    state: model.permissions.fullDiskAccess,
                    pane: .mailData
                )
            }

            Section("Server") {
                ServerStatusRows(model: model)
            }

            if let error = model.errorMessage {
                Section("Could Not Apply Settings") {
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
    let pane: PrivacySettingsPane

    var body: some View {
        LabeledContent(title) {
            HStack {
                Text(state.displayName)
                    .foregroundStyle(.secondary)
                Button("Open \(title)…") { pane.open() }
            }
        }
    }
}

private struct PermissionSettingsRow: View {
    let title: String
    let detail: String
    let state: PermissionState
    let pane: PrivacySettingsPane

    var body: some View {
        LabeledContent {
            HStack {
                Text(state.displayName)
                    .foregroundStyle(.secondary)
                Button("Open \(title)…") { pane.open() }
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
