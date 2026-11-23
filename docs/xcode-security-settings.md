# Xcode Security Settings

Security build settings decisions for Version Report. Last audited 2026-11-23.

The app is Swift only, ships as a Developer ID signed and notarized package, and
embeds Sparkle as a prebuilt binary package. The C, C++, and Objective-C warning
and analyzer settings therefore have nothing to check and are not tracked here.

## Enabled settings

- `ENABLE_ENHANCED_SECURITY`: set to `YES` on the project, so every target
  inherits it. It turns on stack zero-initialization, the security-relevant
  compiler warnings, and typed allocator support. The app target also carries
  its own `YES`, which is redundant but harmless.
- `ENABLE_HARDENED_RUNTIME`: already on before this audit, and kept.
- Enhanced Security entitlements in `Version Report.entitlements`:
  - `com.apple.security.hardened-process`
  - `com.apple.security.hardened-process.enhanced-security-version-string` = `2`
  - `com.apple.security.hardened-process.hardened-heap`
  - `com.apple.security.hardened-process.dyld-ro`
  - `com.apple.security.hardened-process.platform-restrictions-string` = `2`
- Hardware memory tagging, in soft mode:
  - `com.apple.security.hardened-process.checked-allocations`
  - `com.apple.security.hardened-process.checked-allocations.soft-mode`

  It only takes effect on Macs with an M5 chip or later. In soft mode a memory
  error writes a simulated crash report instead of ending the app. Nobody has
  run it on that hardware yet.

## Disabled settings

- `ENABLE_POINTER_AUTHENTICATION` = `NO` on the app and the unit-test target:
  Enhanced Security would add an arm64e slice, but the Sparkle binary package
  (framework, Updater, Autoupdate, and both XPC services) ships arm64 and x86_64
  only, so an arm64e app can't link it. Turn it back on when Sparkle ships
  arm64e.

## Deferred

- Checked pointer arithmetic (`ENABLE_HARDWARE_CHECKED_POINTER_ARITHMETIC_SLICE`
  and its entitlement): it needs the arm64e slice, which is off for the reason
  above, and it is meant for iPhone and Apple Watch hardware rather than the Mac.
  Revisit with pointer authentication.
- Hardware memory tagging enforcement: soft mode stays on until simulated crash
  reports have been reviewed on M5-or-later hardware. Then remove the
  `soft-mode` entitlement.
- Additional diagnostic settings (for example Swift strict memory safety): not
  reviewed in this audit.
- App Sandbox (`ENABLE_APP_SANDBOX` is `NO`): outside this audit. The app reads
  installed apps' versions and runs Sparkle's installer, so sandboxing needs its
  own review.

## Verification

An archive and Developer ID export made with the same settings as
`scripts/release.sh`, without notarization, was checked on 2026-11-23:

- The app, `Sparkle.framework`, `Autoupdate`, `Updater.app`, and both XPC
  services contain arm64 and x86_64 and no arm64e.
- All of them are signed with the Developer ID Application certificate for the
  team, with the hardened runtime flag set, and the app's signature verifies.
- The app's entitlements are the eight keys above plus
  `com.apple.security.network.client`. Sparkle's components have the same
  entitlements as in Sparkle's own download.
- The exported app launched and ran in isolated mode (see `RunEnvironment.swift`)
  without a crash report or logged errors.

Not verified: notarization, installing the package, Sparkle updating from an
older build, and memory tagging on supported hardware. Run
`scripts/release.sh` in full before shipping.
