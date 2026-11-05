import Foundation

struct ReleaseHistoryEntry: Codable, Equatable, Identifiable {
    enum Kind: String, Codable {
        // The vendor's own release date (GitHub, Sparkle, App Store).
        case released
        // The date Version Report noticed the change; can lag the real release by one check interval.
        case detected
        // The version that was current when tracking began; not a release date.
        case firstSeen
    }

    var version: String
    var date: Date
    var kind: Kind

    var id: String { VersionReportService.marketingVersion(version) }
}

private final class SparkleHistoryParser: NSObject, XMLParserDelegate {
    private(set) var releases: [(version: String, date: Date)] = []

    private var inItem = false
    private var currentElement = ""
    private var text = ""
    private var itemVersion: String?
    private var itemShortVersion: String?
    private var itemDate: Date?

    private static let rfc822Formatters: [DateFormatter] = [
        "EEE, dd MMM yyyy HH:mm:ss Z",
        "EEE, d MMM yyyy HH:mm:ss Z",
        "dd MMM yyyy HH:mm:ss Z",
        "EEE, dd MMM yyyy HH:mm Z"
    ].map { format in
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = format
        return formatter
    }

    static func parseDate(_ string: String) -> Date? {
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        for formatter in rfc822Formatters {
            if let date = formatter.date(from: trimmed) { return date }
        }
        return ISO8601DateFormatter().date(from: trimmed)
    }

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?, attributes: [String: String] = [:]) {
        currentElement = elementName
        text = ""
        if elementName == "item" {
            inItem = true
            itemVersion = nil
            itemShortVersion = nil
            itemDate = nil
        } else if inItem, elementName == "enclosure" {
            itemShortVersion = itemShortVersion ?? attributes["sparkle:shortVersionString"]
            itemVersion = itemVersion ?? attributes["sparkle:version"]
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        text += string
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
        guard inItem else { return }
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        switch elementName {
        case "pubDate":
            itemDate = Self.parseDate(value)
        case "sparkle:shortVersionString":
            if !value.isEmpty { itemShortVersion = value }
        case "sparkle:version":
            if !value.isEmpty { itemVersion = value }
        case "item":
            if let version = itemShortVersion ?? itemVersion, let date = itemDate {
                releases.append((version, date))
            }
            inItem = false
        default:
            break
        }
        text = ""
    }
}

extension VersionReportService {

    private var releaseHistoryURL: URL {
        baseURL.appendingPathComponent("release-history.json")
    }

    private static let historySeededKey = "versionReport.releaseHistorySeeded"
    private static let historyBackfilledKey = "versionReport.releaseHistoryBackfilledIDs"

    func loadReleaseHistory() -> [String: [ReleaseHistoryEntry]] {
        guard let data = try? Data(contentsOf: releaseHistoryURL) else { return [:] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return (try? decoder.decode([String: [ReleaseHistoryEntry]].self, from: data)) ?? [:]
    }

    private func saveReleaseHistory(_ history: [String: [ReleaseHistoryEntry]]) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(history) else { return }
        try? data.write(to: releaseHistoryURL, options: .atomic)
        releaseHistory = history
    }

    // Newest first. A vendor release date replaces a detected/first-seen date for the same version.
    private static func merge(_ incoming: [ReleaseHistoryEntry], into existing: [ReleaseHistoryEntry]) -> [ReleaseHistoryEntry] {
        var byVersion = Dictionary(existing.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        for entry in incoming {
            if let current = byVersion[entry.id] {
                if entry.kind == .released && current.kind != .released {
                    byVersion[entry.id] = entry
                }
            } else {
                byVersion[entry.id] = entry
            }
        }
        return byVersion.values.sorted { $0.date > $1.date }
    }

    func recordReleaseHistory(_ entries: [ReleaseHistoryEntry], forAppID id: String) {
        guard !entries.isEmpty else { return }
        var history = loadReleaseHistory()
        let merged = Self.merge(entries, into: history[id] ?? [])
        guard merged != history[id] else { return }
        history[id] = merged
        saveReleaseHistory(history)
    }

    func removeReleaseHistory(forAppID id: String) {
        var history = loadReleaseHistory()
        guard history.removeValue(forKey: id) != nil else { return }
        saveReleaseHistory(history)
        var backfilled = Set(UserDefaults.standard.stringArray(forKey: Self.historyBackfilledKey) ?? [])
        backfilled.remove(id)
        UserDefaults.standard.set(Array(backfilled), forKey: Self.historyBackfilledKey)
    }

    // One-time: turn what app-state.json already knows into the first history entry for each app.
    func seedReleaseHistoryFromStateIfNeeded() {
        let trackedIDs = Set(loadAppConfigs().map(\.id))
        var history = loadReleaseHistory()

        // app-state.json keeps entries for apps that were removed or renamed; don't carry those over.
        let pruned = history.filter { trackedIDs.contains($0.key) }
        if pruned.count != history.count {
            history = pruned
            saveReleaseHistory(history)
        }

        guard !UserDefaults.standard.bool(forKey: Self.historySeededKey) else {
            releaseHistory = history
            return
        }

        let parser = ISO8601DateFormatter()

        for (id, state) in loadAppState() where state.version != "Unknown" && trackedIDs.contains(id) {
            let entry: ReleaseHistoryEntry?
            if let updated = state.lastUpdated.flatMap(parser.date(from:)) {
                entry = ReleaseHistoryEntry(version: state.version, date: updated, kind: .detected)
            } else if let checked = parser.date(from: state.lastChecked) {
                entry = ReleaseHistoryEntry(version: state.version, date: checked, kind: .firstSeen)
            } else {
                entry = nil
            }
            if let entry {
                history[id] = Self.merge([entry], into: history[id] ?? [])
            }
        }

        saveReleaseHistory(history)
        UserDefaults.standard.set(true, forKey: Self.historySeededKey)
    }

    // Fetches vendor release dates once per app for sources that publish them.
    func backfillReleaseHistory(for configs: [AppConfig]) async {
        var backfilled = Set(UserDefaults.standard.stringArray(forKey: Self.historyBackfilledKey) ?? [])

        for config in configs where !backfilled.contains(config.id) {
            let releases: [ReleaseHistoryEntry]?
            switch config.source {
            case .github(let repoPath):
                releases = await fetchGitHubReleaseHistory(repoPath)
            case .sparkle(let feedURL):
                releases = await fetchSparkleReleaseHistory(feedURL)
            case .appstore(let pageURL, _, _):
                releases = await fetchAppStoreReleaseDate(pageURL)
            default:
                releases = []
            }

            // nil = request failed; leave it un-flagged so the next check retries.
            guard let releases else { continue }
            recordReleaseHistory(releases, forAppID: config.id)
            backfilled.insert(config.id)
        }

        UserDefaults.standard.set(Array(backfilled), forKey: Self.historyBackfilledKey)
    }

    private func fetchGitHubReleaseHistory(_ repoPath: String) async -> [ReleaseHistoryEntry]? {
        let normalized = Self.normalizeGitHubRepoPath(repoPath)
        guard !normalized.isEmpty,
              let url = URL(string: "https://api.github.com/repos/\(normalized)/releases?per_page=100") else { return [] }

        var request = URLRequest(url: url)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")

        guard let (data, response) = try? await URLSession.shared.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200 else { return nil }

        struct Release: Decodable {
            let tagName: String
            let publishedAt: Date?
            let draft: Bool
            let prerelease: Bool
            enum CodingKeys: String, CodingKey {
                case tagName = "tag_name", publishedAt = "published_at", draft, prerelease
            }
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let releases = try? decoder.decode([Release].self, from: data) else { return nil }

        return releases.compactMap { release in
            guard !release.draft, !release.prerelease, let date = release.publishedAt else { return nil }
            let version = release.tagName.hasPrefix("v") ? String(release.tagName.dropFirst()) : release.tagName
            return ReleaseHistoryEntry(version: version, date: date, kind: .released)
        }
    }

    private func fetchSparkleReleaseHistory(_ feedURL: URL) async -> [ReleaseHistoryEntry]? {
        guard let (data, response) = try? await URLSession.shared.data(from: feedURL),
              (response as? HTTPURLResponse)?.statusCode == 200 else { return nil }

        let parser = SparkleHistoryParser()
        let xmlParser = XMLParser(data: data)
        xmlParser.delegate = parser
        xmlParser.parse()

        return parser.releases.map { ReleaseHistoryEntry(version: $0.version, date: $0.date, kind: .released) }
    }

    private func fetchAppStoreReleaseDate(_ pageURL: URL) async -> [ReleaseHistoryEntry]? {
        guard let id = iTunesID(from: pageURL),
              let url = URL(string: "https://itunes.apple.com/lookup?id=\(id)&entity=macSoftware") else { return [] }

        guard let (data, response) = try? await URLSession.shared.data(from: url),
              (response as? HTTPURLResponse)?.statusCode == 200,
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }

        guard let result = (json["results"] as? [[String: Any]])?.first,
              let version = result["version"] as? String,
              let dateString = result["currentVersionReleaseDate"] as? String,
              let date = ISO8601DateFormatter().date(from: dateString) else { return [] }

        return [ReleaseHistoryEntry(version: version, date: date, kind: .released)]
    }
}
