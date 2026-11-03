# HIG redesign: implementation guide

How to bring Tickoff's windows in line with Apple's Human Interface Guidelines. The design
and the reasoning live on the canvas; this guide turns it into code changes.

- **Design canvas (private):** https://claude.ai/artifact/1cMedkLD7XsxAerWKbbFNk
  Boards: Audit, Main window light and dark, Toolbar More menu, Edit Task sheet, New Project sheet.
- **Rules source:** the HIG pages themselves, not memory. Read the page before you change a
  component, under `https://developer.apple.com/design/human-interface-guidelines/<page>`:
  `sidebars`, `toolbars`, `lists-and-tables`, `sheets`, `buttons`, `typography`, `color`,
  `dark-mode`, `settings`, `search-fields`, `context-menus`. If a page and the canvas
  disagree, the page wins; fix the canvas.
- **Status:** design only. No app code has changed yet.

## Before you start

Follow `AGENTS.md`: create a GitHub issue, then branch `issue-<number>-hig-redesign` from an
up-to-date `main`. If the work splits into issues, one branch each (suggested split at the end).
Leave the build warning-free and the tests green after every step.

## The changes, in the order to do them

Each step is small enough to build and test on its own. Dependency rules in `AGENTS.md` still
apply: features never import each other, the shell holds no feature logic, SQL stays in its store.

### 1. Sidebar: navigation only

File: `Features/Filters/FiltersView.swift`.
- Delete the `.safeAreaInset(edge: .bottom)` block (Progress, "x of y completed", Clear
  Completed) and the `confirmingClear` dialog. HIG (Sidebars, macOS): no critical information or
  actions at the bottom, since people move windows so that edge is hidden.
- The `done` / `total` computed properties move to the detail column (step 2).
- Row icons keep following the tint (system accent). Project dots keep their fixed colours
  because they carry meaning.

### 2. Toolbar: title, progress, search, More

File: `Features/TaskList/TaskListView.swift`.
- Subtitle becomes the progress, for example `2 of 10 completed`, replacing the date and task
  count text. Counts already exist in `TaskSet`.
- Replace the custom `searchField`, `searchOpen`, `ClickAwayMonitor`, `searchBackground()` and
  `removingSharedBackground()` with the standard `.searchable(text:prompt:)`. Placeholder is
  "Search". Keep focusing it from ⌘F with `searchRequest` (`isPresented` / focus binding).
  Delete the `AppKit` import if nothing else needs it.
- Add a `ToolbarItem` More menu (`ellipsis.circle`, labelled "More") with: Show Notes (toggle),
  Use Compact Rows (toggle), divider, Clear Completed… (disabled when nothing is done).
  Clear Completed keeps its confirmation dialog and its `store.clearCompleted(project:)` call;
  the dialog moves here from the sidebar. Toolbar rule: every toolbar item also exists in the
  menu bar (step 6).
- Title length: the HIG says keep titles under 15 characters. Project names are user typed, so
  they can exceed it; accept truncation, do not shorten the name.

### 3. Task rows: plain list rows

Files: `Features/TaskList/TaskCard.swift` (rename to `TaskRow.swift` if you like; update tests
and doc comments), `TaskListView.swift`.
- Remove the card background and border, `Pill`, and the per-row Edit and Delete buttons.
- Row content, top to bottom: completion control, title (Body 13/16), one-line note (Callout
  12/15, secondary), then one metadata line (Subheadline 11/14, secondary): status label, a
  project dot with name (All Projects only), `High priority` style text, and the due label.
  Status and priority are always words; colour only reinforces them (HIG Color: never colour
  alone). Overdue stays red with the word "Overdue".
- Use `List(selection:)` with the default plain style and system separators and selection.
  Return or double-click opens the edit sheet; Delete removes after the existing flow.
- Keep the context menu (Edit…, Change Status, Delete). Context menu items must also exist in the
  menu bar (step 6).
- Performance rules from `AGENTS.md` stay: still a recycling `List`, still fine at 10,000 tasks.
  Do not do per-row work in `body`.

### 4. Type: built-in text styles

Files: `Shared/Theme.swift`, every call to `appearance.font(...)`.
HIG Typography: macOS has no Dynamic Type; use the built-in styles. macOS sizes from the page:

| Use | Style | Size / line height |
|---|---|---|
| Toolbar title | Title 3 | 15 / 20 (semibold per the system toolbar) |
| Sheet title | Title 2 | 17 / 22 |
| Row title, field text | Body | 13 / 16 |
| Note | Callout | 12 / 15 |
| Metadata, sidebar headers | Subheadline | 11 / 14 |

Use `.title3`, `.title2`, `.body`, `.callout`, `.subheadline` instead of `Appearance.font`.
Never go below 10pt. Remove the Text size setting (`UiScale`).

### 5. Appearance and accent: follow the system

Files: `Shared/Theme.swift`, `App/TickoffApp.swift`, `Features/Settings/*`,
`Features/Projects/*`, `Shared/Project.swift`, `Shared/ProjectStore.swift`.
- Remove `ThemeMode` and the `preferredColorScheme` call (HIG Dark Mode: no app-specific
  appearance setting).
- Remove the custom accent: drop `.tint(appearance.accent.color)` from `applying(_:)` so the
  system accent applies everywhere (HIG Color, macOS). `.applying` can go away entirely.
- **Project colours.** `projects.colour` stores `Accent` keys: `system`, `indigo`, `violet`,
  `teal`, `rose`, `orange`. That data must keep working. Create a `ProjectColour` type in
  `Shared/Project.swift` with the **same raw keys** and system-colour rendering:

  | Stored key | Label | Colour |
  |---|---|---|
  | `system` | Accent | `.accentColor` (follows System Settings) |
  | `indigo` | Indigo | `.indigo` |
  | `violet` | Purple | `.purple` |
  | `teal` | Teal | `.teal` |
  | `rose` | Pink | `.pink` |
  | `orange` | Orange | `.orange` |

  Keep `init?(key:)` lenient with `.system` as fallback, as `ProjectStore.project(from:)` does
  today. Do not rename keys or add a migration: `AGENTS.md` forbids changing what an existing
  code means. Replace `Accent` in `Project.colour`, `ProjectStore.create`, `ProjectDraft` and
  `ProjectEditorView`.
- Existing rows in the `settings` table (`theme_mode`, `accent`, `ui_scale`) stay in the
  database untouched and are simply no longer read. Never drop them: the file is shared with
  older builds.

### 6. Menu bar and settings

Files: `App/AppCommands.swift`, `App/ContentView.swift`, `App/TickoffApp.swift`,
`Features/Settings/*`.
- The commands already there stay (New Task, New Project…, Find Tasks, sidebar). Add, using the
  existing `AppActions` plus request counters pattern (see `findRequest`):
  Edit Task… (⌘E, needs a selected row), Delete (⌫ via the standard Edit menu), Mark as To Do /
  In Progress / Done, Clear Completed…, and View menu toggles Show Notes and Use Compact Rows.
  Toggle commands need the current value, so publish it through the focused value.
- Compact and Show Notes stay stored in the `settings` table (`compact_cards`, `show_notes`)
  through `SettingsStore`; keep those two keys and their defaults. HIG Settings: options that
  show or hide parts of a view belong in that view.
- With those moved, the Settings window has nothing left. Remove the `Settings` scene,
  `SettingsView` and the accent picker. This drops ⌘, ; confirm that choice with the owner
  before merging (the canvas lists it as an open decision). If you keep a window, it needs a real
  general setting; HIG asks for as few as possible.

### 7. Sheets

Files: `EditTaskView.swift`, `ProjectEditorView.swift`.
- Same structure for both: title (Title 2), a two-column form with labels in a leading, right
  aligned column and controls in the second, then Cancel and the default button at the trailing
  end. Esc is the cancel action, Return the default action.
- Default button uses the system accent (it will, once step 5 is done). Create stays disabled
  until the name is not empty. Errors stay inline.
- Colour in the New Project sheet is a labelled radio group; selected swatch gets a ring and
  `.isSelected`; every swatch has an accessibility label.
- One sheet at a time (HIG Sheets); the shell already presents them one by one.

### 8. Quick add bar

File: `Features/AddTask/AddTaskBar.swift`. Mostly unchanged: standard text field, standard
pop-up buttons for project and priority, one prominent Add button, disabled until there is a
title. Remove `.controlSize(.large)` so controls use system sizes.

## Tests

Add or update in `TickoffTests/` (Swift Testing, in-memory database, full-sentence names):
- `ProjectColour` maps every stored key, falls back to `.system` for an unknown key, and a
  project saved with each key reads back unchanged (`ProjectStoreTests`).
- Delete or trim `ThemeTests`, `SettingsModelTests` and `SettingsStoreTests` for removed
  settings; keep coverage that unknown or missing settings fall back to defaults, and that
  `compact_cards` and `show_notes` still round-trip.
- Progress subtitle text, if you extract it into a pure function.
- Do not drive the UI with synthetic clicks. Check visually with window-only screenshots, in
  light and dark, and with Increase Contrast turned on.

## Acceptance checklist

- [ ] Sidebar has no controls at its bottom edge.
- [ ] Search is the standard field in the toolbar; ⌘F focuses it; no custom event monitor.
- [ ] Rows are plain list rows; no per-row buttons; context menu and menu bar offer Edit,
      Change Status and Delete.
- [ ] Every toolbar item has a menu bar command.
- [ ] All text uses built-in styles, none under 10pt, in light and dark.
- [ ] Text contrast is at least 4.5:1; small secondary text is checked with Increase Contrast.
- [ ] Accent and appearance follow System Settings; no in-app theme, accent or text size.
- [ ] Existing databases open unchanged; project colours show as before.
- [ ] Settings window decision confirmed with the owner.
- [ ] Build has no warnings and all tests pass.
- [ ] README screenshots refreshed.

## Suggested issue split

1. Sidebar and toolbar (steps 1, 2, 6 toolbar and menu parts).
2. Task rows and type styles (steps 3, 4).
3. Follow the system: appearance, accent, project colours, Settings (steps 5, 6 settings part).
4. Sheets and add bar (steps 7, 8).

Steps 1 to 4 touch different files, so they can be separate branches off `main`; step 3 should
land before step 4 so the sheets pick up the system accent.
