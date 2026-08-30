# Backend Directory Structure

## Target Ownership

- `Sources/PippinCore/` contains transport- and UI-independent domain types and
  safety primitives. Examples: `Config`, `PippinError`, `ConfirmTokenStore`,
  `BackendRouter`, `SQLiteReader`, `AppleScriptRunner`, and `ToolContext`.
- `Sources/PippinModules/` is the package boundary reserved for product modules.
  It currently contains only the `PippinModules` namespace and depends solely on
  `PippinCore`; production tool registration currently lives in
  `Sources/PippinServer/ProductionToolCatalogue.swift`.
- `Sources/PippinServer/` owns MCP and SwiftNIO integration. `ServerHost` owns
  sessions and shared service state, `HTTPListener` adapts NIO HTTP messages, and
  `ToolRegistry` derives the visible MCP tool surface.
- `Sources/PippinApp/Runtime/ServerRuntime.swift` composes and owns the resident
  server for the macOS app; it is not a second server implementation.

Tests mirror targets under `Tests/PippinCoreTests`, `Tests/PippinServerTests`,
`Tests/PippinAppTests`, and `Tests/PippinShimTests`.

## Placement Rules

- Put reusable validation, DTOs, persistence primitives, and safety gates in
  `PippinCore` only when they have no MCP, NIO, SwiftUI, or AppKit dependency.
- Put wire conversion and protocol lifecycle in `PippinServer`; keep the private
  `PippinHTTPHandler` in `HTTPListener.swift` thin and delegate decisions to
  `ServerHost`.
- Keep one source of truth for shared state. `ServerHost` owns session state;
  `ServerRuntime` owns process lifecycle; `Config` owns the persisted shape.

## Avoid

- Do not import UI or transport frameworks into `PippinCore`.
- Do not duplicate capability or write gating in individual transports. Use
  `ToolRegistry` for visibility and re-check visibility in `ServerHost.call`.
- Do not put backend lifecycle state in SwiftUI views.
