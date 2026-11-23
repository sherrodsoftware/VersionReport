import AppKit

/// The copy of a tracked app installed on this Mac.
struct InstalledAppInfo: Equatable {
    let bundleID: String?
    let version: String
    var build: String? = nil
    let url: URL

    init(bundleID: String?, version: String, build: String? = nil, url: URL) {
        self.bundleID = bundleID
        self.version = version
        self.build = build
        self.url = url
    }
}

/// A built-in library app found on this Mac that isn't tracked yet.
struct InstalledAppSuggestion: Identifiable, Equatable {
    let config: AppConfig
    let installed: InstalledAppInfo
    var id: String { config.id }
}

/// How the installed copy compares with the newest available version.
enum InstallStatus: Equatable {
    /// No bundle ID and no app with a matching name, so nothing to compare.
    case notTracked
    /// The app has a bundle ID but isn't installed on this Mac.
    case notInstalled
    case upToDate
    case outdated
    /// Installed, but the two versions can't be compared reliably.
    case unknown
}

enum InstalledApps {

    /// Finds the installed copy of an app, preferring its bundle ID and falling
    /// back to an app named "<appName>.app" in the Applications folders.
    static func lookup(bundleID: String?, appName: String) -> InstalledAppInfo? {
        if let bundleID {
            let candidates = NSWorkspace.shared.urlsForApplications(withBundleIdentifier: bundleID)
            if let url = preferredLocation(in: candidates), let info = readInfo(at: url) {
                return info
            }
            return nil
        }
        return readInfo(at: applicationURL(named: "\(appName).app"))
    }

    /// The first existing "/Applications/<name>" or "~/Applications/<name>".
    static func applicationURL(named fileName: String) -> URL? {
        let fileManager = FileManager.default
        return applicationFolders
            .map { $0.appendingPathComponent(fileName) }
            .first { fileManager.fileExists(atPath: $0.path) }
    }

    /// Reads the version and bundle ID straight from Info.plist. Bundle(url:)
    /// caches its info dictionary, which would hide updates installed while
    /// Version Report is running.
    static func readInfo(at url: URL?) -> InstalledAppInfo? {
        guard let url,
              let data = try? Data(contentsOf: url.appendingPathComponent("Contents/Info.plist")),
              let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any] else {
            return nil
        }

        let short = (plist["CFBundleShortVersionString"] as? String)?.trimmingCharacters(in: .whitespaces)
        let build = (plist["CFBundleVersion"] as? String)?.trimmingCharacters(in: .whitespaces)
        guard let version = [short, build].compactMap({ $0 }).first(where: { !$0.isEmpty }) else { return nil }

        return InstalledAppInfo(
            bundleID: plist["CFBundleIdentifier"] as? String,
            version: version,
            build: build.flatMap { $0.isEmpty || $0 == version ? nil : $0 },
            url: url
        )
    }

    /// Compares only the numeric parts both versions share, so differently
    /// formatted versions of the same release, such as "6.0.1,3221" and "6.0.1",
    /// or "7.2.5.90525" and "7.2.5 (90525)", count as up to date rather than
    /// raising a false alarm. Both the app's version and its build number are
    /// tried, because some sources publish the build (Microsoft Office's
    /// "16.115.26111533" against an app version of "16.115.1"); the app counts
    /// as current if either one keeps up.
    static func status(installed: InstalledAppInfo?, available: String, tracksInstall: Bool) -> InstallStatus {
        guard let installed else { return tracksInstall ? .notInstalled : .notTracked }
        guard let availableParts = numericParts(VersionReportService.marketingVersion(available)) else { return .unknown }

        var candidates: [[Int]] = []
        if let versionParts = numericParts(installed.version) { candidates.append(versionParts) }
        // A build number only counts when it uses the same scheme as the available
        // version (same first number). Plain counters such as Transmit's "774261"
        // would otherwise always look newer than "5.11.7".
        if let buildParts = installed.build.flatMap(numericParts), buildParts.first == availableParts.first {
            candidates.append(buildParts)
        }

        let results = candidates.map { compare($0, availableParts) }

        if results.contains(.upToDate) { return .upToDate }
        if results.contains(.outdated) { return .outdated }
        return .unknown
    }

    nonisolated private static func compare(_ installedParts: [Int], _ availableParts: [Int]) -> InstallStatus {
        for (have, latest) in zip(installedParts, availableParts) where have != latest {
            return have < latest ? .outdated : .upToDate
        }
        return .upToDate
    }

    /// The leading dotted number in a version string: "6.0.1 (3221)" → [6, 0, 1].
    nonisolated static func numericParts(_ version: String) -> [Int]? {
        guard let range = version.range(of: #"[0-9]+(\.[0-9]+)*"#, options: .regularExpression) else { return nil }
        let parts = version[range].split(separator: ".").compactMap { Int($0) }
        return parts.isEmpty ? nil : parts
    }

    private static var applicationFolders: [URL] {
        [
            URL(fileURLWithPath: "/Applications"),
            FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Applications")
        ]
    }

    /// Prefers a copy in an Applications folder over others LaunchServices knows
    /// about, such as build products or apps on mounted disk images.
    private static func preferredLocation(in urls: [URL]) -> URL? {
        let folders = applicationFolders.map { $0.standardizedFileURL.path + "/" }
        let usable = urls.filter { url in
            let path = url.standardizedFileURL.path
            return !path.contains("/.Trash/") && !path.hasPrefix("/Volumes/")
        }
        return usable.first { url in folders.contains { url.standardizedFileURL.path.hasPrefix($0) } }
            ?? usable.first
    }
}
