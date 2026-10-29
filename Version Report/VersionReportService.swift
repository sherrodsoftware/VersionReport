import Foundation
import AppKit
import UserNotifications
import UniformTypeIdentifiers
import Combine

enum CheckFrequency: String, CaseIterable {
    case onLaunch = "onLaunch"
    case hourly = "hourly"
    case every6Hours = "every6Hours"
    case daily = "daily"
    case manual = "manual"

    var displayName: String {
        switch self {
        case .onLaunch:    return "On launch"
        case .hourly:      return "Every hour"
        case .every6Hours: return "Every 6 hours"
        case .daily:       return "Every day"
        case .manual:      return "Manually only"
        }
    }

    var interval: TimeInterval? {
        switch self {
        case .onLaunch:    return nil
        case .hourly:      return 3600
        case .every6Hours: return 6 * 3600
        case .daily:       return 24 * 3600
        case .manual:      return nil
        }
    }
}

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
    case appstore(pageURL: URL, parserType: String, parserValue: String)
    case custom(versionURL: URL, parserType: String, parserValue: String)

    var displayName: String {
        switch self {
        case .homebrew: return "Homebrew Cask"
        case .sparkle: return "Sparkle Feed"
        case .github: return "GitHub Releases"
        case .appstore: return "App Store"
        case .custom(_, let parserType, _): return "Custom (\(parserType))"
        }
    }

    var latestReleaseURL: URL? {
        switch self {
        case .homebrew(let caskName):
            return URL(string: "https://formulae.brew.sh/cask/\(caskName)")
        case .github(let repoPath):
            return URL(string: "https://github.com/\(repoPath)/releases/latest")
        case .appstore:
            return nil
        case .custom(let versionURL, _, _):
            return versionURL
        case .sparkle:
            return nil
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
        case "appstore":
            self = .appstore(
                pageURL: try container.decode(URL.self, forKey: .versionURL),
                parserType: try container.decode(String.self, forKey: .parserType),
                parserValue: try container.decode(String.self, forKey: .parserValue)
            )
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
        case .appstore(let pageURL, let parserType, let parserValue):
            try container.encode("appstore", forKey: .sourceType)
            try container.encode(pageURL, forKey: .versionURL)
            try container.encode(parserType, forKey: .parserType)
            try container.encode(parserValue, forKey: .parserValue)
        case .custom(let versionURL, let parserType, let parserValue):
            try container.encode(versionURL, forKey: .versionURL)
            try container.encode(parserType, forKey: .parserType)
            try container.encode(parserValue, forKey: .parserValue)
        }
    }
}

struct AppConfig: Codable, Identifiable, Equatable {
    enum CodingKeys: String, CodingKey {
        case id, name, vendor
    }

    var id: String
    let name: String
    let source: AppSource
    // nil = never set (eligible for backfill from the bundled library); "" = user cleared it.
    var vendor: String?

    var displayVendor: String? {
        guard let trimmed = vendor?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else { return nil }
        return trimmed
    }

    init(id: String? = nil, name: String, source: AppSource, vendor: String? = nil) {
        self.id = id ?? Self.defaultID(for: name)
        self.name = name
        self.source = source
        self.vendor = vendor
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let name = try container.decode(String.self, forKey: .name)
        self.init(
            id: try container.decodeIfPresent(String.self, forKey: .id),
            name: name,
            source: try AppSource(from: decoder),
            vendor: try container.decodeIfPresent(String.self, forKey: .vendor)
        )
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encodeIfPresent(vendor, forKey: .vendor)
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
    var lastCheckError: String?

    init(version: String, previousVersion: String?, lastChecked: String, lastUpdated: String?, hasUnreadUpdate: Bool, lastCheckError: String? = nil) {
        self.version = version
        self.previousVersion = previousVersion
        self.lastChecked = lastChecked
        self.lastUpdated = lastUpdated
        self.hasUnreadUpdate = hasUnreadUpdate
        self.lastCheckError = lastCheckError
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        version = try container.decode(String.self, forKey: .version)
        previousVersion = try container.decodeIfPresent(String.self, forKey: .previousVersion)
        lastChecked = try container.decode(String.self, forKey: .lastChecked)
        let rawLastUpdated = try container.decodeIfPresent(String.self, forKey: .lastUpdated)
        lastUpdated = rawLastUpdated == "Never" ? nil : rawLastUpdated
        hasUnreadUpdate = try container.decodeIfPresent(Bool.self, forKey: .hasUnreadUpdate) ?? false
        lastCheckError = try container.decodeIfPresent(String.self, forKey: .lastCheckError)
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
    @Published var checkHadErrors = false
    @Published var pendingLibraryConflicts: [LibraryConflict] = []
    @Published var groups: [AppGroup] = []
    @Published var smartGroups: [SmartGroup] = []

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

    private var smartGroupsURL: URL {
        baseURL.appendingPathComponent("smart-groups.json")
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

    private func loadSmartGroups() -> [SmartGroup] {
        guard let data = try? Data(contentsOf: smartGroupsURL),
              let loaded = try? JSONDecoder().decode([SmartGroup].self, from: data) else {
            return []
        }
        return loaded
    }

    private func saveSmartGroups(_ smartGroups: [SmartGroup]) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(smartGroups) else { return }
        try? data.write(to: smartGroupsURL)
    }

    func createSmartGroup(_ smartGroup: SmartGroup) {
        var updated = smartGroups
        updated.append(smartGroup)
        saveSmartGroups(updated)
        smartGroups = updated
    }

    func updateSmartGroup(_ smartGroup: SmartGroup) {
        var updated = smartGroups
        guard let idx = updated.firstIndex(where: { $0.id == smartGroup.id }) else { return }
        updated[idx] = smartGroup
        saveSmartGroups(updated)
        smartGroups = updated
    }

    func deleteSmartGroup(id: String) {
        let updated = smartGroups.filter { $0.id != id }
        saveSmartGroups(updated)
        smartGroups = updated
    }

    func moveSmartGroups(from source: IndexSet, to destination: Int) {
        var updated = smartGroups
        let items = source.sorted().map { updated[$0] }
        for index in source.sorted().reversed() { updated.remove(at: index) }
        let adjustedDest = destination - source.filter { $0 < destination }.count
        updated.insert(contentsOf: items, at: max(0, min(adjustedDest, updated.count)))
        saveSmartGroups(updated)
        smartGroups = updated
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
        smartGroups = loadSmartGroups()
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
        backfillVendorsInMonitoredApps()
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
            if let index = userLibraryConfigs.firstIndex(where: { $0.id == bundledConfig.id }) {
                if userLibraryConfigs[index].vendor == nil, let vendor = bundledConfig.vendor {
                    userLibraryConfigs[index].vendor = vendor
                    didChangeLibrary = true
                }
            } else {
                // New entry: add it; never overwrite an entry the user already has.
                userLibraryConfigs.append(bundledConfig)
                didChangeLibrary = true
            }
        }

        guard didChangeLibrary else { return }
        saveAppLibrary(userLibraryConfigs)
    }

    func backfillVendorsInMonitoredApps() {

        guard let bundledLibraryURL = bundledAppLibraryURL,
              let bundledData = try? Data(contentsOf: bundledLibraryURL),
              let bundledConfigs = try? JSONDecoder().decode([AppConfig].self, from: bundledData) else {
            return
        }

        let bundledVendors = Dictionary(
            bundledConfigs.compactMap { config in config.vendor.map { (config.id, $0) } },
            uniquingKeysWith: { first, _ in first }
        )

        var configs = loadAppConfigs()
        var didChange = false

        for index in configs.indices where configs[index].vendor == nil {
            if let vendor = bundledVendors[configs[index].id] {
                configs[index].vendor = vendor
                didChange = true
            }
        }

        if didChange {
            saveAppConfigs(configs)
        }
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
            await applyDetectedVendorIfNeeded(for: config)
        }

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

    // Homebrew casks and Sparkle feeds carry no vendor metadata, so only these two sources are detectable.
    func detectVendor(for source: AppSource) async -> String? {
        switch source {
        case .appstore(let pageURL, _, _):
            guard let id = iTunesID(from: pageURL),
                  let url = URL(string: "https://itunes.apple.com/lookup?id=\(id)&entity=macSoftware"),
                  let (data, _) = try? await URLSession.shared.data(from: url),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let result = (json["results"] as? [[String: Any]])?.first,
                  let artist = result["artistName"] as? String else { return nil }
            return artist.replacingOccurrences(
                of: #",?\s+(Inc\.?|LLC|L\.L\.C\.|Ltd\.?|Limited|GmbH|Corp\.?|Corporation|Co\.?|S\.A\.|AB|Pty\.? Ltd\.?)$"#,
                with: "",
                options: [.regularExpression, .caseInsensitive]
            )

        case .github(let repoPath):
            guard let owner = Self.normalizeGitHubRepoPath(repoPath).split(separator: "/").first,
                  let url = URL(string: "https://api.github.com/users/\(owner)") else { return nil }
            var request = URLRequest(url: url)
            request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
            guard let (data, response) = try? await URLSession.shared.data(for: request),
                  (response as? HTTPURLResponse)?.statusCode == 200,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
            let name = (json["name"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
            return (name?.isEmpty == false ? name : nil) ?? json["login"] as? String

        default:
            return nil
        }
    }

    private func applyDetectedVendorIfNeeded(for config: AppConfig) async {
        guard config.vendor == nil, let vendor = await detectVendor(for: config.source) else { return }

        await MainActor.run {
            var configs = loadAppConfigs()
            guard let index = configs.firstIndex(where: { $0.id == config.id }),
                  configs[index].vendor == nil else { return }
            configs[index].vendor = vendor
            saveAppConfigs(configs)
            apps = loadMonitoredApps()
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
            source: config.source,
            vendor: config.vendor
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

        case .appstore(let pageURL, let parserType, let parserValue):
            let (data, _) = try await URLSession.shared.data(from: pageURL)
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

    private func iTunesID(from url: URL) -> Int? {
        // iTunes Lookup API: ?id=12345
        if let id = URLComponents(url: url, resolvingAgainstBaseURL: false)?
            .queryItems?.first(where: { $0.name == "id" })?.value.flatMap(Int.init) {
            return id
        }
        // App Store page URL: /id12345
        if let match = url.path.range(of: #"/id(\d+)"#, options: .regularExpression) {
            return Int(url.path[match].dropFirst(3))
        }
        return nil
    }

    private func batchLookupAppStoreVersions(configs: [(config: AppConfig, pageURL: URL)]) async -> [String: String] {
        let pairs = configs.compactMap { item -> (Int, String)? in
            guard let id = iTunesID(from: item.pageURL) else { return nil }
            return (id, item.config.id)
        }
        guard !pairs.isEmpty,
              let url = URL(string: "https://itunes.apple.com/lookup?id=\(pairs.map { "\($0.0)" }.joined(separator: ","))&entity=macSoftware") else {
            return [:]
        }
        guard let (data, response) = try? await URLSession.shared.data(from: url) else {
            print("[AppStore batch] network error")
            return [:]
        }
        if let http = response as? HTTPURLResponse, http.statusCode != 200 {
            print("[AppStore batch] HTTP \(http.statusCode)")
            return [:]
        }
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let results = json["results"] as? [[String: Any]] else {
            print("[AppStore batch] unexpected response: \(String(data: data, encoding: .utf8) ?? "<binary>")")
            return [:]
        }
        print("[AppStore batch] got \(results.count) results for \(pairs.count) IDs")

        var trackIdToVersion: [Int: String] = [:]
        for result in results {
            if let trackId = result["trackId"] as? Int, let version = result["version"] as? String {
                trackIdToVersion[trackId] = version
            }
        }
        return Dictionary(uniqueKeysWithValues: pairs.compactMap { (trackId, configId) -> (String, String)? in
            guard let v = trackIdToVersion[trackId] else { return nil }
            return (configId, v)
        })
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

            // Batch-fetch all App Store apps in a single iTunes Lookup API call
            let appStoreItems: [(config: AppConfig, pageURL: URL)] = configs.compactMap { config in
                if case .appstore(let pageURL, _, _) = config.source { return (config, pageURL) }
                return nil
            }
            var batchedVersions = await batchLookupAppStoreVersions(configs: appStoreItems)
            let appStoreIDs = Set(appStoreItems.map { $0.config.id })

            // Fall back to individual lookups for any app the batch missed
            await withTaskGroup(of: (String, String?).self) { group in
                for item in appStoreItems where batchedVersions[item.config.id] == nil {
                    group.addTask {
                        let version = try? await self.fetchCurrentVersion(for: item.config)
                        return (item.config.id, version ?? nil)
                    }
                }
                for await (configID, version) in group {
                    if let version { batchedVersions[configID] = version }
                }
            }

            for item in appStoreItems {
                if let version = batchedVersions[item.config.id] {
                    clearCheckError(for: item.config)
                    let result = updateAppState(version: version, for: item.config)
                    if result.didUpdate {
                        sendVersionUpdateNotification(appName: item.config.name, previousVersion: result.previousVersion, currentVersion: version)
                        detectedUpdates.append((appName: item.config.name, previousVersion: result.previousVersion, currentVersion: version))
                    }
                } else {
                    let msg = "App Store lookup failed"
                    fetchErrors.append("\(item.config.name): \(msg)")
                    saveCheckError(msg, for: item.config)
                }
            }

            await withTaskGroup(of: (AppConfig, String?, Error?).self) { group in
                for config in configs where !appStoreIDs.contains(config.id) {
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
                        saveCheckError(error.localizedDescription, for: config)
                    } else if let version {
                        clearCheckError(for: config)
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
                self.checkHadErrors = !fetchErrors.isEmpty
                if fetchErrors.isEmpty {
                    self.statusMessage = "Check completed at \(completionTime)"
                } else {
                    let count = fetchErrors.count
                    self.statusMessage = count == 1
                        ? "Check completed at \(completionTime) — \(count) app failed"
                        : "Check completed at \(completionTime) — \(count) apps failed"
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

    func saveCheckError(_ message: String, for config: AppConfig) {
        var appState = loadAppState()
        let existing = appState[config.id]
        appState[config.id] = AppState(
            version: existing?.version ?? "Unknown",
            previousVersion: existing?.previousVersion,
            lastChecked: Self.iso8601Writer.string(from: Date()),
            lastUpdated: existing?.lastUpdated,
            hasUnreadUpdate: existing?.hasUnreadUpdate ?? false,
            lastCheckError: message
        )
        saveAppState(appState)
    }

    func clearCheckError(for config: AppConfig) {
        var appState = loadAppState()
        appState[config.id]?.lastCheckError = nil
        saveAppState(appState)
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
                    vendor: config.displayVendor,
                    version: state?.version ?? "Unknown",
                    previousVersion: state?.previousVersion ?? "Unknown",
                    sourceType: config.source.displayName,
                    lastChecked: state.flatMap { Self.iso8601Parser.date(from: $0.lastChecked) },
                    lastUpdated: state.flatMap { $0.lastUpdated.flatMap { Self.iso8601Parser.date(from: $0) } },
                    iconName: config.id,
                    hasUnreadUpdate: state?.hasUnreadUpdate ?? false,
                    lastCheckError: state?.lastCheckError,
                    latestReleaseURL: config.source.latestReleaseURL
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

    func saveCustomIcon(_ image: NSImage, forID id: String) {
        let iconsURL = baseURL.appendingPathComponent("icons")
        try? FileManager.default.createDirectory(at: iconsURL, withIntermediateDirectories: true)
        let dest = iconsURL.appendingPathComponent("\(id).png")

        // Render at 128×128 — enough for @2x display at 64pt
        let size = CGSize(width: 128, height: 128)
        let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 128, pixelsHigh: 128,
                                   bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                                   isPlanar: false, colorSpaceName: .deviceRGB,
                                   bytesPerRow: 0, bitsPerPixel: 0)!
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        image.draw(in: NSRect(origin: .zero, size: size),
                   from: .zero, operation: .copy, fraction: 1)
        NSGraphicsContext.restoreGraphicsState()

        if let data = rep.representation(using: .png, properties: [:]) {
            try? data.write(to: dest)
            objectWillChange.send()
        }
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

    func runLaunchCheck() {
        let freq = CheckFrequency(rawValue: UserDefaults.standard.string(forKey: "checkFrequency") ?? "") ?? .onLaunch
        guard freq != .manual else { return }
        runVersionCheck()
        scheduleAutoCheck()
    }

    func scheduleAutoCheck() {
        hourlyTimer?.invalidate()
        hourlyTimer = nil

        let freq = CheckFrequency(rawValue: UserDefaults.standard.string(forKey: "checkFrequency") ?? "") ?? .onLaunch
        guard let interval = freq.interval else { return }

        hourlyTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            self?.runVersionCheck()
        }
    }

    func stopHourlyCheck() {
        hourlyTimer?.invalidate()
        hourlyTimer = nil
    }
}
