import AppKit

enum PrivacySettingsPane {
    case reminders
    case mailAutomation
    case mailData

    private static let generalURL = URL(
        string: "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension"
    )!

    private var url: URL {
        let route = switch self {
        case .reminders: "Privacy_Reminders"
        case .mailAutomation: "Privacy_Automation"
        case .mailData: "Privacy_AllFiles"
        }
        return URL(
            string: "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?\(route)"
        )!
    }

    @MainActor
    func open() {
        if !NSWorkspace.shared.open(url) {
            NSWorkspace.shared.open(Self.generalURL)
        }
    }
}
