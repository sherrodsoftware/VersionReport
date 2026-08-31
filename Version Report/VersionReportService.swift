import Foundation
import AppKit
import UserNotifications
import UniformTypeIdentifiers
import Combine

struct AppConfig: Codable, Identifiable, Equatable {
    enum CodingKeys: String, CodingKey {
        case id
        case name
        case versionURL
        case parserType
        case parserValue
    }

    var id: String
    let name: String
    let versionURL: URL
    let parserType: String
    let parserValue: String

    init(
        id: String? = nil,
        name: String,
        versionURL: URL,
        parserType: String,
        parserValue: String
    ) {
        self.id = id ?? Self.defaultID(for: name)
        self.name = name
        self.versionURL = versionURL
        self.parserType = parserType
        self.parserValue = parserValue
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let name = try container.decode(String.self, forKey: .name)

        self.init(
            id: try container.decodeIfPresent(String.self, forKey: .id),
            name: name,
            versionURL: try container.decode(URL.self, forKey: .versionURL),
            parserType: try container.decode(String.self, forKey: .parserType),
            parserValue: try container.decode(String.self, forKey: .parserValue)
        )
    }

    static func defaultID(for name: String) -> String {
        let components = name.lowercased().split { !$0.isLetter && !$0.isNumber }
        return components.map(String.init).joined(separator: "_")
    }
}

struct AppState: Codable {
    var version: String
    var previousVersion: String?
    var parserType: String
    var lastChecked: String
    var lastUpdated: String
    var hasUnreadUpdate: Bool? = nil
}

final class VersionReportService: ObservableObject {

    @Published var apps: [MonitoredApp] = []
    @Published var isChecking = false
    @Published var statusMessage = "Ready"

    private var hourlyTimer: Timer?
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


    func loadApps() {
        initializeApplicationSupportIfNeeded()
        apps = loadMonitoredApps()
        updateDockBadge()

        if shouldPerformAutomaticCheck() {
            runVersionCheck()
        }
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
            if let existingIndex = userLibraryConfigs.firstIndex(where: { $0.id == bundledConfig.id }) {
                let existingConfig = userLibraryConfigs[existingIndex]

                if existingConfig.name != bundledConfig.name ||
                   existingConfig.versionURL != bundledConfig.versionURL ||
                   existingConfig.parserType != bundledConfig.parserType ||
                   existingConfig.parserValue != bundledConfig.parserValue {
                    userLibraryConfigs[existingIndex] = bundledConfig
                    didChangeLibrary = true
                }
            } else {
                userLibraryConfigs.append(bundledConfig)
                didChangeLibrary = true
            }
        }

        guard didChangeLibrary else {
            return
        }

        saveAppLibrary(userLibraryConfigs)
    }

    func mergeBundledAppConfigsIntoMonitoredApps() {

        guard let bundledLibraryURL = bundledAppLibraryURL,
              let bundledData = try? Data(contentsOf: bundledLibraryURL),
              let bundledConfigs = try? JSONDecoder().decode([AppConfig].self, from: bundledData) else {
            return
        }

        var monitoredConfigs = loadAppConfigs()
        var didChangeConfigs = false

        for bundledConfig in bundledConfigs {
            if let existingIndex = monitoredConfigs.firstIndex(where: { $0.id == bundledConfig.id }) {
                let existingConfig = monitoredConfigs[existingIndex]

                if existingConfig.name != bundledConfig.name ||
                   existingConfig.versionURL != bundledConfig.versionURL ||
                   existingConfig.parserType != bundledConfig.parserType ||
                   existingConfig.parserValue != bundledConfig.parserValue {
                    monitoredConfigs[existingIndex] = bundledConfig
                    didChangeConfigs = true
                }
            }
        }

        guard didChangeConfigs else {
            return
        }

        saveAppConfigs(monitoredConfigs)
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
                        self.updateDockBadge()

                        let formatter = DateFormatter()
                        formatter.timeStyle = .short
                        formatter.dateStyle = .none

                        self.statusMessage = "Added \(config.name) at \(formatter.string(from: Date()))"
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
            versionURL: config.versionURL,
            parserType: config.parserType,
            parserValue: config.parserValue
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

        loadApps()
        updateDockBadge()
    }

    func parserTypes() -> [String] {
        ["jq", "jq_trim_comma", "regex", "highest_version"]
    }

    func fetchCurrentVersion(for config: AppConfig) async throws -> String? {
        let (data, _) = try await URLSession.shared.data(from: config.versionURL)

        switch config.parserType {
        case "jq":
            return parseJSONValue(from: data, keyPath: config.parserValue)

        case "jq_trim_comma":
            return parseJSONValue(from: data, keyPath: config.parserValue)?
                .split(separator: ",", maxSplits: 1)
                .first
                .map(String.init)

        case "regex":
            guard let responseText = String(data: data, encoding: .utf8) else {
                return nil
            }

            return firstRegexVersionMatch(
                in: responseText,
                pattern: config.parserValue
            )

        case "highest_version":
            guard let responseText = String(data: data, encoding: .utf8) else {
                return nil
            }

            return highestRegexVersionMatch(
                in: responseText,
                pattern: config.parserValue
            )

        default:
            return nil
        }
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

            for config in configs {

                do {

                    if let version = try await fetchCurrentVersion(for: config) {
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

                } catch {

                    print("Check failed for \(config.name): \(error)")

                }

            }

            if !detectedUpdates.isEmpty {
                await sendTeamsUpdateNotification(for: detectedUpdates)
            }

            let updatedApps = loadMonitoredApps()

            await MainActor.run {
                self.apps = updatedApps
                self.updateDockBadge()
                self.isChecking = false

                let formatter = DateFormatter()
                formatter.timeStyle = .short
                formatter.dateStyle = .none

                self.statusMessage = "Check completed at \(formatter.string(from: Date()))"
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
        loadAppState().values.filter {
            $0.hasUnreadUpdate ?? false
        }.count
    }

    func updateDockBadge() {
        let count = unreadUpdateCount()

        DispatchQueue.main.async {
            NSApp.dockTile.badgeLabel = count > 0 ? "\(count)" : nil
            NSApp.dockTile.display()
        }
    }

    func clearUnreadUpdate(for appID: String) {
        var appState = loadAppState()

        guard var state = appState[appID], state.hasUnreadUpdate == true else {
            return
        }

        state.hasUnreadUpdate = false
        appState[appID] = state
        saveAppState(appState)

        apps = loadMonitoredApps()
        updateDockBadge()
    }


    func updateAppState(version: String, for config: AppConfig) -> (previousVersion: String, didUpdate: Bool) {

        var appState = loadAppState()
        let existingState = appState[config.id]
        let previousVersion = existingState?.version ?? "Unknown"
        let didUpdate = previousVersion != "Unknown" && previousVersion != version

        let formatter = ISO8601DateFormatter()
        let now = formatter.string(from: Date())

        let lastUpdated: String
        let hasUnreadUpdate: Bool

        if didUpdate {
            lastUpdated = now
            hasUnreadUpdate = true
        } else {
            lastUpdated = existingState?.lastUpdated ?? "Never"
            hasUnreadUpdate = existingState?.hasUnreadUpdate ?? false
        }

        appState[config.id] = AppState(
            version: version,
            previousVersion: didUpdate ? previousVersion : existingState?.previousVersion,
            parserType: config.parserType,
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

    func loadMonitoredApps() -> [MonitoredApp] {

        let configs = loadAppConfigs()
        migrateAppState(for: configs)
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
                    sourceType: state?.parserType ?? config.parserType,
                    lastChecked: formatDisplayDate(state?.lastChecked ?? "Never"),
                    lastUpdated: formatDisplayDate(state?.lastUpdated ?? "Never"),
                    iconName: config.id,
                    hasUnreadUpdate: state?.hasUnreadUpdate ?? false
                )
            )

        }

        return loadedApps.sorted {
            $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }

    }


    func formatDisplayDate(_ value: String) -> String {

        guard value != "Never" else {
            return value
        }

        let parser = ISO8601DateFormatter()

        guard let date = parser.date(from: value) else {
            return value
        }

        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short

        return formatter.string(from: date)
    }

    func icon(for app: MonitoredApp) -> NSImage {
        let iconPath = baseURL
            .appendingPathComponent("icons")
            .appendingPathComponent("\(app.iconName).png")
            .path

        if let icon = NSImage(contentsOfFile: iconPath) {
            icon.isTemplate = false
            return icon
        }

        return NSWorkspace.shared.icon(for: UTType.application)
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

    func shouldPerformAutomaticCheck() -> Bool {
        let appState = loadAppState()
        let parser = ISO8601DateFormatter()

        let mostRecentCheck = appState.values
            .compactMap { parser.date(from: $0.lastChecked) }
            .max()

        guard let mostRecentCheck else {
            return true
        }

        return Date().timeIntervalSince(mostRecentCheck) > 90 * 60
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

        hourlyTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: false) { _ in
            self.runVersionCheck()
            self.scheduleNextHourlyCheck()
        }

    }

    func stopHourlyCheck() {
        hourlyTimer?.invalidate()
        hourlyTimer = nil
    }
}
