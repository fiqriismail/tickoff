---
title: Data and backups
description: Find Tickoff's local database and safely back up or restore your tasks, projects and daily goals.
---

## Where your data lives

Tickoff stores tasks, projects, Daily Goals definitions, recorded daily progress
and display options locally in:

```text
~/.hello_gui/tasks.db
```

The folder is created on first launch. The name is retained from the earlier
Rust app. There is no account, cloud sync or built-in backup/export command.

In Finder, choose **Go > Go to Folder** (**Shift-Command-G**) and enter:

```text
~/.hello_gui/
```

The database contains your task titles and notes. Treat it and any copies as
private data; do not attach them to public bug reports.

## Make a safe backup

1. Quit Tickoff with **Command-Q**. Close any other Tickoff instances, older
   Rust builds, or database tools using the same folder.
2. In Finder, open `~/.hello_gui/`.
3. **Copy the entire folder**, rather than moving it, into a dated backup
   location outside the original folder.
4. Verify the copy contains `tasks.db`. If present, keep `tasks.db-wal`,
   `tasks.db-shm` and `tasks.db-journal` with the same copy.
5. Reopen Tickoff after the copy finishes.

:::caution[Do not copy a live database]
SQLite may use journal or write-ahead-log (WAL) sidecar files. Copying only
`tasks.db` while an app is writing can miss recent changes or produce an
inconsistent backup. Do not delete sidecars to make a backup look cleaner.
Quit every process using the database before copying the folder.
:::

The current app does not force a particular journal mode; an existing database
may retain settings from earlier tools or versions. A folder-level, app-closed
backup avoids relying on the absence of sidecars.

## Restore a backup

:::danger[Restoring replaces all current data]
A restore is not a merge. It replaces tasks, projects, daily progress and settings
with the saved copy. Make a separate backup of your current folder first.
:::

1. Quit every Tickoff instance and any tool using its database.
2. Make a dated copy of the current `~/.hello_gui/` folder.
3. Move the current folder aside so it remains available for recovery.
4. Copy the complete backed-up folder into your home directory and name it
   `.hello_gui`. Confirm that `tasks.db` is directly inside it, not in an extra
   nested folder.
5. Keep sidecars from the backup with that backup; **never mix them with
   sidecars from the current database**.
6. Open Tickoff and check the restored tasks and projects.

The app opens the current local day for Daily Goals. Earlier restored progress
remains stored, but only Today is displayed.

## Start fresh without destroying your backup

Quit all database users, make a backup, then move `~/.hello_gui/` to a safe
location outside its original path. On the next normal launch, Tickoff creates
a new folder and empty database with Inbox.

Do not delete your old copy until you are certain you no longer need it.

## Upgrading from an older version

The Swift app uses the same database location as the Rust-era app. Existing tasks
are adopted; adding Projects places older tasks into Inbox, and existing
projects remain Tasks projects when Daily Goals support is added.

Updates preserve existing data when adding support for newer features.
Still, back up before updating, and do not assume an older app understands newer
features or can safely edit them. Prefer the current app for your current data.

See [Troubleshooting](../troubleshooting/) if the app reports a database error.
