# Cross-Layer Thinking Guide

Map the real Pippin flow before changing a contract. The important boundaries
are SwiftPM targets, actor ownership, MCP transport conversion, persistence, and
SwiftUI presentation.

## Request Flow

```text
NIO HTTP → HTTPListener → ServerHost validation/session routing
         → ToolRegistry + ToolContext → domain operation → MCP result
```

- Keep HTTP path/header/body and SSE conversion in `HTTPListener`.
- Keep authentication, sessions, visible-tool decisions, and MCP call dispatch
  in `ServerHost`.
- Keep reusable validation and safety primitives transport-free in
  `PippinCore`.
- Convert actionable domain failures to the structured `PippinError` wire shape;
  do not turn them into empty successful results.

## Settings and Presentation Flow

```text
SwiftUI control → PippinPresentationModel → ServerRuntime.updateConfig
                → Config.save → ServerHost.updateConfig → snapshot → SwiftUI
```

The persisted config and resident host update before the shared presentation
mirror advances. On failure, keep the prior mirror and expose an actionable
error. Menu-bar and Settings surfaces must continue to receive the same model
from `AppDelegate`.

## Package and Import Boundaries

- `PippinCore` has no MCP, NIO, SwiftUI, or AppKit dependency.
- `PippinModules` depends on `PippinCore`; it must not own transport behavior.
- `PippinServer` adapts core/module behavior to MCP and NIO.
- `PippinApp` composes the resident service and owns presentation/UI behavior.
- Tests belong to the target whose contract they verify; import-boundary tests
  enforce the system-framework edges that SwiftPM cannot express.

## Change Touchpoints

When changing the tool surface, inspect `ProductionToolCatalogue`,
`ToolRegistry`, `ServerHost.call`, synthetic catalogues, visibility tests, and
`ToolSurfaceBudgetTests`. A disabled tool must disappear from `tools/list`, and a
stale cached call must still be rejected.

When changing `Config`, inspect its Codable keys/defaults, validation, load/save
tests, `ServerRuntime.updateConfig`, `ServerHost.updateConfig`, Settings controls,
and any tool-visibility effect.

When changing runtime or permission state, inspect `ServerSnapshot`,
`AppRuntimeSnapshot`, `PippinPresentationModel`, both app surfaces, preview
fixtures, and `PippinAppTests`.

When adding private-store access, trace path resolution, schema probing, bound
query values, backend fallback, and the final user-visible error. The existing
`immutable=1` connection is a known unsafe limitation for actively modified Mail
databases and must not be propagated.

## Avoid

- Do not move protocol/session decisions into the NIO adapter or SwiftUI views.
- Do not publish endpoint metadata before the listener accepts connections.
- Do not advance UI config optimistically before persistence and host update
  succeed.
- Do not assume a package dependency proves system-framework isolation; retain
  the source import-boundary tests.
- Do not update one consumer of a shared DTO, config field, tool definition, or
  presentation enum without searching all producers and consumers.

## Review Checklist

- [ ] Traced the complete read/write flow through real symbols.
- [ ] Verified validation at each trust boundary and cleanup on partial failure.
- [ ] Checked package dependencies and source import tests.
- [ ] Updated every producer, consumer, preview, and affected test.
- [ ] Preserved tool-budget, permission, session, and token-safety invariants.
