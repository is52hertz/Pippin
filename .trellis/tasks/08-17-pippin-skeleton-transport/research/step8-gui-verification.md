# Step 8 — GUI Verification

Date: 2026-08-23 through 2026-08-24.

## Initial GUI automated quality gate

- `swift build`: passed.
- `swift test`: **185 tests in 24 suites**, passed.
- `git diff --check HEAD`: passed.
- The initial GUI pass's independent `trellis-check` reported no findings or
  self-fixes before the later functional onboarding patch.
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

## HIG / Liquid Glass source review (insufficient by itself)

- Native `MenuBarExtra` with `.window` style and native `Settings` scene.
- Standard `Form`, `Section`, `LabeledContent`, `Toggle`, `Button`,
  `OpenSettingsAction`, semantic foreground styles, and system window materials.
- No custom window chrome, hand-drawn background, or manual glass effect.
- One shared `@MainActor @Observable` presentation model; resident actors remain
  authoritative and permission work does not block the main actor.
- Permission labels state the actual scope: **Mail Automation** is per target and
  **Mail Data** is an effective directory-access check.

These source-level properties are necessary but did not predict the actual
composition quality. They must not be used as evidence that AC10 has passed.

## User visual review — 2026-08-23

The first packaged build opened its menu as a nearly zero-height blank strip:
`Form` had a fixed width but no usable height inside the `.window`-style
`MenuBarExtra`. A one-line regression fix gives the menu a 390×440pt scrollable
viewport. The signed rebuild renders Server, Permissions, Modules, and Settings.

The user then rejected the rendered UI as non-HIG-compliant and visually
unfinished. Concrete debt visible in the manual screenshots:

- the menu is too dense for its role and clips the lower Modules/action content,
  making its scroll affordance and primary actions unclear;
- permission buttons dominate each row and create inconsistent wrapping and
  alignment, especially Mail Automation;
- the Settings window is much larger than its content needs, with excessive and
  uneven empty space;
- Refresh appears as an isolated centered toolbar control with weak hierarchy;
- the overall information hierarchy and spacing do not read like a deliberate
  macOS settings experience even though every component is system-provided.

The screenshots live in a temporary user directory and are not copied into this
public repository. **AC10 remains open.** The UI needs a dedicated visual/HIG
redesign and another manual review rather than more source-only assertions.

## Initial functional manual checks

The computer-use driver can inspect regular application windows but cannot
attach to Pippin's `LSUIElement` status item reliably. The user only needs to
exercise the interactions that cannot be proved by unit/protocol tests:

1. Scroll the menu from top to bottom and confirm the Modules plus
   `Settings…` / Refresh / Quit action row remain reachable.
2. Open Settings once from `Settings…` and once with Command-comma; both must
   focus the same native Settings window rather than create duplicates.
3. Disable one module, close and reopen Settings, confirm the value persisted,
   then restore the module to enabled and leave Writes off.
4. Open each of Reminders, Mail Automation, and Mail Data settings; each must
   route to its intended Privacy & Security pane. Do not grant or revoke access.
5. Use Refresh in the menu and Settings. It must return promptly, update status,
   show no TCC prompt, and not launch Mail.

### Pre-fix result

| Check | Result | Evidence / follow-up |
|---|---|---|
| Menu scroll and action row | Pass | Modules and `Settings…` / Refresh / Quit remain reachable. |
| Settings entry points | Partial failure | Both open Settings, but neither reliably activates and raises an already-open Settings window. Fix the `LSUIElement` activation path. |
| Module persistence | Pass | The changed enabled state survived close/reopen and was restored. |
| Privacy routes | Mixed | All routes open the intended panes. Reminders and Automation do not show Pippin because no first authorization request has registered it with TCC. Mail Data retained the grant from the prior run and was not changed here. |
| Refresh | Pass | Returns normally with no TCC prompt. |

The missing Reminders/Automation rows are not a deep-link failure. EventKit
requires an explicit `requestFullAccessToReminders` call before the system can
prompt and register the app. Apple Events permission is target-specific and
likewise needs a user-initiated automation attempt; a passive status read and a
settings-page navigation cannot create the entry. Whether Step 8 adds explicit
request actions or defers registration to the first module call is a product
decision because the former intentionally triggers TCC UI (and Automation may
need Mail to be running).

## Functional onboarding patch verification — 2026-08-24

The approved follow-up patch addresses the Settings activation failure and adds
explicit, state-specific permission onboarding without changing the temporary
390×440 functional layout or claiming AC10:

- both the menu item and Command-comma use the same `OpenSettingsAction` control
  and call `NSApp.activate()` before opening the Settings scene;
- `ServerHost` and `pippin_status` retain only the passive
  `PermissionProviding` dependency, while user clicks route separately through
  `PermissionActionPerforming` and `ServerRuntime`;
- Reminders and Mail Automation prompting is reachable only from explicit
  **Request Access…** actions; Mail launch resolves only `com.apple.mail`; Mail
  Data only opens Full Disk Access instructions with the general Privacy &
  Security fallback retained for every exact deep link;
- successful, failed, and cancelled actions refresh the passive snapshot, and
  the shared presentation model suppresses concurrent permission actions.

Automated verification for this functional patch:

- `swift build`: passed.
- `swift test`: **193 tests in 24 suites**, passed.
- `swift build -c release`: passed from the existing build cache without new
  diagnostics.
- `git diff --check`: passed after the review self-fix.

### Packaged-app rerun result

The user completed the signed-app rerun on 2026-08-24. All four functional
checks passed:

| Check | Result |
|---|---|
| Menu `Settings…` and Command-comma | Both raise the same existing Settings window after it has been covered by another app. |
| Reminders onboarding | **Request Access…** presents the system prompt and refreshes to the selected result. |
| Mail Automation onboarding | **Open Mail…** starts Mail; the row advances from `unavailable` to `not_determined`; the separate **Request Access…** presents the target-specific Automation prompt. |
| Mail Data onboarding | **Open Full Disk Access…** opens the intended pane and does not grant access programmatically. |

A passive MCP status call after onboarding reported all three effective states as
`granted`. The bearer token was never printed or logged. This closes the
functional follow-up; the visual redesign and AC10 remain open and are not part
of this patch.
