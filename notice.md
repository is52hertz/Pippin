# Project Notice — Pippin

Durable, cross-task facts. Session progress does not belong here.

## Signing identity — do not regenerate

Pippin.app is signed with a self-signed local identity. macOS keys TCC grants to
the code signature, so replacing this certificate silently invalidates every
permission the user has granted — it produces no error, only later failures that
look like bugs.

```
Identity    Pippin Local Signing
SHA-1       1AB7E0BC58C427092143FBADABA7F34CD607775D
Bundle ID   io.github.is52hertz.pippin
Created     2026-08-23, validity 7300 days
```

The designated requirement TCC matches on:

```
identifier "io.github.is52hertz.pippin"
  and certificate root = H"1ab7e0bc58c427092143fbadaba7f34cd607775d"
```

Only two things are pinned: the bundle identifier and the certificate. The
binary's hash is not, so rebuilding freely is safe. Changing either of the two is
not, and neither is recoverable except by re-granting every permission by hand.

`Scripts/setup_dev_signing.sh` refuses to overwrite an existing identity and has
no `--force`. That is deliberate; do not add one.

## Packaging

- `Scripts/package_app.sh` → `build/Pippin.app`. Requires the identity above and
  **fails hard** if it is missing or ambiguous. There is no ad-hoc fallback, by
  design — an ad-hoc signature has no stable designated requirement.
- Hardened runtime is deliberately off. It exists to satisfy notarization, which
  is permanently out of scope (no paid Apple Developer account), and enabling it
  would impose an entitlement requirement on the Apple Events this app sends.
- Never validate permission-dependent behaviour via `swift run`. A bare
  executable has a different signature and bundle identity and does not inherit
  the app's TCC grants. Use `Scripts/compile_and_run.sh`.

## Dependencies

Two, both user-approved: `modelcontextprotocol/swift-sdk` (pinned `exact:
"0.12.1"` — pre-1.0, and its transport contract has been mapped in detail) and
`apple/swift-nio` (the MCP SDK ships no HTTP listener). Adding a third needs a
decision.

`PippinCore` must not import SwiftUI, AppKit, or the MCP SDK. The package graph
blocks the SDK and NIO; `Tests/PippinCoreTests/ImportBoundaryTests.swift` covers
the system frameworks.

## Secrets

The repository is public. `.gitignore` denies keys, certificates, keychains,
provisioning profiles, `build/`, and `endpoint.json` (which carries the server's
bearer token at runtime). `setup_dev_signing.sh` exports nothing; key material
lives only in a mode-0700 temp directory and is wiped by a trap.
