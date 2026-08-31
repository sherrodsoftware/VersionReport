# Version Report Project Guidance

Use the documentation in `docs/` as the authoritative product context for work in this project.

- Start with `docs/README.md` for the product overview.
- Read `docs/Architecture.md` before changing application structure, persistence, synchronization, notifications, or core service behavior.
- Read `docs/Adding Apps.md` and `docs/Parser Reference.md` before adding or changing an application source or parser.
- Read `docs/Release Process.md` for build, packaging, deployment, and release work.
- Consult `docs/Roadmap.md` when discussing priorities or proposed features.

Preserve these established design decisions unless the user explicitly asks to change them:

- `VersionReportService.swift` owns almost all application logic; views should contain little business logic.
- `AppUIState.swift` contains transient UI state, not persistent application data.
- The bundled app library and bundled icons are authoritative for matching entries, while user-only entries and icons are preserved.
- Secrets such as the Microsoft Teams webhook URL belong in Keychain, not JSON or UserDefaults.
- Prefer stable version sources in this order: Homebrew JSON, vendor JSON, vendor release notes, Apple App Store pages, then other HTML sources.
- Prefer targeted, product-specific parsing over broad version matching.
