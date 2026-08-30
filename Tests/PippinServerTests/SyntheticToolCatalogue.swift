import MCP
import PippinCore

@testable import PippinServer

/// Test-only module tools. Production intentionally ships no Reminders or Mail
/// definitions yet, so registry and notification gating need a synthetic surface
/// until those module tasks land.
enum SyntheticToolCatalogue {
    static let definitions: [ToolDefinition] = [
        StatusTool.definition,
        definition("pippin_reminders_search", module: "reminders", capability: .read),
        definition("pippin_reminders_create", module: "reminders", capability: .write),
        definition("pippin_reminders_delete", module: "reminders", capability: .destructive),
        definition("pippin_mail_search", module: "mail", capability: .read),
    ]

    static let registry = ToolRegistry(catalogue: definitions)

    private static func definition(
        _ name: String,
        module: String,
        capability: Capability
    ) -> ToolDefinition {
        ToolDefinition(
            tool: Tool(name: name, description: nil, inputSchema: .object([:])),
            module: module,
            requiredCapability: capability
        )
    }
}
