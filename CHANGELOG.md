# Changelog

## Unreleased

- **Less redrawing.** Version Report's models now use Swift's Observation instead of `ObservableObject`, so a change redraws only the views that show it. Before, any change, such as a new status message, the end of a check, or selecting a row, redrew the whole window, sidebar, and detail panel. Menu commands are now built as small views, so their enabled state keeps following the selection.
- **Faster checks and adding.** A version check gathers every app's result and saves them together, instead of reading and rewriting the app state file twice for each app. Adding several apps at once, from Add Installed Apps or Add from Library, saves and checks them together instead of rebuilding the list twice for each app, and the status line reports how many were added. Installed versions are looked up once and reused until Version Report becomes active again.
- **Quicker table.** App icons are read and decoded once and kept in memory, instead of for every visible row each time the table redraws. The table's rows are filtered and sorted when the apps, groups, sort, or search change, rather than twice on every redraw, so selecting a row no longer re-sorts the list.
- **Clicks no longer go missing after dragging.** After dragging apps onto a group, the next click anywhere in the window was lost, so selecting All Apps or a group took a second click. Rows now use the table's own dragging, which drags the selection, shows the rows with a count, and starts anywhere on a row, instead of a custom drag that left the table waiting for a mouse-up.
- **Double-click anywhere on a row** to open its details, or press Return. This uses the table's own double-click action instead of a double-tap on the app's name.
- **Dropping apps onto a group works anywhere on the group.** Before, a group only accepted a drop near its top or bottom edge. The sidebar is now a standard Mac source list, like Mail's or Music's: selection uses the system highlight, the arrow keys move between items, VoiceOver announces each item and its unread count, and dragging several apps adds them all with one save.
- **Release script.** `scripts/release.sh` archives, exports, packages, notarizes, staples, and Sparkle-signs a release, checks the signature and hardened runtime, refuses a build number Sparkle wouldn't offer, and prints the appcast entry. `--hotfix` names the package for a new build of an existing release.
- **Packages always install into /Applications**, rather than over a copy of Version Report that was moved elsewhere.
- **Tests no longer touch your Version Report.** Running the tests used the real data folder and settings, and saved the test window's column widths over yours. Tests and profiling launches now use their own data and settings, and never start Sparkle or send notifications or Teams messages.
- **Stronger built-in protections.** Version Report now turns on macOS's Enhanced Security protections, which make it harder for a bug in the app to be used against it: extra separation of memory allocations, read-only dynamic loader data, and tighter limits on loading libraries and receiving messages from other processes. On newer Macs (M5 or later), memory errors are also checked by the hardware, and for now they only produce a diagnostic report instead of closing the app. You shouldn't notice any difference.
- **Up-to-date documentation.** The docs now describe the current library and icon behavior, sources, data files, and release process, and the Roadmap is no longer published.

## Version Report 2026.11.19

- **Installed Version.** An optional column shows the version of each app installed on this Mac beside the newest available version, with an orange arrow when it's behind. The detail panel shows it too, and smart groups can match apps whose installed version is out of date, is current, is installed, or is not installed. It refreshes when Version Report becomes active. Versions compare only the parts they share, and an app's build number is also tried when it uses the same scheme as the source, so differently formatted versions of the same release aren't flagged.
- **Add the apps you already have.** At launch, Version Report offers to track apps on this Mac that are in its built-in library. Not Now asks again at the next launch; Don't show this again turns the prompt off, and Settings turns it back on. File > Add Installed Apps opens the list at any time.
- **Bundle IDs.** Apps have an optional bundle ID, which is how Version Report finds the installed copy. All 100 built-in apps include one, apps you add get one automatically when possible, and the Add/Edit window has a Bundle ID field and Choose App. LIBRARY.md lists each app's bundle ID.
- **Sparkle feeds.** Feeds that put the version inside each item rather than on the download link now work, instead of reporting "No version found in feed".
- **Hotfix (build 2026111905).** Not Now no longer hides the installed apps prompt for good.

## Version Report 2026.11.17

- **Custom icons are kept.** Icons set by dragging an image onto an app are no longer replaced by the built-in icon at each launch. Built-in icons you haven't changed still update.
- **Whole-number versions.** Custom web lookups can track apps that use plain whole-number versions, such as 27 or 90. A dotted version still wins when a match contains one, so existing lookups report the same versions.
- **Selecting text in the Edit App window** no longer starts dragging an app from the list behind it.
- **Figma** has a new icon, taken from the app.

## Version Report 2026.11.09

- **100 apps in the built-in library**, adding Figma, OpenCode, and OS Report. LIBRARY.md lists them all.
- **Check for Updates moved to the app menu**, below About Version Report. Checking monitored apps is now Check Versions Now (⌘R) in the File menu and toolbar.
- **Jamf Extender** has its own icon.

## Version Report 2026.11.06

- **Release history.** Each app's detail panel lists the versions Version Report knows about, with release dates from GitHub, Sparkle, and the App Store where available.
- **Overdue update alerts.** Apps that go quiet well past their usual release cycle get a clock badge and one notification, and smart groups can match them.
- **Version-only copying and notifications**, without the trailing build number.
- **SoundQ** reads Pro Sound Effects' version API after a site redesign broke the old lookup.
- **Hotfix (build 2026110602).** Add from Library always uses the built-in definition for built-in apps, so re-adding an app picks up lookup fixes.

Earlier releases are listed on [GitHub Releases](https://github.com/sherrodsoftware/VersionReport/releases).
