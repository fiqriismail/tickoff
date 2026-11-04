---
title: Troubleshooting
description: Resolve first-launch, missing-task, daily-goal and local database problems.
---

## macOS blocks the first launch

Tickoff is ad-hoc signed but is not signed with an Apple Developer ID or
notarised. Only approve a copy you downloaded from the
[official Tickoff releases](https://github.com/fiqriismail/tickoff/releases).

1. In Finder, open **Applications**.
2. Control-click **Tickoff.app**, choose **Open**, and confirm if macOS offers
   that option.
3. If it is still blocked, open **System Settings > Privacy & Security** after
   attempting to launch the app. Look for the Tickoff warning and choose
   **Open Anyway**, then follow the confirmation prompts.

The exact wording and available controls vary by macOS version. On managed Macs,
your organisation may restrict these options.

## Check your macOS version

Tickoff requires **macOS 14 Sonoma or later**. Choose **Apple menu > About This
Mac** to check your version. The universal download runs on both Apple Silicon
and Intel Macs.

## A task seems to be missing

Clear the task search, select **All Tasks** in Library, then **All Projects**.
Status filters and search are applied inside the selected project scope.
Archived projects are hidden from the sidebar but their tasks still appear
under All Projects. Daily Goals do not appear in task searches.

If a task or Tasks project was deleted, there is no app-level recovery. See
[restoring a backup](../data-and-backups/#restore-a-backup).

## Today's goal or target looks unchanged

Goal edits apply tomorrow, not immediately. A row can show **Changes scheduled
for tomorrow** while retaining today's name, tracking style and target.

If the date has changed, bring Tickoff to the foreground. It checks the local
day on activation and periodically while running. Confirm your Mac's date and
time zone in System Settings if the day still seems wrong. See
[Daily Goals](../../guide/daily-goals/#a-fresh-local-day).

## The app shows a database error

Read and note the error banner. Do not delete the database or journal files.
If startup says **Couldn't open your tasks database**, the app is running with a
temporary, in-memory database. Anything entered in that session is not saved to
your normal database and is lost when you quit. Copy any important new text to a
separate safe place before quitting.

Before attempting repair or replacement:

1. Quit all Tickoff instances and any database tools.
2. [Back up the complete data folder](../data-and-backups/#make-a-safe-backup).
3. Check that your disk has free space and your user can access `~/.hello_gui/`.
4. Reopen Tickoff. If the error continues, report its wording and your app/macOS
   versions without uploading your database.

Dismissal of an error banner is not confirmation that the underlying problem
has been repaired.

## A menu command is disabled

New Task, Find Tasks, task display options and Clear Completed apply to Tasks
views, not Daily Goals. New Goal requires a Daily Goals project. Task and Goal
edit commands require a relevant row selection; Clear Completed requires Done
tasks in the selected scope.

See [Keyboard shortcuts](../../guide/keyboard-shortcuts/) for command availability.

## Report a problem

If you still need help, [open a GitHub issue](https://github.com/fiqriismail/tickoff/issues/new).
Include your macOS version, Tickoff version and the steps that reproduce the
problem. You can find the app version in **Tickoff > About Tickoff**.

Do not attach your task database or screenshots containing private information.

[Return to Getting started](../../guide/getting-started/).
