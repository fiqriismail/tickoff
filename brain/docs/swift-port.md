# Native Swift port

Priority 1. Tracked by the GitHub milestone **Native Swift port** (epic #11). The
Projects milestone (epic #1) is priority 2, deferred until the port is done, and its
issues have been rewritten for the Swift code.

**Status: complete** (#12 to #20 merged). `README.md` and `AGENTS.md` describe the final code.

## Why

The app is macOS-only in practice, and about half the Rust code works around things
macOS gives for free: the menu bar (`menu.rs`), theming (`theme.rs`), the hidden title
bar and dragging, and per-frame caching for an immediate-mode UI. SwiftUI brings native
controls and text editing, accessibility, lower idle CPU and a smaller app. We give up
Windows and Linux builds, which were never tested anyway.

## Decisions (27-10-2026)

| Topic | Choice | Reason |
|---|---|---|
| UI | SwiftUI, macOS 14+ | `@Observable`, Swift Testing, modern SwiftUI |
| Storage | GRDB via SPM | Opens the existing SQLite file unchanged; explicit SQL and migrations |
| Repo | Replace in place | Tag the last Rust commit, delete the crate, Xcode project at the root |
| Projects | Deferred, built on Swift | Avoids building it twice |

## Data contract (must not change)

- File: `~/.hello_gui/tasks.db`.
- `tasks(id, title, notes, priority, status, due, created_at)`: status 0 to do, 1 in
  progress, 2 done; priority 0 low, 1 medium, 2 high; `due` is `YYYY-MM-DD` or `''`.
  Unknown status falls back to To do, unknown priority to Medium.
- `settings(key, value)`: `theme_mode` light/dark/system, `accent`
  indigo/violet/teal/rose/orange, `ui_scale` small/default/large, `compact_cards` and
  `show_notes` `"true"`/`"false"`. Missing or unknown values use the defaults (System,
  Indigo, Default, false, true).
- Task order: open first, then priority high to low, then due date (undated last), then
  newest first.
- GRDB's migrator registers the original schema as `v1` with `CREATE TABLE IF NOT EXISTS`,
  so Rust-era files adopt it without changes. Projects adds `v2`.

## How the code maps

| Rust | Swift |
|---|---|
| `main.rs`, `app.rs` | `TickoffApp.swift`, `App/AppModel.swift`, `App/ContentView.swift` |
| `menu.rs` (muda) | `App/AppCommands.swift` (`.commands`) |
| `shared/db.rs` | `Shared/AppDatabase.swift` |
| `shared/tasks.rs`, `shared/task.rs` | `Shared/TaskStore.swift`, `Shared/Task.swift` |
| `shared/outcome.rs` | `Shared/Outcome.swift` |
| `shared/theme.rs` | `Shared/Theme.swift` + asset catalog colours |
| `features/settings/store.rs` | `Features/Settings/SettingsStore.swift` |
| `features/*` | `Features/*` (one folder per feature) |
| `packaging/macos/bundle.sh` | `packaging/macos/release.sh` (xcodebuild archive) |

## Issues

#12 scaffold → #13 data layer → #14 settings and theme → #15 shell and sidebar →
#16 task list → #17 add/edit → #18 menu and About → #20 docs. Packaging (#19) only
needs #12.

## Risks

- Reading a real Rust-era database: #13 includes a test with a Rust-schema file.
- Performance with 10,000+ tasks in a SwiftUI `List`: check with a seeded database in #16.
- Losing the working Rust app mid-port: mitigated by the tag made in #12.
