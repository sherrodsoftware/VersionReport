# Architecture

## High-Level Design

Version Report is built around a small number of focused components.

### Version_ReportApp.swift

The application entry point.

Responsibilities:

-   Creates shared application state.
-   Creates the VersionReportService.
-   Registers application commands.
-   Registers the Settings window.

------------------------------------------------------------------------

### ContentView.swift

The primary user interface.

Responsibilities:

-   Displays monitored applications.
-   Handles selection.
-   Context menus.
-   Copy Version.
-   Refresh and update notifications.

The view itself contains very little business logic.

------------------------------------------------------------------------

### VersionReportService.swift

The heart of the application.

Responsibilities include:

-   Loading and saving monitored apps.
-   Reading and updating app-state.json.
-   Loading and merging app-library.json.
-   Deploying and updating bundled icons.
-   Fetching remote version information.
-   Parsing responses.
-   Running scheduled update checks.
-   Sending local notifications.
-   Sending Microsoft Teams notifications.

Almost all application logic lives here.

------------------------------------------------------------------------

### AppUIState.swift

Stores transient UI state only.

Examples:

-   Selected rows
-   Sheet presentation
-   Dialog state

Persistent application data is intentionally kept out of AppUIState.

------------------------------------------------------------------------

### KeychainHelper.swift

Stores sensitive information securely.

Currently used for:

-   Microsoft Teams webhook URL

This avoids storing secrets in JSON files or UserDefaults.

------------------------------------------------------------------------

### SettingsView.swift

Application preferences.

Current features:

-   Microsoft Teams webhook
-   Test notification
-   Save/Clear webhook

Future notification providers can be added without changing the
application architecture.

## Application Support

Version Report stores data in:

\~/Library/Application Support/Version Report/

Files:

-   apps.json
-   app-library.json
-   app-state.json
-   Icons/

## Library Synchronization

The bundled app-library.json is treated as authoritative.

On launch:

1.  Missing user library created.
2.  Matching bundled entries overwrite matching user entries.
3.  User-only entries remain untouched.

This allows parser improvements to be deployed without deleting user
customizations.

Each application definition has a stable, readable `id` (for example,
`google_chrome`). The ID, rather than the display name, identifies the
application in the library, monitored-app state, table selection, and icon
lookup. Display names may change without losing observed-version state.

## Icon Synchronization

Bundled icons are authoritative.

Matching icons are replaced on launch.

Icons that exist only in the user's Icons folder are preserved.

## Update Flow

1.  Load monitored applications.
2.  Fetch remote version.
3.  Parse version.
4.  Compare against app-state.
5.  Update app-state.
6.  Notify user.
7.  Optionally notify Microsoft Teams.

## Parser Families

-   Homebrew JSON
-   Vendor JSON
-   Vendor release notes
-   Apple App Store
-   Custom regex sources

The architecture is intentionally source-agnostic. New applications are
normally added through app-library.json without requiring code changes.
