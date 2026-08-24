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

private struct ServerStatusSection: View {
    let model: PippinPresentationModel

    var body: some View {
        Section("Server") {
            ServerStatusRows(model: model)
        }
    }
}

struct ServerStatusRows: View {
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
