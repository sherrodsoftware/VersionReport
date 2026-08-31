# Version Report

## Overview

Version Report is a native macOS release-monitoring tool for Mac
administrators. It tracks the latest stable releases for a configurable
set of managed applications and notifies administrators when a vendor
publishes an update. It checks vendor-maintained sources such as Homebrew
APIs, vendor JSON endpoints, release notes, and selected Mac App Store
pages; it does not inspect applications installed on the local Mac.

## Key Features

-   Monitor configurable applications
-   Native macOS update notifications
-   Microsoft Teams webhook notifications (optional)
-   Secure Keychain storage for webhook URLs
-   Reusable application library
-   Automatic library and icon synchronization
-   Multiple parser types: jq, jq_trim_comma, regex, highest_version

## Data Files

Application Support folder:

`~/Library/Application Support/Version Report/`

Contents:

-   apps.json
-   app-library.json
-   app-state.json
-   Icons/

## Architecture

-   Version_ReportApp.swift --- app entry point
-   ContentView.swift --- primary interface
-   VersionReportService.swift --- update engine
-   SettingsView.swift --- preferences
-   KeychainHelper.swift --- secure storage

## Source Families

-   Homebrew casks
-   Homebrew formulas
-   Vendor JSON APIs
-   Vendor release notes
-   Apple App Store pages

## Deployment

Bundled app-library.json updates matching user entries while preserving
user-created entries. Bundled icons replace matching deployed icons
while leaving user-only icons untouched.

## Notifications

-   Native macOS notifications
-   Microsoft Teams Adaptive Card notifications (optional)

## Planned Documentation

-   Architecture.md
-   Adding Apps.md
-   Parser Reference.md
-   Release Process.md
-   Roadmap.md
