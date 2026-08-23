# Step 8 — GUI Verification

Date: 2026-08-23.

## Automated quality gate

- `swift build`: passed.
- `swift test`: **185 tests in 24 suites**, passed.
- `git diff --check HEAD`: passed.
- Independent `trellis-check`: no findings and no self-fixes.
- Production catalogue still contains only `pippin_status`; its description and
  serialized `tools/list` remain inside the established budgets.

Focused coverage includes:

- every supported EventKit and Apple Events state mapping, including
  `not_determined` versus `denied`;
- Mail-not-running and effective Mail-directory probe behavior;
- compact permission serialization and `pippin_status` output schema;
- injected, deterministic server snapshots with no live TCC in unit tests;
- presentation-model success/failure behavior;
- config persistence before resident-host application, including a persistence
  failure that proves the host remains unchanged;
- the existing real SDK `tools/list_changed` notification path.

## Signed bundle and runtime

`Scripts/package_app.sh` passed, followed by
`codesign --verify --deep --strict build/Pippin.app`.

- Bundle identifier: `io.github.is52hertz.pippin`
- Authority: `Pippin Local Signing`
- Signing identity SHA-1: `1AB7E0BC58C427092143FBADABA7F34CD607775D`
- Designated requirement remains bound to the same identifier and certificate.
- `LSUIElement=true`; LaunchServices reports `ApplicationType=UIElement`.
- Both required usage descriptions and the bundled shim are present.

A fresh packaged launch published a mode-0600 endpoint on `127.0.0.1`. A real
MCP `pippin_status` call returned:

```json
{
  "full_disk_access": "denied",
  "mail_automation": "unavailable",
  "reminders": "not_determined"
}
```

The call completed promptly, did not output the bearer token, and Mail was not
running before or after it. This proves the ordinary status path neither launches
Mail nor requests Apple Events consent.

## HIG / Liquid Glass source review

- Native `MenuBarExtra` with `.window` style and native `Settings` scene.
- Standard `Form`, `Section`, `LabeledContent`, `Toggle`, `Button`,
  `SettingsLink`, semantic foreground styles, and system window materials.
- No custom window chrome, hand-drawn background, or manual glass effect.
- One shared `@MainActor @Observable` presentation model; resident actors remain
  authoritative and permission work does not block the main actor.
- Permission labels state the actual scope: **Mail Automation** is per target and
  **Mail Data** is an effective directory-access check.

## Pending visual confirmation

The computer-use driver can inspect regular application windows but cannot
attach to Pippin before its `LSUIElement` status item opens a window. The final
visual check therefore remains user-observed:

- menu-bar popup contains Server, Permissions, and Modules;
- `Settings…` and Command-comma open the native Settings window;
- controls/materials render correctly in the user's current appearance;
- opening and refreshing these views causes no TCC prompt;
- privacy buttons route to the intended System Settings panes.
