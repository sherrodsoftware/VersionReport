# Adding Apps

This guide describes the preferred process for adding a new application
to Version Report.

## Workflow

1.  Identify the best version source.
2.  Test the source in Version Report (Look Up or Test Parser).
3.  Verify against the application's About window.
4.  Add the entry to `Version Report/Resources/app-library.json`, with its
    vendor and bundle ID.
5.  Add a 128×128 icon to `Version Report/Resources/icons/`, named by app ID.
6.  Run `python3 scripts/generate-library-md.py` to update `LIBRARY.md`.
7.  Build and run the tests.

------------------------------------------------------------------------

## Preferred Version Sources

### 1. Homebrew Casks (Preferred)

Use the Homebrew Cask source with the cask name:

``` json
{ "sourceType": "homebrew", "caskName": "firefox" }
```

Version Report reads `https://formulae.brew.sh/api/cask/<name>.json`. Use it
whenever a maintained cask exists.

### Sparkle Feeds and GitHub Releases

Apps that update through Sparkle can use their appcast URL
(`"sourceType": "sparkle", "feedURL": ...`). Apps that publish GitHub releases
can use `"sourceType": "github", "repoPath": "owner/repo"`, but check that the
repository's latest release is the app itself: some repositories publish
releases for other tools, or leave the latest-release marker on an old version.

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

Use the App Store source. Searching in the Add App window creates a lookup URL
such as:

    https://itunes.apple.com/lookup?id=1435415804&entity=macSoftware

with the `jq` parser and `.results.0.version`. The lookup also provides the
app's bundle ID and its developer.

------------------------------------------------------------------------

## Choosing a Parser

## Application IDs

Every library entry needs a stable, readable lowercase ID using underscores.
For example:

    "id": "google_chrome"

Built-in entries also need a `vendor` and a `bundleId`; a test fails if a
built-in entry has no bundle ID or two share one. Confirm a bundle ID with:

    osascript -e 'id of app "Google Chrome"'

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

Edit `Version Report/Resources/app-library.json` directly; it's the single
shipping catalog.

On launch, Version Report adds new bundled entries to each user's library and
fills in fields the user never set, but doesn't overwrite existing entries.
Add from Library always uses the bundled definition, so a fix reaches anyone who
removes and re-adds the app.

------------------------------------------------------------------------

## Parser Philosophy

The goal is not simply to extract a version.

The goal is to select the most stable, maintainable source available.

Preferred order:

1.  Homebrew casks
2.  Vendor JSON
3.  Vendor release notes
4.  Apple App Store lookup
5.  Other HTML sources
