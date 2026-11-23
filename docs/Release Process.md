# Release Process

Version Report ships as a Developer ID signed, notarized installer package on
GitHub Releases. Installed copies update themselves through Sparkle, using the
appcast at `https://www.sherrodsoftware.com/versionreport/appcast.xml`, which
lives in the website repository at `public/versionreport/appcast.xml`.

## Source Control

The project is tracked in Git on the `main` branch and pushed to GitHub. Commit
after each working change, and before a risky one, with a short message that
describes the result. Don't commit secrets, build output, Finder metadata, or
personal Xcode state.

Keep `CHANGELOG.md` current: add each user-visible change to the Unreleased
section as it lands, and rename that section to the version when releasing.

## Version Numbers

-   **Version** (`MARKETING_VERSION`): the release date, `YYYY.MM.DD`.
-   **Build** (`CURRENT_PROJECT_VERSION`): `YYYYMMDDNN`, where `NN` counts the
    builds that day.

Sparkle compares build numbers, so every release needs a build number higher
than the one in the live appcast. Bump both in Xcode and commit before building.

## Before Building

-   Verify parser changes with **Test Parser**, and compare reported versions
    with the application's About window.
-   After changing `Version Report/Resources/app-library.json`, run
    `python3 scripts/generate-library-md.py` to update `LIBRARY.md`. A test
    fails if it's out of date, or if a built-in app is missing a bundle ID.
-   Put new or updated icons in `Version Report/Resources/icons/`, named by app
    ID, at 128×128.
-   Run the tests.

## Build

```sh
scripts/release.sh            # a normal release
scripts/release.sh --hotfix   # a new build for an existing release
```

The script runs the tests, archives the Release configuration, exports it with
Developer ID, checks the signature, team, and hardened runtime, and refuses to
continue if the build number isn't higher than the live appcast's. It then
builds and signs the package, notarizes and staples it, signs it for Sparkle,
and prints the appcast item. `--skip-tests` and `--skip-notarize` skip those
steps.

Packages are written to `dist/` (which isn't tracked):

-   Release: `Version Report <version>.pkg` (GitHub names it
    `Version.Report.<version>.pkg`)
-   Hotfix: `VersionReport-<version>-build<build>.pkg`, replacing the package on
    the existing release

## Deployment

1.  Create a GitHub release tagged `v<version>` (or edit the existing release
    for a hotfix) and upload the package.
2.  Replace the item in the website's `public/versionreport/appcast.xml` with
    the one the script printed, and commit it. Cloudflare deploys the site from
    `main`; check that its build passes, and re-run it if it fails.
3.  Add the release notes from `CHANGELOG.md`.

On first launch, the new build:

-   Adds new bundled library entries and fills in fields the user never set,
    without overwriting user entries.
-   Updates bundled icons the user hasn't changed.
-   Keeps the user's monitored apps, state, groups, and history.

## Post-Deployment Validation

-   Confirm the appcast is live with the new build number, and that its
    download URL returns the package with the expected size.
-   Use Version Report → Check for Updates… on a Mac with the previous version.
-   Confirm monitored apps, parser updates, and icon updates.
-   Run Check Versions Now, and verify Teams notifications if configured.
