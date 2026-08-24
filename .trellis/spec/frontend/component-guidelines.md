# Component Guidelines

> Concrete SwiftUI component conventions established by the Pippin app.

## Convention: Settings Window Shell

**What:** Pippin Settings is one fixed-ID ordinary SwiftUI `Window`, not a
SwiftUI `Settings` scene. It suppresses default launch, uses content-minimum
resizability, and is opened through one shared `OpenWindowAction` control after
calling modern `NSApp.activate()`.

**Why:** Pippin is an `LSUIElement` menu-bar app with a multi-pane,
`NavigationSplitView`-based Settings UI. The ordinary window preserves
menu-bar-only startup while providing standard resizable window controls and
reliable reopening/raising of the same instance.

```swift
Window("Pippin Settings", id: PippinWindow.settingsID) {
    PippinSettingsView(model: model)
}
.defaultLaunchBehavior(.suppressed)
.windowResizability(.contentMinSize)
```

The sidebar is visible by default but remains controlled by the system toolbar
button. Its visibility must therefore be mutable, window-local state:

```swift
@State private var columnVisibility: NavigationSplitViewVisibility = .doubleColumn

NavigationSplitView(columnVisibility: $columnVisibility) {
    // Sidebar
} detail: {
    // Selected pane
}
```

A zero-size system `ToolbarItem` is permitted solely to make SwiftUI install the
unified macOS toolbar/titlebar. Do not draw custom titlebar material or traffic
lights.

### Wrong vs Correct

```swift
// Wrong: the system sidebar button remains visible but cannot change a constant.
NavigationSplitView(columnVisibility: .constant(.doubleColumn)) { ... }

// Correct: the standard button changes window-local visibility.
NavigationSplitView(columnVisibility: $columnVisibility) { ... }
```

Do not discover the Settings window by title, use deprecated
`activate(ignoringOtherApps:)`, or replace the standard sidebar button with a
custom control.

### Required Verification

- Signed-app launch stays menu-bar-only.
- Menu `Settings…` and Command-comma raise the same window.
- Close/reopen and minimize/restore work from the menu-bar entry.
- The standard sidebar button hides and restores the sidebar.
- Resizing keeps standard system chrome and materials.
