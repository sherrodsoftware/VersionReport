import Foundation
import AppKit
import UserNotifications
import UniformTypeIdentifiers
import Combine

enum VersionFetchError: Error, LocalizedError {
    case rateLimited(source: String)
    case httpError(source: String, statusCode: Int)

    var errorDescription: String? {
        switch self {
        case .rateLimited(let source): return "\(source) rate limit reached"
        case .httpError(let source, let code): return "\(source) returned HTTP \(code)"
        }
    }
}

private final class SparkleXMLParser: NSObject, XMLParserDelegate {
    var version: String?

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?, attributes: [String: String] = [:]) {
        guard elementName == "enclosure", version == nil else { return }
        version = attributes["sparkle:shortVersionString"] ?? attributes["sparkle:version"]
        if version != nil { parser.abortParsing() }
    }
}

enum AppSource: Equatable {
    case homebrew(caskName: String)
    case sparkle(feedURL: URL)
    case github(repoPath: String)
    case custom(versionURL: URL, parserType: String, parserValue: String)

    var displayName: String {
        switch self {
        case .homebrew: return "Homebrew Cask"
        case .sparkle: return "Sparkle Feed"
        case .github: return "GitHub Releases"
        case .custom(_, let parserType, _): return "Custom (\(parserType))"
        }
    }
}

extension AppSource: Codable {
    enum CodingKeys: String, CodingKey {
        case sourceType, caskName, feedURL, repoPath, versionURL, parserType, parserValue
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let sourceType = try container.decodeIfPresent(String.self, forKey: .sourceType) ?? "custom"

        switch sourceType {
        case "homebrew":
            self = .homebrew(caskName: try container.decode(String.self, forKey: .caskName))
        case "sparkle":
            self = .sparkle(feedURL: try container.decode(URL.self, forKey: .feedURL))
        case "github":
            self = .github(repoPath: try container.decode(String.self, forKey: .repoPath))
        default:
            self = .custom(
                versionURL: try container.decode(URL.self, forKey: .versionURL),
                parserType: try container.decode(String.self, forKey: .parserType),
                parserValue: try container.decode(String.self, forKey: .parserValue)
            )
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .homebrew(let caskName):
            try container.encode("homebrew", forKey: .sourceType)
            try container.encode(caskName, forKey: .caskName)
        case .sparkle(let feedURL):
            try container.encode("sparkle", forKey: .sourceType)
            try container.encode(feedURL, forKey: .feedURL)
        case .github(let repoPath):
            try container.encode("github", forKey: .sourceType)
            try container.encode(repoPath, forKey: .repoPath)
        case .custom(let versionURL, let parserType, let parserValue):
            try container.encode(versionURL, forKey: .versionURL)
            try container.encode(parserType, forKey: .parserType)
            try container.encode(parserValue, forKey: .parserValue)
        }
    }
}

struct AppConfig: Codable, Identifiable, Equatable {
    enum CodingKeys: String, CodingKey {
        case id, name
    }

    var id: String
    let name: String
    let source: AppSource

    init(id: String? = nil, name: String, source: AppSource) {
        self.id = id ?? Self.defaultID(for: name)
        self.name = name
        self.source = source
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let name = try container.decode(String.self, forKey: .name)
        self.init(
            id: try container.decodeIfPresent(String.self, forKey: .id),
            name: name,
            source: try AppSource(from: decoder)
        )
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try source.encode(to: encoder)
    }

    static func defaultID(for name: String) -> String {
        let components = name.lowercased().split { !$0.isLetter && !$0.isNumber }
        return components.map(String.init).joined(separator: "_")
    }
}

struct LibraryConflict: Codable, Identifiable {
    let bundledConfig: AppConfig
    let userConfig: AppConfig
    var id: String { bundledConfig.id }
}

struct AppState: Codable {
    var version: String
    var previousVersion: String?
    var lastChecked: String
    var lastUpdated: String?
    var hasUnreadUpdate: Bool

    init(version: String, previousVersion: String?, lastChecked: String, lastUpdated: String?, hasUnreadUpdate: Bool) {
        self.version = version
        self.previousVersion = previousVersion
        self.lastChecked = lastChecked
        self.lastUpdated = lastUpdated
        self.hasUnreadUpdate = hasUnreadUpdate
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        version = try container.decode(String.self, forKey: .version)
        previousVersion = try container.decodeIfPresent(String.self, forKey: .previousVersion)
        lastChecked = try container.decode(String.self, forKey: .lastChecked)
        let rawLastUpdated = try container.decodeIfPresent(String.self, forKey: .lastUpdated)
        lastUpdated = rawLastUpdated == "Never" ? nil : rawLastUpdated
        hasUnreadUpdate = try container.decodeIfPresent(Bool.self, forKey: .hasUnreadUpdate) ?? false
    }
}

final class VersionReportService: ObservableObject {

    @Published var apps: [MonitoredApp] = [] {
        didSet {
            updateDockBadge()
        }
    }
    @Published var isChecking = false
    @Published var statusMessage = "Ready"
    @Published var pendingLibraryConflicts: [LibraryConflict] = []
    @Published var groups: [AppGroup] = []

    private var hourlyTimer: Timer?
    private var dockBadgeRefreshObserver: NSObjectProtocol?
    private let baseURL: URL
    private let bundledAppLibraryURL: URL?

    init(
        baseURL: URL = versionReportBaseURL,
        bundledAppLibraryURL: URL? = Bundle.main.url(
            forResource: "app-library",
            withExtension: "json"
        )
    ) {
        self.baseURL = baseURL
        self.bundledAppLibraryURL = bundledAppLibraryURL
        dockBadgeRefreshObserver = NotificationCenter.default.addObserver(
            forName: .versionReportRefreshDockBadge,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.updateDockBadge()
        }
    }

    deinit {
        if let dockBadgeRefreshObserver {
            NotificationCenter.default.removeObserver(dockBadgeRefreshObserver)
        }
    }

    private var appStateURL: URL {
        baseURL.appendingPathComponent("app-state.json")
    }

    private var appsConfigURL: URL {
        baseURL.appendingPathComponent("apps.json")
    }

    private var appLibraryURL: URL {
        baseURL.appendingPathComponent("app-library.json")
    }

    private var groupsURL: URL {
        baseURL.appendingPathComponent("groups.json")
    }

    private func loadGroups() -> [AppGroup] {
        guard let data = try? Data(contentsOf: groupsURL),
              let loaded = try? JSONDecoder().decode([AppGroup].self, from: data) else {
            return []
        }
        return loaded
    }

    private func saveGroups(_ groups: [AppGroup]) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(groups) else { return }
        try? data.write(to: groupsURL)
    }

    func createGroup(named name: String) {
        var updated = groups
        updated.append(AppGroup(name: name))
        saveGroups(updated)
        groups = updated
    }

    func deleteGroup(id: String) {
        var updated = groups.filter { $0.id != id }
        saveGroups(updated)
        groups = updated
    }

    func renameGroup(id: String, to newName: String) {
        var updated = groups
        guard let idx = updated.firstIndex(where: { $0.id == id }) else { return }
        updated[idx].name = newName
        saveGroups(updated)
        groups = updated
    }

    func addApp(_ appID: String, toGroup groupID: String) {
        var updated = groups
        guard let idx = updated.firstIndex(where: { $0.id == groupID }) else { return }
        guard !updated[idx].appIDs.contains(appID) else { return }
        updated[idx].appIDs.append(appID)
        saveGroups(updated)
        groups = updated
    }

    func moveGroups(from source: IndexSet, to destination: Int) {
        var updated = groups
        let items = source.sorted().map { updated[$0] }
        for index in source.sorted().reversed() { updated.remove(at: index) }
        let adjustedDest = destination - source.filter { $0 < destination }.count
        updated.insert(contentsOf: items, at: max(0, min(adjustedDest, updated.count)))
        saveGroups(updated)
        groups = updated
    }

    func removeApp(_ appID: String, fromGroup groupID: String) {
        var updated = groups
        guard let idx = updated.firstIndex(where: { $0.id == groupID }) else { return }
        updated[idx].appIDs.removeAll { $0 == appID }
        saveGroups(updated)
        groups = updated
    }

    private func loadPersistedConflicts() -> [LibraryConflict] {
        guard let data = UserDefaults.standard.data(forKey: "pendingLibraryConflicts") else { return [] }
        return (try? JSONDecoder().decode([LibraryConflict].self, from: data)) ?? []
    }

    private func savePersistedConflicts(_ conflicts: [LibraryConflict]) {
        if let data = try? JSONEncoder().encode(conflicts) {
            UserDefaults.standard.set(data, forKey: "pendingLibraryConflicts")
        }
    }


    func loadApps() {
        initializeApplicationSupportIfNeeded()
        pendingLibraryConflicts = loadPersistedConflicts()
        groups = loadGroups()
        reloadApps()
        runVersionCheck()
    }

    func resolveLibraryConflict(_ conflict: LibraryConflict, useBuiltin: Bool) {
        if useBuiltin {
            var monitoredConfigs = loadAppConfigs()
            if let idx = monitoredConfigs.firstIndex(where: { $0.id == conflict.userConfig.id }) {
                monitoredConfigs[idx] = conflict.bundledConfig
                saveAppConfigs(monitoredConfigs)
                reloadApps()
            }
        }
        // Regardless of choice, remove from pending list
        var remaining = loadPersistedConflicts().filter { $0.id != conflict.id }
        savePersistedConflicts(remaining)
        pendingLibraryConflicts = remaining
    }

    func loadAppConfigs() -> [AppConfig] {

        guard let data = try? Data(contentsOf: appsConfigURL),
              let configs = try? JSONDecoder().decode([AppConfig].self, from: data) else {
            return []
        }

        let normalizedConfigs = normalizeIDs(in: configs)

        if normalizedConfigs != configs {
            saveAppConfigs(normalizedConfigs)
        }

        return normalizedConfigs
    }


    func saveAppConfigs(_ configs: [AppConfig]) {

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]

        guard let data = try? encoder.encode(configs) else {
            return
        }

        try? data.write(to: appsConfigURL, options: .atomic)
    }

    func loadAppLibrary() -> [AppConfig] {

        guard let data = try? Data(contentsOf: appLibraryURL),
              let configs = try? JSONDecoder().decode([AppConfig].self, from: data) else {
            return []
        }

        let normalizedConfigs = normalizeIDs(in: configs)

        if normalizedConfigs != configs {
            saveAppLibrary(normalizedConfigs)
        }

        return normalizedConfigs.sorted {
            $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
    }

    func saveAppLibrary(_ configs: [AppConfig]) {

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]

        guard let data = try? encoder.encode(configs) else {
            return
        }

        try? data.write(to: appLibraryURL, options: .atomic)
    }

    func addAppConfigToLibrary(_ config: AppConfig) {

        var libraryConfigs = loadAppLibrary()

        if libraryConfigs.contains(where: { $0.id == config.id }) {
            statusMessage = "The selected app is already in the app library."
            return
        }

        libraryConfigs.append(config)
        saveAppLibrary(libraryConfigs)
        statusMessage = "Added \(config.name) to the app library."
    }

    func initializeApplicationSupportIfNeeded() {

        let fileManager = FileManager.default

        try? fileManager.createDirectory(
            at: baseURL,
            withIntermediateDirectories: true
        )

        if !fileManager.fileExists(atPath: appsConfigURL.path) {
            saveAppConfigs([])
        }

        initializeAppLibraryIfNeeded()
        initializeIconsIfNeeded()
        mergeBundledAppLibrary()
        mergeBundledAppConfigsIntoMonitoredApps()
        mergeBundledIcons()

        if !fileManager.fileExists(atPath: appStateURL.path) {
            saveAppState([:])
        }
    }

    func initializeAppLibraryIfNeeded() {

        let fileManager = FileManager.default

        guard !fileManager.fileExists(atPath: appLibraryURL.path) else {
            return
        }

        if let bundledLibraryURL = bundledAppLibraryURL {
            try? fileManager.copyItem(
                at: bundledLibraryURL,
                to: appLibraryURL
            )
            return
        }

        let currentConfigs = loadAppConfigs()
        saveAppLibrary(currentConfigs)
    }

    func mergeBundledAppLibrary() {

        guard let bundledLibraryURL = bundledAppLibraryURL,
              let bundledData = try? Data(contentsOf: bundledLibraryURL),
              let bundledConfigs = try? JSONDecoder().decode([AppConfig].self, from: bundledData) else {
            return
        }

        var userLibraryConfigs = loadAppLibrary()
        var didChangeLibrary = false

        for bundledConfig in bundledConfigs {
            if !userLibraryConfigs.contains(where: { $0.id == bundledConfig.id }) {
                // New entry: add it; never overwrite an entry the user already has.
                userLibraryConfigs.append(bundledConfig)
                didChangeLibrary = true
            }
        }

        guard didChangeLibrary else { return }
        saveAppLibrary(userLibraryConfigs)
    }

    func mergeBundledAppConfigsIntoMonitoredApps() {

        guard let bundledLibraryURL = bundledAppLibraryURL,
              let bundledData = try? Data(contentsOf: bundledLibraryURL),
              let bundledConfigs = try? JSONDecoder().decode([AppConfig].self, from: bundledData) else {
            return
        }

        let monitoredConfigs = loadAppConfigs()
        var knownConflictIDs = Set(loadPersistedConflicts().map { $0.id })
        var newConflicts: [LibraryConflict] = []

        for bundledConfig in bundledConfigs {
            // If already monitored under the same ID, the user's config wins — don't touch it.
            if monitoredConfigs.contains(where: { $0.id == bundledConfig.id }) { continue }

            // If monitored under a different ID but the same name, the user added it before
            // it became a built-in entry. Record a conflict so we can offer to swap.
            if let userConfig = monitoredConfigs.first(where: {
                $0.name.localizedCaseInsensitiveCompare(bundledConfig.name) == .orderedSame &&
                $0.id != bundledConfig.id &&
                $0.source != bundledConfig.source
            }) {
                if !knownConflictIDs.contains(bundledConfig.id) {
                    newConflicts.append(LibraryConflict(bundledConfig: bundledConfig, userConfig: userConfig))
                    knownConflictIDs.insert(bundledConfig.id)
                }
            }
        }

        if !newConflicts.isEmpty {
            var all = loadPersistedConflicts() + newConflicts
            // Deduplicate by bundled config ID
            var seen = Set<String>()
            all = all.filter { seen.insert($0.id).inserted }
            savePersistedConflicts(all)
            pendingLibraryConflicts = all
        }
    }

    func initializeIconsIfNeeded() {

        let fileManager = FileManager.default
        let iconsURL = baseURL.appendingPathComponent("icons")

        guard !fileManager.fileExists(atPath: iconsURL.path) else {
            return
        }

        if let bundledIconsURL = Bundle.main.url(
            forResource: "icons",
            withExtension: nil
        ) {
            try? fileManager.copyItem(
                at: bundledIconsURL,
                to: iconsURL
            )
        } else {
            try? fileManager.createDirectory(
                at: iconsURL,
                withIntermediateDirectories: true
            )
        }
    }

    func mergeBundledIcons() {

        let fileManager = FileManager.default

        guard let bundledIconsURL = Bundle.main.url(
            forResource: "icons",
            withExtension: nil
        ) else {
            return
        }

        let userIconsURL = baseURL.appendingPathComponent("icons")

        try? fileManager.createDirectory(
            at: userIconsURL,
            withIntermediateDirectories: true
        )

        guard let bundledIconFiles = try? fileManager.contentsOfDirectory(
            at: bundledIconsURL,
            includingPropertiesForKeys: nil
        ) else {
            return
        }

        for bundledIconFile in bundledIconFiles {

            let destinationURL = userIconsURL.appendingPathComponent(
                bundledIconFile.lastPathComponent
            )

            if fileManager.fileExists(atPath: destinationURL.path) {
                try? fileManager.removeItem(at: destinationURL)
            }

            try? fileManager.copyItem(
                at: bundledIconFile,
                to: destinationURL
            )
        }
    }

    func addAppConfig(_ config: AppConfig) {
        var configs = loadAppConfigs()

        guard !configs.contains(where: { $0.id == config.id }) else {
            statusMessage = "An app with this ID is already being tracked."
            return
        }

        configs.append(config)
        saveAppConfigs(configs)
        loadApps()

        Task {
            do {
                if let version = try await fetchCurrentVersion(for: config) {

                    _ = updateAppState(
                        version: version,
                        for: config
                    )

                    let updatedApps = loadMonitoredApps()

                    await MainActor.run {
                        self.apps = updatedApps
                        self.statusMessage = "Added \(config.name) at \(Self.displayTimeFormatter.string(from: Date()))"
                    }
                }

            } catch {

                await MainActor.run {
                    self.statusMessage = "Added \(config.name), but version lookup failed"
                }

                print("Initial check failed for \(config.name): \(error)")
            }
        }
    }

    func updateAppConfig(_ config: AppConfig, replacingID id: String) -> AppConfig? {
        var configs = loadAppConfigs()

        guard let index = configs.firstIndex(where: { $0.id == id }) else {
            return nil
        }

        let existingConfig = configs[index]
        let updatedConfig = AppConfig(
            id: existingConfig.id,
            name: config.name,
            source: config.source
        )

        configs[index] = updatedConfig
        saveAppConfigs(configs)
        migrateAppState(for: existingConfig)

        return updatedConfig
    }

    func deleteAppConfig(id: String) {
        let configs = loadAppConfigs().filter { $0.id != id }
        saveAppConfigs(configs)

        var appState = loadAppState()
        appState.removeValue(forKey: id)
        saveAppState(appState)

        reloadApps()
    }

    func customParserTypes() -> [String] {
        ["jq", "jq_trim_comma", "regex", "highest_version"]
    }

    func fetchCurrentVersion(for config: AppConfig) async throws -> String? {
        switch config.source {
        case .homebrew(let caskName):
            return try await lookupHomebrewCask(caskName)?.version

        case .sparkle(let feedURL):
            return try await lookupSparkleFeed(feedURL)?.version

        case .github(let repoPath):
            return try await lookupGitHubRelease(repoPath)?.version

        case .custom(let versionURL, let parserType, let parserValue):
            let (data, _) = try await URLSession.shared.data(from: versionURL)

            switch parserType {
            case "jq":
                return parseJSONValue(from: data, keyPath: parserValue)

            case "jq_trim_comma":
                return parseJSONValue(from: data, keyPath: parserValue)?
                    .split(separator: ",", maxSplits: 1)
                    .first
                    .map(String.init)

            case "regex":
                guard let responseText = String(data: data, encoding: .utf8) else { return nil }
                return firstRegexVersionMatch(in: responseText, pattern: parserValue)

            case "highest_version":
                guard let responseText = String(data: data, encoding: .utf8) else { return nil }
                return highestRegexVersionMatch(in: responseText, pattern: parserValue)

            default:
                return nil
            }
        }
    }

    struct HomebrewCaskInfo {
        let name: String
        let version: String
    }

    func lookupHomebrewCask(_ caskName: String) async throws -> HomebrewCaskInfo? {
        let trimmed = caskName.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !trimmed.isEmpty,
              let url = URL(string: "https://formulae.brew.sh/api/cask/\(trimmed).json") else {
            return nil
        }

        let (data, response) = try await URLSession.shared.data(from: url)

        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            return nil
        }

        struct CaskResponse: Decodable {
            let name: [String]
            let version: String
        }

        guard let cask = try? JSONDecoder().decode(CaskResponse.self, from: data),
              let displayName = cask.name.first else {
            return nil
        }

        return HomebrewCaskInfo(name: displayName, version: cask.version)
    }

    struct SparkleInfo {
        let version: String
    }

    func lookupSparkleFeed(_ feedURL: URL) async throws -> SparkleInfo? {
        let (data, response) = try await URLSession.shared.data(from: feedURL)

        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            return nil
        }

        let parser = SparkleXMLParser()
        let xmlParser = XMLParser(data: data)
        xmlParser.delegate = parser
        xmlParser.parse()

        guard let version = parser.version else { return nil }
        return SparkleInfo(version: version)
    }

    struct GitHubReleaseInfo {
        let repoName: String
        let version: String
        let tagName: String
    }

    func lookupGitHubRelease(_ repoPath: String) async throws -> GitHubReleaseInfo? {
        let normalized = Self.normalizeGitHubRepoPath(repoPath)
        guard !normalized.isEmpty,
              let url = URL(string: "https://api.github.com/repos/\(normalized)/releases/latest") else {
            return nil
        }

        var request = URLRequest(url: url)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else { return nil }

        if httpResponse.statusCode == 403 || httpResponse.statusCode == 429 {
            let remaining = httpResponse.value(forHTTPHeaderField: "X-RateLimit-Remaining")
            if remaining == "0" || httpResponse.statusCode == 429 {
                throw VersionFetchError.rateLimited(source: "GitHub")
            }
        }

        guard httpResponse.statusCode == 200 else { return nil }

        struct ReleaseResponse: Decodable {
            let tagName: String
            let name: String?
            enum CodingKeys: String, CodingKey {
                case tagName = "tag_name"
                case name
            }
        }

        guard let release = try? JSONDecoder().decode(ReleaseResponse.self, from: data) else {
            return nil
        }

        let repoName = normalized.components(separatedBy: "/").last ?? normalized
        let version = release.tagName.hasPrefix("v") ? String(release.tagName.dropFirst()) : release.tagName

        return GitHubReleaseInfo(repoName: repoName, version: version, tagName: release.tagName)
    }

    static func normalizeGitHubRepoPath(_ input: String) -> String {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        // Accept "owner/repo" directly
        if trimmed.range(of: #"^[^/]+/[^/]+$"#, options: .regularExpression) != nil {
            return trimmed
        }
        // Parse from a github.com URL
        guard let url = URL(string: trimmed),
              let host = url.host,
              host.hasSuffix("github.com") else {
            return ""
        }
        let parts = url.pathComponents.filter { $0 != "/" }
        guard parts.count >= 2 else { return "" }
        return "\(parts[0])/\(parts[1])"
    }

    func runVersionCheck() {

        if isChecking {
            return
        }

        isChecking = true
        statusMessage = "Check Running..."

        let configs = loadAppConfigs()

        Task {
            var detectedUpdates: [(appName: String, previousVersion: String, currentVersion: String)] = []
            var fetchErrors: [String] = []

            await withTaskGroup(of: (AppConfig, String?, Error?).self) { group in
                for config in configs {
                    group.addTask {
                        do {
                            let version = try await self.fetchCurrentVersion(for: config)
                            return (config, version, nil)
                        } catch {
                            return (config, nil, error)
                        }
                    }
                }

                for await (config, version, error) in group {
                    if let error {
                        print("Check failed for \(config.name): \(error)")
                        fetchErrors.append("\(config.name): \(error.localizedDescription)")
                    } else if let version {
                        let result = updateAppState(version: version, for: config)

                        if result.didUpdate {
                            sendVersionUpdateNotification(
                                appName: config.name,
                                previousVersion: result.previousVersion,
                                currentVersion: version
                            )

                            detectedUpdates.append(
                                (
                                    appName: config.name,
                                    previousVersion: result.previousVersion,
                                    currentVersion: version
                                )
                            )
                        }
                    }
                }
            }

            if !detectedUpdates.isEmpty {
                await sendTeamsUpdateNotification(for: detectedUpdates)
            }

            let updatedApps = loadMonitoredApps()
            let completionTime = Self.displayTimeFormatter.string(from: Date())

            await MainActor.run {
                self.apps = updatedApps
                self.isChecking = false
                if fetchErrors.isEmpty {
                    self.statusMessage = "Check completed at \(completionTime)"
                } else {
                    let summary = fetchErrors.count == 1
                        ? fetchErrors[0]
                        : "\(fetchErrors.count) apps failed (\(fetchErrors.joined(separator: "; ")))"
                    self.statusMessage = "Check completed at \(completionTime) — \(summary)"
                }
            }

        }

    }

    func loadAppState() -> [String: AppState] {

        guard let data = try? Data(contentsOf: appStateURL) else {
            return [:]
        }

        return (try? JSONDecoder().decode([String: AppState].self, from: data)) ?? [:]
    }

    func saveAppState(_ appState: [String: AppState]) {

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]

        guard let data = try? encoder.encode(appState) else {
            return
        }

        try? data.write(to: appStateURL, options: .atomic)
    }

    private func normalizeIDs(in configs: [AppConfig]) -> [AppConfig] {
        var usedIDs = Set<String>()

        return configs.map { config in
            var normalizedConfig = config
            let baseID = config.id.isEmpty ? AppConfig.defaultID(for: config.name) : config.id
            var candidateID = baseID
            var suffix = 2

            while usedIDs.contains(candidateID) {
                candidateID = "\(baseID)_\(suffix)"
                suffix += 1
            }

            normalizedConfig.id = candidateID
            usedIDs.insert(candidateID)
            return normalizedConfig
        }
    }

    private func migrateAppState(for configs: [AppConfig]) {
        var appState = loadAppState()
        var didMigrate = false

        for config in configs where appState[config.id] == nil {
            if let legacyState = appState.removeValue(forKey: config.name) {
                appState[config.id] = legacyState
                didMigrate = true
            }
        }

        if didMigrate {
            saveAppState(appState)
        }
    }

    private func migrateAppState(for config: AppConfig) {
        migrateAppState(for: [config])
    }

    func unreadUpdateCount() -> Int {
        apps.filter(\.hasUnreadUpdate).count
    }

    func updateDockBadge() {
        DispatchQueue.main.async { [weak self] in
            guard let self else {
                return
            }

            let count = self.unreadUpdateCount()
            let dockTile = NSApplication.shared.dockTile
            dockTile.contentView = nil
            dockTile.badgeLabel = count > 0 ? "\(count)" : nil
            dockTile.display()
        }
    }

    /// Reloads the visible app snapshot and its matching Dock badge from saved state.
    func reloadApps() {
        apps = loadMonitoredApps()
    }

    func markUpdatesAsRead(for appIDs: Set<String>) {
        setUnreadStatus(false, for: appIDs)
    }

    func markUpdatesAsUnread(for appIDs: Set<String>) {
        setUnreadStatus(true, for: appIDs)
    }

    private func setUnreadStatus(_ isUnread: Bool, for appIDs: Set<String>) {
        guard !appIDs.isEmpty else {
            return
        }

        var appState = loadAppState()
        var didChange = false

        for appID in appIDs {
            guard var state = appState[appID], state.hasUnreadUpdate != isUnread else {
                continue
            }

            state.hasUnreadUpdate = isUnread
            appState[appID] = state
            didChange = true
        }

        guard didChange else {
            return
        }

        saveAppState(appState)
        reloadApps()
    }


    func updateAppState(version: String, for config: AppConfig) -> (previousVersion: String, didUpdate: Bool) {

        var appState = loadAppState()
        let existingState = appState[config.id]
        let previousVersion = existingState?.version ?? "Unknown"
        let didUpdate = previousVersion != "Unknown" && previousVersion != version

        let now = Self.iso8601Writer.string(from: Date())

        let lastUpdated: String?
        let hasUnreadUpdate: Bool

        if didUpdate {
            lastUpdated = now
            hasUnreadUpdate = true
        } else {
            lastUpdated = existingState?.lastUpdated
            hasUnreadUpdate = existingState?.hasUnreadUpdate ?? false
        }

        appState[config.id] = AppState(
            version: version,
            previousVersion: didUpdate ? previousVersion : existingState?.previousVersion,
            lastChecked: now,
            lastUpdated: lastUpdated,
            hasUnreadUpdate: hasUnreadUpdate
        )

        saveAppState(appState)

        return (previousVersion, didUpdate)
    }

    func parseJSONValue(from data: Data, keyPath: String) -> String? {
        guard let json = try? JSONSerialization.jsonObject(with: data) else {
            return nil
        }

        let keys = keyPath
            .trimmingCharacters(in: CharacterSet(charactersIn: "."))
            .split(separator: ".")
            .map(String.init)

        var currentValue: Any = json

        for key in keys {
            if let dictionary = currentValue as? [String: Any] {
                guard let nextValue = dictionary[key] else {
                    return nil
                }
                currentValue = nextValue
            } else if let array = currentValue as? [Any],
                      let index = Int(key),
                      array.indices.contains(index) {
                currentValue = array[index]
            } else {
                return nil
            }
        }

        if let stringValue = currentValue as? String {
            return stringValue
        }

        if let numberValue = currentValue as? NSNumber {
            return numberValue.stringValue
        }

        return nil
    }

    func firstRegexVersionMatch(in text: String, pattern: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return nil
        }

        let range = NSRange(text.startIndex..<text.endIndex, in: text)

        guard let match = regex.firstMatch(in: text, range: range),
              let matchRange = Range(match.range, in: text) else {
            return nil
        }

        let matchedText = String(text[matchRange])
        return extractVersionNumber(from: matchedText)
    }

    func highestRegexVersionMatch(in text: String, pattern: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return nil
        }

        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        let matches = regex.matches(in: text, range: range)

        let versions = matches.compactMap { match -> String? in
            guard let matchRange = Range(match.range, in: text) else {
                return nil
            }

            let matchedText = String(text[matchRange])
            return extractVersionNumber(from: matchedText)
        }

        return versions.sorted(by: compareVersions).last
    }

    func extractVersionNumber(from text: String) -> String? {
        let versionPattern = #"[0-9]+(\.[0-9]+)+"#

        guard let regex = try? NSRegularExpression(pattern: versionPattern) else {
            return nil
        }

        let range = NSRange(text.startIndex..<text.endIndex, in: text)

        guard let match = regex.firstMatch(in: text, range: range),
              let matchRange = Range(match.range, in: text) else {
            return nil
        }

        return String(text[matchRange])
    }

    func compareVersions(_ left: String, _ right: String) -> Bool {
        let leftParts = left.split(separator: ".").compactMap { Int($0) }
        let rightParts = right.split(separator: ".").compactMap { Int($0) }
        let maxCount = max(leftParts.count, rightParts.count)

        for index in 0..<maxCount {
            let leftValue = index < leftParts.count ? leftParts[index] : 0
            let rightValue = index < rightParts.count ? rightParts[index] : 0

            if leftValue != rightValue {
                return leftValue < rightValue
            }
        }

        return false
    }

    private static let iso8601Parser = ISO8601DateFormatter()

    static let displayTimeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .none
        f.timeStyle = .short
        return f
    }()

    private static let iso8601Writer = ISO8601DateFormatter()
    private static let legacyMigrationKey = "versionReport.legacyStateMigrationDone"

    func loadMonitoredApps() -> [MonitoredApp] {

        let configs = loadAppConfigs()

        if !UserDefaults.standard.bool(forKey: Self.legacyMigrationKey) {
            migrateAppState(for: configs)
            UserDefaults.standard.set(true, forKey: Self.legacyMigrationKey)
        }

        let appState = loadAppState()

        var loadedApps: [MonitoredApp] = []

        for config in configs {

            let state = appState[config.id]

            loadedApps.append(
                MonitoredApp(
                    id: config.id,
                    name: config.name,
                    version: state?.version ?? "Unknown",
                    previousVersion: state?.previousVersion ?? "Unknown",
                    sourceType: config.source.displayName,
                    lastChecked: state.flatMap { Self.iso8601Parser.date(from: $0.lastChecked) },
                    lastUpdated: state.flatMap { $0.lastUpdated.flatMap { Self.iso8601Parser.date(from: $0) } },
                    iconName: config.id,
                    hasUnreadUpdate: state?.hasUnreadUpdate ?? false
                )
            )

        }

        return loadedApps.sorted {
            $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }

    }

    func icon(forID id: String) -> NSImage {
        let iconPath = baseURL
            .appendingPathComponent("icons")
            .appendingPathComponent("\(id).png")
            .path

        if let icon = NSImage(contentsOfFile: iconPath) {
            icon.isTemplate = false
            return icon
        }

        return NSWorkspace.shared.icon(for: UTType.application)
    }

    func icon(for app: MonitoredApp) -> NSImage {
        icon(forID: app.iconName)
    }


    func requestNotificationPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { granted, error in
            if let error = error {
                print("Failed to request notification permission: \(error)")
            }
        }
    }

    func sendVersionUpdateNotification(appName: String, previousVersion: String, currentVersion: String) {
        let content = UNMutableNotificationContent()
        content.title = "Version Report"
        content.body = "\(appName) updated from \(previousVersion) to \(currentVersion)"
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: "version-report-\(appName)-\(currentVersion)",
            content: content,
            trigger: nil
        )

        UNUserNotificationCenter.current().add(request) { error in
            if let error = error {
                print("Failed to send notification: \(error)")
            }
        }
    }

    func sendTeamsUpdateNotification(for updates: [(appName: String, previousVersion: String, currentVersion: String)]) async {

        guard let webhookURLString = KeychainHelper.shared.loadTeamsWebhookURL()?.trimmingCharacters(in: .whitespacesAndNewlines),
              !webhookURLString.isEmpty,
              let webhookURL = URL(string: webhookURLString) else {
            return
        }

        let titleText = updates.count == 1 ? "Version Report Update" : "Version Report Updates"
        let summaryText: String

        if let update = updates.first, updates.count == 1 {
            summaryText = "\(update.appName) version \(update.currentVersion) is now available."
        } else {
            summaryText = "\(updates.count) app updates are now available."
        }

        let facts: [[String: String]] = updates.map { update in
            [
                "title": update.appName,
                "value": "\(update.previousVersion) → \(update.currentVersion)"
            ]
        }

        let cardBody: [[String: Any]] = [
            [
                "type": "TextBlock",
                "text": titleText,
                "weight": "Bolder",
                "size": "Medium"
            ],
            [
                "type": "TextBlock",
                "text": summaryText,
                "wrap": true
            ],
            [
                "type": "FactSet",
                "facts": facts
            ]
        ]

        let adaptiveCard: [String: Any] = [
            "$schema": "http://adaptivecards.io/schemas/adaptive-card.json",
            "type": "AdaptiveCard",
            "version": "1.4",
            "body": cardBody
        ]

        let payload: [String: Any] = [
            "type": "message",
            "attachments": [
                [
                    "contentType": "application/vnd.microsoft.card.adaptive",
                    "contentUrl": NSNull(),
                    "content": adaptiveCard
                ]
            ]
        ]

        guard let payloadData = try? JSONSerialization.data(withJSONObject: payload) else {
            print("Failed to create Teams update notification payload.")
            return
        }

        var request = URLRequest(url: webhookURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = payloadData

        do {
            let (responseData, response) = try await URLSession.shared.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse else {
                print("Teams update notification failed: no HTTP response.")
                return
            }

            guard (200...299).contains(httpResponse.statusCode) else {
                let responseText = String(data: responseData, encoding: .utf8) ?? "No response body."
                print("Teams update notification failed: HTTP \(httpResponse.statusCode). \(responseText)")
                return
            }
        } catch {
            print("Teams update notification failed: \(error)")
        }
    }

    func scheduleNextHourlyCheck() {

        hourlyTimer?.invalidate()

        let calendar = Calendar.current
        let now = Date()

        guard let nextHour = calendar.nextDate(
            after: now,
            matching: DateComponents(minute: 0, second: 0),
            matchingPolicy: .nextTime
        ) else {
            return
        }

        let interval = nextHour.timeIntervalSince(now)

        hourlyTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: false) { [weak self] _ in
            self?.runVersionCheck()
            self?.scheduleNextHourlyCheck()
        }

    }

    func stopHourlyCheck() {
        hourlyTimer?.invalidate()
        hourlyTimer = nil
    }
}
