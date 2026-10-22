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

    func testBundledLibraryMergeMatchesAppsByStableID() throws {
        let bundledURL = testDirectory.appendingPathComponent("bundled-library.json")
        let bundledConfig = makeConfig(
            id: "adobe_photoshop",
            name: "Photoshop"
        )
        let customConfig = makeConfig(id: "custom_tool", name: "Custom Tool")
        let existingBundledConfig = makeConfig(
            id: "adobe_photoshop",
            name: "Adobe Photoshop"
        )
        try JSONEncoder().encode([bundledConfig]).write(to: bundledURL)

        let service = makeService(bundledLibraryURL: bundledURL)
        service.saveAppLibrary([existingBundledConfig, customConfig])
        service.mergeBundledAppLibrary()

        let library = service.loadAppLibrary()
        XCTAssertEqual(library.first(where: { $0.id == bundledConfig.id })?.name, "Photoshop")
        XCTAssertEqual(library.first(where: { $0.id == bundledConfig.id })?.parserValue, ".version")
        XCTAssertEqual(library.first(where: { $0.id == customConfig.id })?.name, "Custom Tool")
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
