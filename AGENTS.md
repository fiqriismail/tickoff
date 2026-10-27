# AGENTS.md

Tickoff is a native macOS task manager built with Swift and SwiftUI and a local SQLite
database (GRDB). This file is the contract for any coding agent working in this repository:
follow the architecture below, and when in doubt, copy the patterns already in the code
rather than inventing new ones.

- **Stack:** Swift 6 language mode, SwiftUI, minimum macOS 14 Sonoma, Xcode 16+, GRDB (Swift
  Package Manager) for SQLite, Swift Testing for tests. macOS only.
- **History:** the app was rewritten from Rust/egui. The last Rust commit is tagged
  `v0.1.0-rust`. The background and decisions are in `brain/docs/swift-port.md`.
- **Next up:** the Projects milestone (epic #1), built on this code.

## Commands

```sh
xcodebuild build -project Tickoff.xcodeproj -scheme Tickoff -destination 'platform=macOS'
xcodebuild test  -project Tickoff.xcodeproj -scheme Tickoff -destination 'platform=macOS'
packaging/macos/release.sh   # Release archive, ad-hoc signed, dist/Tickoff-<version>-macos-universal.zip
```

Open `Tickoff.xcodeproj` in Xcode for day-to-day work (⌘R run, ⌘U test). Always leave the
tree building without warnings and with all tests passing. The Xcode project uses a
file-system synchronized group, so new files under `Tickoff/` and `TickoffTests/` are picked
up automatically; do not hand-edit `project.pbxproj` to add them.

## Branching

Work is tracked as GitHub issues. When you start implementing an issue, create a new
branch for it before making any change; never implement an issue directly on `main`.

- Branch from an up-to-date `main`.
- Name it after the issue: `issue-<number>-<short-slug>`, e.g. `issue-2-projects-schema`.
- One issue per branch. Commit and push only when asked.

## Daily notes

After finishing every task, write a small summary to `brain/daily-notes/dd-mm-yyyy.md`
(today's date, e.g. `brain/daily-notes/26-10-2026.md`). Always do this, even for small tasks.

- One file per day. If it already exists, append a new entry; never overwrite earlier ones.
- Each entry is a few lines: what was asked, what changed (files or areas), and anything
  left open or worth knowing next time. Keep it short.
- Create `brain/daily-notes/` if it is missing.

## Architecture

The app is split into three layers with strict dependency rules:

```
Tickoff/
  App/                 # the SHELL: owns the database + TaskSet, lays out the window,
                       # routes menu commands and feature Outcomes. No feature logic here.
    TickoffApp.swift       entry point, scenes (main window, Settings), app delegate
    AppModel.swift         database, TaskStore, SettingsModel, TaskSet, error banner state
    ContentView.swift      NavigationSplitView, edit sheet, menu-command routing
    AppCommands.swift      menu bar commands (New Task, Find, About)
    ErrorBanner.swift
  Features/            # one folder per feature; UI + state + calls to a store
    AddTask/  EditTask/  Filters/  Settings/  TaskList/
  Shared/              # cross-cutting building blocks used by 2+ features
    AppDatabase.swift      opens the database and runs migrations
    TaskStore.swift        the ONE place that talks SQL about the `tasks` table
    Task.swift             Task, Status, Priority domain types
    TaskSet.swift          loaded tasks plus cached search keys and counts
    Outcome.swift          what a feature reports back to the shell
    Theme.swift            appearance preferences, accent colours, text scaling
  Resources/           # asset catalog
TickoffTests/          # Swift Testing suites, one per type under test
packaging/macos/       # release.sh, make_icon.swift
```

### Dependency rules (the guard rails)

1. **Features never import each other.** Each feature talks only to `Shared/` and receives
   what it needs as arguments. If two features must coordinate, the shell wires them
   together, e.g. `TaskListView`'s `edit` closure sets `editing` in `ContentView`, which
   presents `EditTaskView`. Menu commands reach features through `AppActions` (a focused
   value) plus request counters that the feature observes with `onChange`.
2. **The shell contains no feature logic.** `AppModel` and `ContentView` own the database
   and the loaded `TaskSet`, lay out the sidebar and detail, and route commands and
   outcomes. Behaviour belongs in the feature that owns it.
3. **`Shared/` stays small.** Something moves there only when two or more features
   genuinely need it. Everything else lives inside the feature that uses it.
4. **SQL for a table lives in exactly one type.** The `tasks` table is owned by
   `Shared/TaskStore.swift`; the `settings` table by `Features/Settings/SettingsStore.swift`.
   Never inline SQL elsewhere. Always use parameterised SQL (`arguments:` / `?`), never
   string interpolation.

### Data flow

- Features are SwiftUI views that take the data they need as arguments (the `TaskSet`, a
  store, a `report` closure) and call a store in direct response to a user action.
- `Outcome` (`Shared/Outcome.swift`) has two cases: `.changed` (the shell reloads tasks and
  clears the error banner) and `.failed(String)` (the shell shows the message). Wrap store
  calls in `Outcome.run { try store.… }`.
- The shell reacts via `AppModel.handle(_:)` (reload the tasks) or `report(_:)` (no reload
  needed, e.g. settings). Features never reload or hold task data themselves; the shell's
  `TaskSet` is the single source of truth, passed down by reference.
- Errors surface through the error banner. Never use `try!`, `fatalError` or force-unwraps
  on database or runtime failures (tests may use them freely).
- Models are `@MainActor @Observable`. Swift 6 strict concurrency is on; keep it warning-free.

### Performance

SwiftUI re-evaluates view bodies often, so never do work per body evaluation that can be
done once per change:

- Derived data (search keys, counts) is computed in `TaskSet.replace` at load time and
  cached; caches key on `TaskSet.revision`, which bumps on every reload (see `VisibleCache`
  in `TaskListView`).
- Follow this pattern for anything new: compute on change, cache keyed on revision, read
  cheaply in `body`.
- The task list is a `List` so rows are recycled; it must stay smooth with 10,000+ tasks.
- No database queries in `body` except in direct response to a user action.

### Database and migrations

- The data file is `~/.hello_gui/tasks.db`, shared with the Rust-era app: tables `tasks`
  and `settings`, status and priority as integer codes, due as `YYYY-MM-DD` or `''`,
  settings keys `theme_mode`, `accent`, `ui_scale`, `compact_cards`, `show_notes`.
- The schema lives in `AppDatabase.migrator` (GRDB `DatabaseMigrator`). `v1` uses
  `CREATE TABLE IF NOT EXISTS` so an existing file is adopted untouched. Add new
  migrations as new `registerMigration` entries; they must be additive and
  backward-compatible. Never rename or drop a column, and never change what an existing
  code means: an older database file must never prevent the app from starting.
- Settings follow the same rule: missing or unrecognised values fall back to defaults
  (see `SettingsStore`). Multi-statement writes go in one transaction.
- Enum columns map through explicit `dbValue` / `init(dbValue:)` conversions on the domain
  types in `Shared/Task.swift`; never store or match raw integers elsewhere.

### Theming and UI

- Never hard-code colours in features. Use semantic styles (`.primary`, `.secondary`,
  `.tint`) and the helpers in `Theme.swift` so the active light/dark theme and accent
  apply automatically. Note `.tint` follows the chosen accent; `Color.accentColor` does not.
- Text size goes through `Appearance.font(_:weight:)` so the Text size setting applies.
- Reusable visual pieces live next to the feature that uses them until a second feature
  needs them.
- The window has a hidden title bar (`.windowStyle(.hiddenTitleBar)`) and a single
  `Window` scene. Don't break dragging, the sidebar inset or the traffic lights when
  touching the layout.
- Menu commands live in `AppCommands`; features only ever see `AppActions`.

## Testing

- Tests use Swift Testing (`import Testing`, `@Test`, `#expect`) in `TickoffTests/`, one
  suite per type under test.
- Database tests use `try AppDatabase()` (in-memory) and seed rows through the store or
  `queue.write`. No test touches the real `~/.hello_gui/tasks.db`; when the hosted tests
  launch the app it detects `XCTestConfigurationFilePath` and uses an in-memory database.
- Test names describe behaviour in a full sentence, e.g.
  `clearCompletedOnlyRemovesDoneTasks`.
- New SQL functions and non-trivial derived-data logic need tests; pure UI layout does not.
- Never drive the UI with synthetic clicks or keystrokes to verify it; that can hit other
  apps. Take window-only screenshots instead.

## Style

- Every file starts with a `///` doc comment on its main type saying what it is and where
  its boundary lies. Non-obvious members get a one-line `///`.
- Comments explain *why* or a constraint the code can't show, not what the next line does.
- Match the existing code's density and idiom; prefer small focused types and functions and
  the existing enum-with-`label` / `CaseIterable` pattern for user-selectable options.
- Keep dependencies minimal: adding a package is an architectural decision, not a
  convenience.
