# G0: swift-sdk 0.12.1 Host Boundary

## Frozen upstream

- Package: `modelcontextprotocol/swift-sdk`
- Tag: `0.12.1`
- Checkout commit: `a0ae212ebf6eab5f754c3129608bc5557637e605`
- Inspected product manifest: `.build/checkouts/swift-sdk/Package.swift`
- Inspected conformance host:
  `.build/checkouts/swift-sdk/Sources/MCPConformance/Server/HTTPApp.swift`

The package exposes one importable library product, `MCP`. The NIO-based
`HTTPApp` is source inside the `MCPConformanceServer` executable target and is
not an importable library product. Pippin therefore cannot adopt it as an API
without copying/forking upstream code or changing the dependency graph.

## What the public SDK owns

The public `MCP` product owns:

- JSON-RPC message models and server dispatch;
- `StatefulHTTPServerTransport`, including one MCP session's Streamable HTTP
  validation, SSE framing, request/response correlation, and resumability;
- `HTTPClientTransport` and `StdioTransport` used by the shim;
- `HTTPRequest`, `HTTPResponse`, validation pipelines, and session-ID
  generation interfaces;
- MCP tool metadata, schemas, notifications, and protocol-version behavior.

Pippin must not duplicate these behaviors.

## Retained Pippin deviations

| Pippin code | Difference from conformance `HTTPApp` | Reason to retain |
|---|---|---|
| `HTTPListener` | Separates socket binding/type conversion from session routing | The upstream NIO host is not importable; Pippin also needs an ephemeral-port fallback and publication through `endpoint.json` |
| NIO runtime tuning | Two event-loop threads, backlog 64, and no `maxMessagesPerRead` override differ from conformance defaults | Bounded personal-use resident server; black-box tests, not these tunings, define compatibility |
| Off-main dispatch | Request work remains on NIO/task executors instead of the SwiftUI main actor | Agent traffic must not stall the menu-bar/settings UI |
| Path/header conversion | Pippin strips the query for exact `/mcp` matching and joins repeated headers per RFC 7230 | Framework-neutral request conversion and endpoint isolation |
| Stream flushing | Each SDK SSE chunk is written and flushed immediately | Required to preserve streaming through NIO |
| Loopback validation | Rejects non-loopback bind before NIO bind | Product security boundary |
| Bearer validation before session lookup | Unknown credentials cannot probe session IDs | Product authentication policy |
| Token-to-capability resolution | Each credential maps to a stable label and capability set | Required tier-ready security model |
| Token/session pinning | A session rejects a different bearer token | Prevents capability confusion after initialize |
| Resident shared primitives | Confirm tokens, audit journal, config, AppleScript coordination, and future Apple data handles are process-wide | Product's single-state-owner architecture |
| Per-session tool catalogue | Visible tools are derived from current config and the session's capabilities | Structural tool gating and token budget |
| Session sweep and tool-list notifications | Pippin controls expiry and emits `notifications/tools/list_changed` after config changes | Product lifecycle/config policy |
| Status provider | Reports the resident app's live state | App UI/status contract |

`HTTPListener` remains a thin NIO socket/framing adapter. `ServerHost` remains a
policy host around one SDK transport per MCP session. Neither is replaced by a
third-party protocol stack.

## Removable or correctable deviations

1. **Initialize classification.** SDK 0.12.1's `JSONRPCMessageKind` is declared
   `package`, so Pippin cannot call the conformance host's classifier. The public
   `Request<Initialize>` decoder is intentionally not used for routing: it would
   validate JSON-RPC/params earlier than the conformance host and alter malformed
   request behavior. Step 1 retains a minimal `JSONSerialization` routing peek,
   but matches upstream by requiring `method == Initialize.name` plus a
   string/integer request ID. The unchanged body then goes to the SDK transport,
   which exclusively owns protocol validation and its error response.
2. **DELETE cleanup.** The upstream conformance host removes a session only when
   DELETE returns HTTP 200. Pippin currently closes on every DELETE response.
   Step 1 should align with successful-only cleanup and cover failed DELETE with
   a regression test. This is MCP-session conformance, not a change to the app or
   resident server's enable/disable lifecycle.
3. **Provenance.** The listener should name the exact tag/commit and state that
   only the non-importable host adapter was adapted. It must not imply that the
   public SDK lacks Streamable HTTP server transport.

## Stop/replacement rule

The retained deviations above cover every intentional code-level difference that
affects routing, security, lifecycle, or wire behavior. Incidental NIO tuning is
listed but is not a compatibility promise.

There is no public SDK API in 0.12.1 that can replace the multi-session NIO host.
Step 1 is therefore a bounded semantic alignment, not a rewrite. If a future SDK
ships an importable host adapter with hooks for authentication and session
policy, replace `HTTPListener`/the generic portion of `ServerHost` behind the
existing black-box HTTP tests; module code must remain untouched.
