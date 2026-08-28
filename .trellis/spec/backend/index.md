# Backend Specifications

These rules cover the SwiftPM service layers in `Sources/PippinCore`,
`Sources/PippinModules`, and `Sources/PippinServer`.

## Pre-Development Checklist

- Read [Directory Structure](./directory-structure.md) before placing code.
- Read [Security and Transport](./security-and-transport.md) for any request,
  session, tool, AppleScript, SQLite, token, or listener change.
- Read [Database Guidelines](./database-guidelines.md) when accessing SQLite or
  another application's data.
- Read [Error Handling](./error-handling.md) and [Logging](./logging-guidelines.md)
  when adding a failure path or operational event.
- Read [Quality](./quality-guidelines.md) before writing or running tests.

## Non-Negotiable Boundary

`PippinCore` must remain independent of MCP, SwiftNIO, SwiftUI, and AppKit.
`Package.swift` expresses this in the target graph; transport adaptation belongs
in `PippinServer`, while application lifecycle and UI belong in `PippinApp`.
