# Architecture

## High-Level Design

Version Report is built around a small number of focused components.
`VersionReportService` owns almost all application logic; views contain little
business logic.

### Version_ReportApp.swift

The application entry point.

-   Creates the shared `VersionReportService` and `AppUIState`.
-   Registers application commands and the Settings window.
-   Starts Sparkle's updater (Version Report → Check for Updates…).

### ContentView.swift

The main window: sidebar, apps table, and detail panel.

-   Displays monitored applications, with optional columns.
-   Handles selection, context menus, copying versions, and sheets.
-   Refreshes installed versions when the app becomes active.

### VersionReportService.swift

The heart of the application.

-   Loading and saving monitored apps, the library, state, and groups.
-   Merging the bundled library and icons into the user's copies.
-   Fetching and parsing remote versions.
-   Running scheduled checks (on launch, hourly, every 6 hours, daily, or manual).
-   Detecting vendors and bundle IDs for newly added apps.
-   Sending macOS notifications, the Dock badge, and Microsoft Teams messages.

### ReleaseHistory.swift

Records each app's known releases in `release-history.json` and works out its
typical update cycle, which drives the overdue alerts.

### InstalledApps.swift

Finds the installed copy of a tracked app, by bundle ID through LaunchServices
or by name in the Applications folders, and compares its version with the
newest available one.

### RunEnvironment.swift

Keeps test runs and profiling launches away from the user's real data. When
Version Report is the unit-test host, or is launched with
`VERSION_REPORT_ISOLATED=1`, it uses a temporary data folder (or
`VERSION_REPORT_DATA_DIR`) and its own defaults domain, and it doesn't start
Sparkle, request notification permission, send notifications or Teams messages,
or show the installed-apps prompt. Tests skip the launch version check;
`VERSION_REPORT_LAUNCH_CHECK=0` or `1` overrides it.

Code that stores service flags or settings uses `RunEnvironment.defaults`
rather than `UserDefaults.standard`.

### AppUIState.swift

Transient UI state only: selected rows, sheet presentation, and dialog state.
Persistent application data is intentionally kept out of `AppUIState`.

### KeychainHelper.swift

Stores the Microsoft Teams webhook URL, so secrets stay out of JSON files and
UserDefaults.

### SettingsView.swift

Check frequency, the installed-apps prompt, and the Microsoft Teams webhook
(save, test, clear).

## Application Support

Version Report stores data in `~/Library/Application Support/Version Report/`:

-   `apps.json`, `app-library.json`, `app-state.json`
-   `release-history.json`, `groups.json`, `smart-groups.json`
-   `bundled-icons.json` and `icons/`
-   `logs/`

## Application IDs and Fields

Each application definition has a stable, readable `id` (for example,
`google_chrome`). The ID, rather than the display name, identifies the
application in the library, monitored-app state, table selection, and icon
lookup. Display names may change without losing observed-version state.

Optional fields:

-   `vendor`: shown in the Vendor column and used by smart groups.
-   `bundleId`: used to find the installed copy (for example, `com.figma.Desktop`).

For both, `nil` means the field was never set and may be filled in from the
bundled library, while an empty string means the user cleared it and it stays
cleared.

## Library Synchronization

On launch:

1.  If the user has no library, the bundled library is copied in.
2.  New bundled entries are added to the user's library.
3.  Existing user entries are never overwritten; only fields the user never set
    (vendor, bundle ID) are filled in from the bundled entry.
4.  Monitored apps get the same fill-in for vendor and bundle ID.
5.  A bundled app whose name matches a monitored app with a different ID and
    source is recorded as a conflict, which the user can review.

Add from Library always offers the bundled definition of a built-in app, so
re-adding an app picks up parser fixes without the merge touching the user's
library file.

## Icon Synchronization

Bundled icons are copied into `icons/` only when no local icon exists, or when
the local icon is still exactly the bundled copy placed there earlier. Each
copy's fingerprint is recorded in `bundled-icons.json`. Icons the user dragged
in are never replaced, while untouched icons still receive bundled updates.

## Update Flow

1.  Load monitored applications.
2.  Fetch each remote version.
3.  Parse the version.
4.  Compare it with `app-state.json`.
5.  Update the state and release history.
6.  Notify the user, and optionally Microsoft Teams.
7.  Fill in release dates from sources that provide them, and alert once for
    apps that have become overdue.

## Sources

-   Homebrew casks (Homebrew's cask API)
-   Sparkle appcasts (version on the enclosure or as item elements)
-   GitHub Releases (latest release)
-   App Store (Apple's lookup API)
-   Custom URLs with a parser: `jq`, `jq_trim_comma`, `regex`, `highest_version`

The architecture is intentionally source-agnostic. New applications are
normally added through `app-library.json` without requiring code changes.
