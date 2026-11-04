---
title: FAQ
description: Answers about supported Macs, privacy, Daily Goals and current Tickoff limitations.
---

## Which Macs are supported?

Tickoff requires **macOS 14 Sonoma or later**. The universal release runs on
Apple Silicon and Intel Macs. The current native app does not support Windows,
Linux, iPhone or iPad.

## Do I need an account or internet connection?

No account is needed. The app stores data locally and makes no network requests.
Downloading the app and viewing this website require a connection; everyday
task and goal tracking do not.

## Does Tickoff sync between computers?

No. There is no built-in cloud sync or shared-project collaboration.
Do not treat copying a live database through a sync service as a supported sync
workflow. See [safe backups](../data-and-backups/).

## Is the app signed?

Releases are ad-hoc signed, not Apple Developer ID signed or notarised.
macOS may require [first-launch approval](../troubleshooting/#macos-blocks-the-first-launch).
Download only from the official GitHub releases.

## Can I set reminders or recurring tasks?

Task due dates are dates, not scheduled notifications. There is no timed reminder
feature. Use a [Daily Goals project](../../guide/daily-goals/) for check-offs or
counters that start fresh each day; it is separate from ordinary tasks.

## Can I convert a project to Daily Goals?

No. Choose the type when creating a project. Existing Tasks projects cannot
be converted, and tasks cannot be moved into Daily Goals projects.

## Where are yesterday's goals, streaks and charts?

This version shows Today only. Recorded progress is kept in the database, but
there is no history browser, streak tracking or chart view. Goal edits apply
tomorrow; they do not change today's definition or older recorded results.

## Can I undo deletion or restore an archived project?

There is no app-level undo/Trash for deleted tasks and no archived-project
browser or restoration command. Removing goals and deleting Daily Goals projects
preserve recorded history, but do not provide an in-app recovery workflow.
See [Projects](../../guide/projects/) and [Data and backups](../data-and-backups/).

## Where are the app's settings?

Display options are in the task toolbar More menu and the View menu.
Appearance follows macOS. See [Appearance and display](../../guide/appearance/).

## How do I report a bug?

Use the [troubleshooting guide](../troubleshooting/#report-a-problem) and include
reproduction steps without sharing private task data.
