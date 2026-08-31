# Adding Apps

This guide describes the preferred process for adding a new application
to Version Report.

## Workflow

1.  Identify the best version source.
2.  Test the parser in Version Report.
3.  Add the application to the library.
4.  Verify against the application's About window.
5.  Update the bundled `app-library.json`.
6.  Build and test.

------------------------------------------------------------------------

## Preferred Version Sources

### 1. Homebrew Casks (Preferred)

Example API:

    https://formulae.brew.sh/api/cask/firefox.json

Parser:

-   Type: `jq_trim_comma`
-   Value: `.version`

Use whenever a maintained cask exists.

------------------------------------------------------------------------

### 2. Homebrew Formulas

Example:

    https://formulae.brew.sh/api/formula/handbrake.json

Parser depends on the JSON structure.

------------------------------------------------------------------------

### 3. Vendor JSON APIs

Examples:

-   Granola
-   BrowserStackLocal

Prefer JSON over HTML whenever possible.

------------------------------------------------------------------------

### 4. Vendor Release Notes

Examples:

-   Downie
-   EditReady
-   Pro Tools
-   Adobe Photoshop

Typically use a targeted `regex` parser anchored to product-specific
text.

Avoid broad version matching.

------------------------------------------------------------------------

### 5. Apple App Store

Use the Mac App Store web page:

    https://apps.apple.com/... ?platform=mac

Current parser pattern:

    primarySubtitle":"Version [0-9]+(\.[0-9]+)+"

This has proven more accurate than Apple's lookup API.

------------------------------------------------------------------------

## Choosing a Parser

## Application IDs

Every library entry needs a stable, readable lowercase ID using underscores.
For example:

    "id": "google_chrome"

The ID must remain unchanged if the application's display name changes. Use it
for the matching icon filename, such as `icons/google_chrome.png`.

### jq

Use when the JSON value is returned exactly.

### jq_trim_comma

Use when Homebrew returns version strings like:

    1.2.3,abcdef

and only the version is needed.

### regex

Preferred for release-note pages.

Anchor the expression to product-specific text whenever possible.

### highest_version

Useful for release-history pages containing many releases.

Avoid on noisy pages that contain unrelated version numbers.

------------------------------------------------------------------------

## Validation Checklist

Before adding an app:

-   Confirm the source is official when practical.
-   Verify Test Parser output.
-   Compare against the application's About window.
-   Ensure the parser survives minor page changes.

------------------------------------------------------------------------

## Deployment

After modifying the library:

1.  Update the Application Support copy while testing.
2.  Copy the finished `app-library.json` into the Xcode Resources
    folder.
3.  Build Version Report.

On launch, Version Report updates matching user library entries
automatically while preserving user-created entries.

------------------------------------------------------------------------

## Parser Philosophy

The goal is not simply to extract a version.

The goal is to select the most stable, maintainable source available.

Preferred order:

1.  Homebrew JSON
2.  Vendor JSON
3.  Vendor release notes
4.  Apple App Store page
5.  Other HTML sources
