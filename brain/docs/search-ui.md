# SwiftUI macOS — Search UX Refactoring

## Objective

Improve the existing macOS task manager UI by moving the Search field from the main content area into the native macOS window toolbar.

Follow Apple's Human Interface Guidelines and native SwiftUI conventions.

**This is a focused UI refactoring, not a complete redesign.**

## 1. Inspect the Existing Implementation

Before modifying code:

- Identify the main `NavigationSplitView` or equivalent container.
- Locate the existing Search field and its binding.
- Identify the current task-filtering implementation.
- Inspect the existing toolbar items, including the sparkle icon and ellipsis menu.
- Identify the application's minimum macOS deployment target.

Reuse existing state management, view models, and filtering logic.

## 2. Implement Native Toolbar Search

Use SwiftUI's `.searchable()` modifier with toolbar placement.

Example:

```swift
struct ContentView: View {
    @State private var searchText = ""

    var body: some View {
        NavigationSplitView {
            SidebarView()
        } detail: {
            TaskListView(searchText: searchText)
                .navigationTitle("All Tasks")
        }
        .searchable(
            text: $searchText,
            placement: .toolbar,
            prompt: "Search tasks"
        )
    }
}
```

Adapt this example to the existing architecture. Do not introduce duplicate search state.

Let SwiftUI manage the native search field, keyboard focus, appearance, and toolbar integration wherever supported.

## 3. Toolbar Layout

Preserve the current toolbar structure.

**Leading area**
- Native macOS traffic-light buttons
- Sidebar toggle
- Current view title
- Task completion summary

**Trailing area**
- Native Search control
- Existing sparkle action
- Existing ellipsis menu

Search should appear before the existing trailing toolbar actions where SwiftUI's toolbar layout allows.

Use `ToolbarItem` placements appropriately. Do not attempt to reproduce the system toolbar manually.

Do not hardcode toolbar coordinates or offsets.

## 4. Remove the Existing Search Row

Remove the standalone Search field located beneath Quick Add.

Preserve the Quick Add row with:

- Task input
- Project selector
- Priority selector
- Add button

After removing the Search row, allow the task list to move upward naturally.

Avoid inserting unnecessary padding to compensate for the removed field.

## 5. Keyboard Interactions

Implement or verify:

| Shortcut | Action |
|---|---|
| ⌘F | Focus Search |
| Escape | Clear or dismiss Search according to native behavior |
| ⌘A | Select text in the focused Search field |

Prefer the keyboard behavior supplied by SwiftUI's `.searchable()`.

Only introduce custom keyboard handling when the native implementation does not meet the requirements.

Do not interfere with existing Quick Add shortcuts.

## 6. Search Behavior

Preserve the existing search implementation.

Requirements:

- Filter task titles and existing searchable descriptions.
- Support case-insensitive matching.
- Update results as the user types.
- Restore the appropriate task list when Search is cleared.
- Preserve existing project, status, and priority filters.
- Avoid unnecessary persistence-layer requests.

Search scope must be predictable and consistent with the existing application behavior.

## 7. Window Resizing

Allow SwiftUI and macOS to manage the toolbar's adaptive layout.

Test:

- Full-screen window
- Standard desktop window
- Narrow supported window width
- Sidebar expanded and collapsed

Search must not overlap existing toolbar actions or window controls.

Avoid manually implementing a separate compact search button unless required by the actual behavior of the supported macOS versions.

## 8. Accessibility and Appearance

Use the native search control to inherit macOS accessibility and appearance behavior.

Verify:

- VoiceOver identifies Search correctly.
- Search receives keyboard focus.
- Dark mode matches the existing interface.
- Search focus is visually apparent.
- Toolbar controls remain accessible.

## 9. Acceptance Criteria

- [ ] Native toolbar Search implemented using `.searchable()`.
- [ ] Existing standalone Search row removed.
- [ ] Quick Add remains unchanged.
- [ ] Search filters tasks correctly.
- [ ] ⌘F focuses Search.
- [ ] Existing sparkle and ellipsis actions work.
- [ ] Toolbar adapts to supported window sizes.
- [ ] Sidebar functionality is preserved.
- [ ] Existing tests pass.
- [ ] No unrelated UI or business logic changes.

## 10. Final Instructions

Implement this with the smallest reasonable code change.

Do not restructure unrelated views, change task models, or introduce third-party dependencies.

Build and run the macOS application after making changes.

Provide a summary of modified files, changes made, and any remaining limitations.

**Target result:** A clean native macOS task manager with Search integrated into the toolbar, while Quick Add remains the primary action above the task list.