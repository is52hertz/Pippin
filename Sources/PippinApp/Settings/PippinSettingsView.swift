import SwiftUI

struct PippinSettingsView: View {
    let model: PippinPresentationModel
    @State private var selection: SettingsPane? = .general
    @State private var columnVisibility: NavigationSplitViewVisibility = .doubleColumn

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            List(SettingsPane.allCases, selection: $selection) { pane in
                Label(pane.title, systemImage: pane.systemImage)
                    .tag(pane)
            }
            .listStyle(.sidebar)
            .navigationSplitViewColumnWidth(min: 160, ideal: 180, max: 210)
        } detail: {
            switch selection ?? .general {
            case .general:
                GeneralSettingsPane(model: model)
            case .integrations:
                IntegrationsSettingsPane(model: model)
            case .privacy:
                PrivacySettingsPane(model: model)
            case .advanced:
                AdvancedSettingsPane(model: model)
            case .about:
                AboutSettingsPane()
            }
        }
        .toolbar {
            ToolbarItem {
                Color.clear
                    .frame(width: 0, height: 0)
            }
        }
        .frame(minWidth: 640, minHeight: 420)
        .task { await model.refresh() }
    }
}

#if DEBUG
private struct PippinSettingsPreview: View {
    @State private var model = PippinPresentationModel(
        runtime: PreviewRuntime(.needsAttention)
    )

    var body: some View {
        PippinSettingsView(model: model)
    }
}

#Preview("Settings") {
    PippinSettingsPreview()
        .frame(width: 720, height: 500)
}
#endif
