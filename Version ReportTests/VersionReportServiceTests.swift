import XCTest
@testable import Version_Report

@MainActor
final class VersionReportServiceTests: XCTestCase {
    private var testDirectory: URL!

    override func setUpWithError() throws {
        testDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("VersionReportTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(
            at: testDirectory,
            withIntermediateDirectories: true
        )
    }

    override func tearDownWithError() throws {
        try FileManager.default.removeItem(at: testDirectory)
    }

    func testLegacyStateMigratesFromDisplayNameToStableID() throws {
        // The migration runs once per Mac, gated by a flag in the host app's real defaults.
        let migrationKey = "versionReport.legacyStateMigrationDone"
        let originalFlag = UserDefaults.standard.object(forKey: migrationKey)
        UserDefaults.standard.removeObject(forKey: migrationKey)
        defer { UserDefaults.standard.set(originalFlag, forKey: migrationKey) }

        let service = makeService()
        let config = makeConfig(id: "adobe_photoshop", name: "Adobe Photoshop")
        let state = makeState(version: "26.0")

        service.saveAppConfigs([config])
        try writeState([config.name: state])

        _ = service.loadMonitoredApps()

        let migratedState = service.loadAppState()
        XCTAssertEqual(migratedState[config.id]?.version, "26.0")
        XCTAssertNil(migratedState[config.name])
    }

    func testRenamingAppPreservesObservedVersionState() {
        let service = makeService()
        let original = makeConfig(id: "adobe_photoshop", name: "Adobe Photoshop")
        let renamed = makeConfig(id: "ignored", name: "Photoshop")

        service.saveAppConfigs([original])
        service.saveAppState([original.id: makeState(version: "26.0")])

        let updated = service.updateAppConfig(renamed, replacingID: original.id)

        XCTAssertEqual(updated?.id, original.id)
        XCTAssertEqual(updated?.name, "Photoshop")
        XCTAssertEqual(service.loadAppState()[original.id]?.version, "26.0")
    }

    func testDuplicateIDsAreMadeUniqueDuringMigration() throws {
        let configs = [
            makeConfig(id: "zoom", name: "Zoom"),
            makeConfig(id: "zoom", name: "Zoom Workplace")
        ]
        let data = try JSONEncoder().encode(configs)
        try data.write(to: testDirectory.appendingPathComponent("apps.json"))

        let configsAfterMigration = makeService().loadAppConfigs()

        XCTAssertEqual(configsAfterMigration.map(\.id), ["zoom", "zoom_2"])
    }

    func testBundledLibraryMergeKeepsUserEntriesAndAddsNewOnes() throws {
        let bundledURL = testDirectory.appendingPathComponent("bundled-library.json")
        var bundledPhotoshop = makeConfig(id: "adobe_photoshop", name: "Photoshop")
        bundledPhotoshop.vendor = "Adobe"
        let bundledNewApp = makeConfig(id: "new_app", name: "New App")
        try JSONEncoder().encode([bundledPhotoshop, bundledNewApp]).write(to: bundledURL)

        let userPhotoshop = makeConfig(id: "adobe_photoshop", name: "Adobe Photoshop")
        let customConfig = makeConfig(id: "custom_tool", name: "Custom Tool")

        let service = makeService(bundledLibraryURL: bundledURL)
        service.saveAppLibrary([userPhotoshop, customConfig])
        service.mergeBundledAppLibrary()

        let library = service.loadAppLibrary()
        let photoshop = library.first(where: { $0.id == "adobe_photoshop" })
        XCTAssertEqual(photoshop?.name, "Adobe Photoshop", "The user's existing entry is never overwritten")
        XCTAssertEqual(photoshop?.vendor, "Adobe", "A never-set vendor is backfilled from the bundled library")
        XCTAssertEqual(library.first(where: { $0.id == "custom_tool" })?.name, "Custom Tool")
        XCTAssertNotNil(library.first(where: { $0.id == "new_app" }), "New bundled entries are added")
    }

    func testAddFromLibraryUsesBundledDefinitionWithoutTouchingLocalLibrary() throws {
        let bundledURL = testDirectory.appendingPathComponent("bundled-library.json")
        let bundledSoundQ = makeConfig(id: "soundq", name: "SoundQ", parserValue: ".version")
        try JSONEncoder().encode([bundledSoundQ]).write(to: bundledURL)

        let staleSoundQ = makeConfig(id: "soundq", name: "SoundQ", parserValue: ".old")
        let customConfig = makeConfig(id: "custom_tool", name: "Custom Tool", parserValue: ".mine")

        let service = makeService(bundledLibraryURL: bundledURL)
        service.saveAppLibrary([staleSoundQ, customConfig])

        let offered = service.loadAppLibraryForAdding()
        XCTAssertEqual(offered.first(where: { $0.id == "soundq" }), bundledSoundQ)
        XCTAssertEqual(offered.first(where: { $0.id == "custom_tool" }), customConfig)

        let local = service.loadAppLibrary()
        XCTAssertEqual(local.first(where: { $0.id == "soundq" }), staleSoundQ, "The local library file is not modified")
    }

    func testParserAndVersionComparisonBehavior() {
        let service = makeService()

        XCTAssertEqual(
            service.firstRegexVersionMatch(
                in: "Photoshop version 26.1.2 is available",
                pattern: "Photoshop version [0-9]+(\\.[0-9]+)+"
            ),
            "26.1.2"
        )
        XCTAssertEqual(
            service.highestRegexVersionMatch(
                in: "Versions 2.9.0, 2.10.0, and 2.3.1",
                pattern: "[0-9]+(\\.[0-9]+)+"
            ),
            "2.10.0"
        )
        XCTAssertTrue(service.compareVersions("2.9.0", "2.10.0"))
        XCTAssertFalse(service.compareVersions("2.10.0", "2.9.0"))
    }

    func testMarkingAnUpdateAsReadUpdatesTheVisibleUnreadCount() {
        let service = makeService()
        let config = makeConfig(id: "adobe_photoshop", name: "Adobe Photoshop")

        service.saveAppConfigs([config])
        service.saveAppState([
            config.id: makeState(version: "26.0", hasUnreadUpdate: true)
        ])
        service.loadApps()

        XCTAssertEqual(service.unreadUpdateCount(), 1)
        XCTAssertTrue(service.apps[0].hasUnreadUpdate)

        service.markUpdatesAsRead(for: [config.id])

        XCTAssertEqual(service.unreadUpdateCount(), 0)
        XCTAssertFalse(service.apps[0].hasUnreadUpdate)
        XCTAssertFalse(service.loadAppState()[config.id]?.hasUnreadUpdate ?? true)
    }

    func testMarkingAnUpdateAsUnreadUpdatesTheVisibleUnreadCount() {
        let service = makeService()
        let config = makeConfig(id: "adobe_photoshop", name: "Adobe Photoshop")

        service.saveAppConfigs([config])
        service.saveAppState([
            config.id: makeState(version: "26.0")
        ])
        service.loadApps()

        service.markUpdatesAsUnread(for: [config.id])

        XCTAssertEqual(service.unreadUpdateCount(), 1)
        XCTAssertTrue(service.apps[0].hasUnreadUpdate)
        XCTAssertTrue(service.loadAppState()[config.id]?.hasUnreadUpdate ?? false)
    }

    private func makeService(bundledLibraryURL: URL? = nil) -> VersionReportService {
        VersionReportService(
            baseURL: testDirectory,
            bundledAppLibraryURL: bundledLibraryURL
        )
    }

    private func makeConfig(
        id: String,
        name: String,
        parserValue: String = ".version"
    ) -> AppConfig {
        AppConfig(
            id: id,
            name: name,
            source: .custom(
                versionURL: URL(string: "https://example.com/releases")!,
                parserType: "jq",
                parserValue: parserValue
            )
        )
    }

    private func makeState(version: String, hasUnreadUpdate: Bool = false) -> AppState {
        AppState(
            version: version,
            previousVersion: nil,
            lastChecked: ISO8601DateFormatter().string(from: Date()),
            lastUpdated: nil,
            hasUnreadUpdate: hasUnreadUpdate
        )
    }

    private func writeState(_ state: [String: AppState]) throws {
        let data = try JSONEncoder().encode(state)
        try data.write(to: testDirectory.appendingPathComponent("app-state.json"))
    }
}


final class UpdateCycleTests: XCTestCase {

    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func history(daysAgo: [Double], kind: ReleaseHistoryEntry.Kind = .released) -> [ReleaseHistoryEntry] {
        daysAgo.enumerated().map { index, days in
            ReleaseHistoryEntry(version: "1.\(index)", date: now.addingTimeInterval(-days * 86400), kind: kind)
        }
    }

    func testMonthlyAppPastTwoCyclesIsOverdue() throws {
        let cycle = try XCTUnwrap(UpdateCycle.from(history(daysAgo: [70, 100, 130, 160, 190]), now: now))
        XCTAssertEqual(cycle.typicalDays, 30, accuracy: 0.01)
        XCTAssertTrue(cycle.isOverdue)
    }

    func testMonthlyAppWithinCycleIsOnSchedule() throws {
        let cycle = try XCTUnwrap(UpdateCycle.from(history(daysAgo: [20, 50, 80, 110, 140]), now: now))
        XCTAssertFalse(cycle.isOverdue)
    }

    func testWeeklyAppNotFlaggedBeforeThirtyDays() throws {
        let weekly = (0..<20).map { Double(25 + $0 * 7) }
        let cycle = try XCTUnwrap(UpdateCycle.from(history(daysAgo: weekly), now: now))
        XCTAssertEqual(cycle.typicalDays, 7, accuracy: 0.01)
        XCTAssertFalse(cycle.isOverdue, "25 days quiet is under the 30-day floor")
    }

    func testLaunchBurstHasNoCycle() {
        XCTAssertNil(UpdateCycle.from(history(daysAgo: [15, 16, 17, 18, 19, 20, 21]), now: now))
    }

    func testTooFewReleasesHasNoCycle() {
        XCTAssertNil(UpdateCycle.from(history(daysAgo: [10, 100, 200]), now: now))
    }

    func testFirstSeenDatesAreIgnored() {
        var entries = history(daysAgo: [70, 100, 130])
        entries.append(ReleaseHistoryEntry(version: "0.9", date: now.addingTimeInterval(-400 * 86400), kind: .firstSeen))
        XCTAssertNil(UpdateCycle.from(entries, now: now), "Only three real releases, so no cycle yet")
    }

    func testOneLongGapDoesNotSkewTypicalCycle() throws {
        let cycle = try XCTUnwrap(UpdateCycle.from(history(daysAgo: [10, 40, 70, 100, 400]), now: now))
        XCTAssertEqual(cycle.typicalDays, 30, accuracy: 0.01)
    }
}


final class LibraryDocumentationTests: XCTestCase {

    /// LIBRARY.md is generated from the bundled library. If this fails, run
    /// `python3 scripts/generate-library-md.py` and commit the result.
    func testLibraryMarkdownListsEveryBundledApp() throws {
        let repoRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let libraryURL = repoRoot.appendingPathComponent("Version Report/Resources/app-library.json")
        let markdownURL = repoRoot.appendingPathComponent("LIBRARY.md")

        let configs = try JSONDecoder().decode([AppConfig].self, from: Data(contentsOf: libraryURL))
        let markdown = try String(contentsOf: markdownURL, encoding: .utf8)

        let documentedNames = markdown
            .split(separator: "\n")
            .filter { $0.hasPrefix("| ") && !$0.hasPrefix("| App |") }
            .compactMap { line in
                line.dropFirst(2)
                    .components(separatedBy: " | ")
                    .first?
                    .replacingOccurrences(of: "\\|", with: "|")
            }

        XCTAssertEqual(
            documentedNames.sorted(),
            configs.map(\.name).sorted(),
            "LIBRARY.md is out of date. Run: python3 scripts/generate-library-md.py"
        )
        XCTAssertTrue(
            markdown.contains("**\(configs.count) apps**"),
            "LIBRARY.md app count is out of date. Run: python3 scripts/generate-library-md.py"
        )
    }
}
