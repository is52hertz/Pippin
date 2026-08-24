import PippinCore
import PippinServer
import SwiftUI

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
