# Version Report

## Overview

Version Report is a native macOS release-monitoring tool for Mac
administrators. It tracks the latest stable releases for a configurable set of
applications and notifies administrators when a vendor publishes an update. It
checks vendor-maintained sources such as Homebrew's API, Sparkle appcasts, GitHub
Releases, Apple's App Store lookup API, vendor JSON endpoints, and release-notes
pages.

It also reads the versions of tracked apps installed on the Mac it runs on, so
it can show which installed copies are out of date. It never changes or updates
installed apps.

## Key Features

-   Monitor configurable applications, from a built-in library of 100 apps or
    added by hand
-   Native macOS notifications and an optional Microsoft Teams webhook
-   Keychain storage for the webhook URL
-   Groups and smart groups (by source, vendor, update status, update cycle,
    installed version, and check dates)
-   Release history per app, and alerts for apps that go quiet well past their
    usual update cycle
-   Installed Version column and an offer at launch to track installed apps
    from the built-in library
-   Sources: Homebrew casks, Sparkle feeds, GitHub Releases, the App Store, and
    custom URLs with the `jq`, `jq_trim_comma`, `regex`, and `highest_version`
    parsers
-   In-app updates through Sparkle

## Data Files

Application Support folder:

`~/Library/Application Support/Version Report/`

Contents:

-   `apps.json`: the apps being tracked
-   `app-library.json`: the user's library, seeded from the built-in library
-   `app-state.json`: current and previous version, check times, and errors
-   `release-history.json`: known releases per app
-   `groups.json` and `smart-groups.json`
-   `bundled-icons.json`: fingerprints of built-in icons copied into `icons/`
-   `icons/`: one PNG per app, named by app ID
-   `logs/`

## Architecture

-   `Version_ReportApp.swift`: app entry point, commands, Sparkle updater
-   `ContentView.swift`: main window and table
-   `VersionReportService.swift`: update engine, persistence, library merging
-   `ReleaseHistory.swift`: release history and update cycles
-   `InstalledApps.swift`: installed-app lookup and version comparison
-   `SettingsView.swift`: preferences
-   `KeychainHelper.swift`: secure storage

See [Architecture.md](Architecture.md) for details.

## Library and Icons

The bundled library adds new apps to the user's library and fills in fields the
user never set, but never overwrites an entry the user already has. Add from
Library always uses the bundled definition for built-in apps, so re-adding an
app picks up lookup fixes. Bundled icons replace an icon only if the user hasn't
changed it.

## Notifications

-   Native macOS notifications
-   Microsoft Teams Adaptive Card notifications (optional)

## Documentation

-   [Architecture.md](Architecture.md)
-   [Adding Apps.md](Adding%20Apps.md)
-   [Parser Reference.md](Parser%20Reference.md)
-   [Release Process.md](Release%20Process.md)
-   [xcode-security-settings.md](xcode-security-settings.md): security build
    settings and entitlements, and why each is on or off
