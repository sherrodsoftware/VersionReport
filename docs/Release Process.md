# Release Process

## Source Control Workflow

The Xcode project is tracked in Git on the `main` branch and synchronized
with the GitLab `origin` remote.

Create a commit after completing a useful, working change, such as a feature,
bug fix, parser update, or application-library update. Also create a commit
before beginning a risky change so there is a known checkpoint to return to.

From the repository root, review, stage, commit, and upload changes with:

```sh
git status
git add -A
git commit -m "Describe the completed change"
git push
```

-   `git status` reviews changed, added, and deleted files.
-   `git add -A` selects those changes for the next commit while respecting
    `.gitignore`.
-   `git commit` creates a recoverable checkpoint in the local repository.
-   `git push` synchronizes local commits with GitLab for backup and
    collaboration.

Use a short, specific commit message that describes the completed result.
Do not commit secrets, build output, Finder metadata, or personal Xcode state.

## Before Building

-   Verify all parser changes with **Test Parser**.
-   Compare reported versions with the application's About window.
-   Update
    `~/Library/Application Support/Version Report/app-library.json`.
-   Copy the finalized `app-library.json` into the Xcode Resources
    folder.
-   Replace any updated icons in `Resources/Icons`.
-   Build and verify that library and icon merge behavior works as
    expected.

## Pre-Release Checklist

-   Test automatic version checking.
-   Test local macOS notifications.
-   Test Microsoft Teams notification (if configured).
-   Verify Settings and Keychain functionality.
-   Verify parser changes for affected apps.
-   Confirm no build warnings/errors.

## Build

1.  Clean Build Folder.
2.  Build Release configuration.
3.  Archive/package as appropriate.
4.  Sign with the appropriate identity (Developer ID for production
    distribution).

## Deployment

Deploy via Jamf.

On first launch the new build will:

-   Merge bundled `app-library.json` into the user's library.
-   Preserve user-created library entries.
-   Update bundled icons while preserving user-only icons.
-   Continue using the user's existing monitored app list and state.

## Post-Deployment Validation

-   Launch Version Report.
-   Confirm monitored apps are intact.
-   Confirm parser updates propagated.
-   Confirm icon updates propagated.
-   Run a manual **Check for Updates**.
-   Verify Teams notifications if configured.
