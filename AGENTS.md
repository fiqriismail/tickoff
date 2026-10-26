# AGENTS.md

Tickoff is a native macOS task manager built in Rust with eframe/egui (immediate-mode GUI)
and a local SQLite database (rusqlite, bundled). This file is the contract for any coding
agent working in this repository: follow the architecture below, and when in doubt, copy
the patterns already in the code rather than inventing new ones.

## Commands

```sh
cargo check          # fast validation while iterating
cargo test           # unit tests (in-memory SQLite, no app window needed)
cargo fmt            # required before finishing any change
cargo clippy         # keep it warning-free
cargo run            # launch the app
./packaging/macos/bundle.sh # build the .app bundle for releases
```

Always leave the tree with `cargo fmt` applied and `cargo test` passing.

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
src/
  main.rs            # eframe entry point and window options only
  app.rs             # the SHELL: owns the Connection + TaskSet, lays out panels,
                     # routes menu Commands and feature Outcomes. No feature logic here.
  menu.rs            # macOS menu bar (muda); emits Command values the shell runs
  features/          # one module per feature; UI + state + SQL calls for that feature
    add_task.rs
    edit_task.rs
    filters.rs
    task_list/       # larger features become folders (mod.rs + submodules like card.rs)
    settings/        # settings/store.rs owns SQL for the `settings` table
  shared/            # cross-cutting building blocks used by 2+ features
    db.rs            # opens the database and runs migrations
    tasks.rs         # the ONE place that talks SQL about the `tasks` table, plus TaskSet
    task.rs          # Task, Priority, Status domain types
    outcome.rs       # Outcome: what a feature reports back to the shell
    theme.rs         # appearance preferences, palette, egui style setup
    icons.rs, widgets.rs
```

### Dependency rules (the guard rails)

1. **Features never import other features.** Each feature talks only to `shared/` and
   receives what it needs as arguments. If two features must coordinate, the shell
   (`app.rs`) wires them together — see how `task_list::Event::Edit(task)` is routed to
   `edit_task.open(task)` in `app.rs`.
2. **The shell contains no feature logic.** `app.rs` owns the `Connection` and the loaded
   `TaskSet`, lays out the sidebar/central panels, and routes commands and outcomes.
   Behaviour belongs in the feature that owns it.
3. **`shared/` stays small.** Something moves there only when two or more features
   genuinely need it. Everything else lives inside the feature that uses it.
4. **SQL for a table lives in exactly one module.** The `tasks` table is owned by
   `shared/tasks.rs`; the `settings` table by `features/settings/store.rs`. Never inline
   SQL elsewhere. Always use parameterised queries (`params![...]`), never string
   interpolation.

### Data flow

- Features expose a `show(&mut self, ui, &Connection, ...)` method called every frame and
  return `Option<Outcome>` (or a richer event enum like `task_list::Event` when the shell
  must do more than reload).
- `Outcome` (`shared/outcome.rs`) has two variants: `Changed` (shell reloads tasks and
  clears the error banner) and `Failed(String)` (shell shows the message). A
  `rusqlite::Result` converts into it with `.into()`.
- The shell reacts via `handle(outcome)` (reload the tasks) or `report(outcome)` (no
  reload needed, e.g. settings). Features never reload or hold task data themselves;
  the shell's `TaskSet` is the single source of truth, passed down by reference.
- Errors surface through the error banner, never `unwrap()`/`expect()`/`panic!` on
  database or runtime failures (tests may unwrap freely).

### Immediate-mode performance

egui redraws every frame, so never do per-frame work that can be done once per change:

- Derived data (search keys, counts) is computed in `TaskSet::replace` at load time and
  cached; caches key on `TaskSet::revision()`, which bumps on every reload.
- Follow this pattern for anything new: compute on change, cache keyed on revision,
  read cheaply in `show`.
- No database queries inside the per-frame draw path except in direct response to a user
  action (click, submit).

### Database and migrations

- The schema lives in `shared/db.rs::migrate` and runs on every open with
  `CREATE TABLE IF NOT EXISTS`. Schema changes must be additive and backward-compatible:
  an older database file must never prevent the app from starting.
- Settings follow the same rule: missing or unrecognised values fall back to defaults
  (see `settings/store.rs`). Multi-statement writes go in one transaction.
- Enum columns map through explicit `to_db()`/`from_db()` methods on the domain types in
  `shared/task.rs` — never store or match raw integers elsewhere.

### Theming and UI

- Never hard-code colours in features. Read them with `theme::palette(ui.ctx())` so the
  active light/dark theme and accent colour apply automatically.
- Reusable visual pieces (buttons, etc.) live in `shared/widgets.rs`; layout constants are
  named `const`s with a doc comment saying what they align with.
- The window has a hidden native title bar; dragging/zoom is handled by
  `title_bar_drag_area` in `app.rs`, and the sidebar insets around the macOS traffic
  lights. Don't break these when touching the layout.
- macOS-specific code (the `muda` menu) stays behind `cfg(target_os = "macos")` and the
  `menu.rs` boundary; features only ever see `Command` values.

## Testing

- Tests are inline `#[cfg(test)] mod tests` blocks next to the code they cover.
- Database tests use `db::open_in_memory()` (already defined, test-only) and may seed
  rows with `execute_batch`. No test touches the real `~/.hello_gui/tasks.db`.
- Test names describe behaviour in a full sentence, e.g.
  `clear_completed_only_removes_done_tasks`.
- New SQL functions and non-trivial derived-data logic need tests; pure UI layout does not.

## Style

- Every module starts with a `//!` doc comment saying what it is and where its boundary
  lies. Public items that aren't self-evident get a one-line `///`.
- Comments explain *why* or a constraint the code can't show — not what the next line does.
- Match the existing code's density and idiom; prefer small focused functions and the
  existing enum-with-`label()`/`key()`/`ALL` pattern for user-selectable options.
- Keep dependencies minimal: adding a crate is an architectural decision, not a convenience.
