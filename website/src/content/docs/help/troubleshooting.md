---
title: Troubleshooting
description: Resolve installation and first-launch problems with Tickoff.
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

## Report a problem

If you still need help, [open a GitHub issue](https://github.com/fiqriismail/tickoff/issues/new).
Include your macOS version, Tickoff version and the steps that reproduce the
problem. You can find the app version in **Tickoff > About Tickoff**.

Do not attach your task database or screenshots containing private information.

[Return to Getting started](../../guide/getting-started/).
