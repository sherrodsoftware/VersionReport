# Version Report Project Guidance

Use the documentation in `docs/` as the authoritative product context for work in this project.

- Start with `docs/README.md` for the product overview.
- Read `docs/Architecture.md` before changing application structure, persistence, synchronization, notifications, or core service behavior.
- Read `docs/Adding Apps.md` and `docs/Parser Reference.md` before adding or changing an application source or parser.
- Read `docs/Release Process.md` for build, packaging, deployment, and release work.
- Consult `docs/Roadmap.md` when discussing priorities or proposed features. It's private and not in the repository, so it may not exist.
- Keep `CHANGELOG.md`'s Unreleased section current as user-visible changes land. Build releases with `scripts/release.sh`.

Preserve these established design decisions unless the user explicitly asks to change them:

- `VersionReportService.swift` owns almost all application logic; views should contain little business logic.
- `AppUIState.swift` contains transient UI state, not persistent application data.
- The bundled app library adds new entries and fills in fields the user never set (vendor, bundle ID), but never overwrites a user's library entry, tracked app, or custom icon. Add from Library always offers the bundled definition of a built-in app, and bundled icons replace only icons the user hasn't changed.
- Secrets such as the Microsoft Teams webhook URL belong in Keychain, not JSON or UserDefaults.
- Prefer stable version sources in this order: Homebrew casks, vendor JSON, vendor release notes, the Apple App Store lookup, then other HTML sources.
- Built-in library entries need a vendor and a unique bundle ID, and `LIBRARY.md` is regenerated with `scripts/generate-library-md.py` after library changes.
- Prefer targeted, product-specific parsing over broad version matching.
