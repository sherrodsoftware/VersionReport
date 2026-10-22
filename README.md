# Version Report

A macOS app for tracking the latest versions of the software you manage — so you always know whether your fleet is running what it should be.

![macOS](https://img.shields.io/badge/macOS-14%2B-blue) ![Swift](https://img.shields.io/badge/Swift-5.9-orange)

---

## What it does

Version Report keeps a list of your important apps and checks each one for the latest available version. When something updates, it flags it so you can decide whether action is needed.

- **Automatic checks** — runs a version check on launch and every hour in the background
- **Unread badges** — new updates bubble to the top and are marked with a blue dot until you dismiss them
- **App detail panel** — double-click any app to see its full version history, source, and dates at a glance
- **Groups** — organize apps into custom groups (drag apps from the table onto a group, or right-click → Add to Group)
- **Built-in library** — a curated list of common macOS apps ready to add with a few clicks

---

## Supported version sources

Version Report knows how to check versions from four sources:

| Source | How it works |
|--------|-------------|
| **Homebrew Cask** | Queries the Homebrew formula for the latest cask version |
| **Sparkle Feed** | Parses an app's Sparkle update XML feed |
| **GitHub Releases** | Reads the latest release tag from a public GitHub repository |
| **Custom** | Fetches any URL and extracts a version using a regex or JSON path |

---

## Getting started

1. **Add apps** — use **File → Add App…** (⇧⌘A) or click the **+** button below the list
2. **Add from the library** — use **File → Add App From Library…** (⌥⌘L) to pick from the built-in curated list
3. **Check for updates** — click the refresh button in the toolbar or press ⌘R
4. **Organize with groups** — use **File → New Group** (⌘N) to create a group, then drag apps onto it from the table or right-click to assign them

---

## The built-in library

The app ships with a curated library of common macOS apps maintained by the developer. When you add an app from the library, Version Report handles keeping the source configuration correct.

**Library vs. your apps:** The built-in library is the pool of apps you *can* add — it doesn't automatically add anything to your list. Apps you've already added manually won't be overwritten if the same app appears in the library. If there's ever a conflict, Version Report will let you know and give you the choice of which version to keep.

To add your own app to the library (so you can reuse its config across machines), select it in the list and choose **File → Add Selected App to Library**.

---

## Building from source

Requires Xcode 15 or later and macOS 14 Sonoma or later.

```bash
git clone https://github.com/sherrodsoftware/VersionReport.git
cd VersionReport
open "Version Report.xcodeproj"
```

Then build and run with ⌘R.

---

## Contributing

Bug reports and feature requests are welcome via [GitHub Issues](https://github.com/sherrodsoftware/VersionReport/issues). Pull requests are also welcome — please open an issue first to discuss significant changes.
