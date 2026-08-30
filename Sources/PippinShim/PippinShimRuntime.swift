import Foundation
import MCP

public enum ShimFailure: Error, Equatable, Sendable {
    case endpointMissing
    case endpointMalformed
    case endpointStale
    case launchFailed
    case readinessTimedOut
    case authenticationFailed
    case connectionFailed
    case residentStopped
    case stdioConnectionFailed
    case stdioOutputFailed

    public var diagnostic: String {
        switch self {
        case .endpointMissing:
            return "pippin-shim: Pippin.app launched, but endpoint.json was not published. Open Pippin's menu-bar item and check its startup status."
        case .endpointMalformed:
            return "pippin-shim: endpoint.json is malformed or not private (mode 0600). Quit and relaunch Pippin.app to republish it."
        case .endpointStale:
            return "pippin-shim: endpoint.json still belongs to a stopped Pippin process. Quit and relaunch Pippin.app."
        case .launchFailed:
            return "pippin-shim: macOS could not launch Pippin.app. Install the signed app bundle, then open it once manually."
        case .readinessTimedOut:
            return "pippin-shim: Pippin.app did not become ready before the startup deadline. Open its menu-bar item and check the server status."
        case .authenticationFailed:
            return "pippin-shim: Pippin rejected the published endpoint credentials. Quit and relaunch Pippin.app to rotate the endpoint."
        case .connectionFailed:
            return "pippin-shim: the resident Pippin server connection failed. Confirm Pippin.app is running, then reconnect the MCP client."
        case .residentStopped:
            return "pippin-shim: the resident Pippin.app process stopped. Relaunch it, then reconnect the MCP client."
        case .stdioConnectionFailed:
            return "pippin-shim: could not open the MCP client's stdio channel. Restart the client and reconnect."
        case .stdioOutputFailed:
            return "pippin-shim: the MCP client's stdout channel closed while a response was being delivered. Reconnect the client."
        }
    }

    static func httpFailure(for error: Error) -> ShimFailure {
        guard case .internalError(let message) = error as? MCPError else {
            return .connectionFailed
        }
        switch message {
        case "Authentication required", "Access forbidden":
            return .authenticationFailed
        default:
            return .connectionFailed
        }
    }
}

public struct PippinShimRuntime {
    public init() {}

    public func run() async throws {
        let endpoint = try await EndpointResolver().resolve()
        let stdio = StdioTransport(logger: nil)
        let configuration = URLSessionConfiguration.ephemeral

        let relay = ShimRelay(
            endpoint: endpoint,
            stdio: stdio,
            urlSessionConfiguration: configuration
        )
        try await relay.run()
    }
}
