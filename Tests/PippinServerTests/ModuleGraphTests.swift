import Testing

@testable import PippinServer

/// Step 1 owns the package graph and nothing else. This asserts the graph links:
/// `PippinServer` resolves against `PippinCore`, `PippinModules`, the MCP SDK, and
/// swift-nio. Real server behaviour arrives in steps 4–6.
@Suite("Package graph")
struct ModuleGraphTests {
    @Test("PippinServer links its dependencies")
    func serverNamespaceExists() {
        #expect(PippinServer.self == PippinServer.self)
    }
}
