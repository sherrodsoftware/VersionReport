import Foundation

/// Keeps test runs and profiling launches away from the user's real data, settings,
/// notifications, and updates.
///
/// Isolated mode is on when Version Report runs as the unit-test host, or when it's
/// launched with `VERSION_REPORT_ISOLATED=1`, for example:
///
///     open -n --env VERSION_REPORT_ISOLATED=1 \
///         --env VERSION_REPORT_DATA_DIR=/tmp/vr-profile "Version Report.app"
///
/// While isolated:
/// - Data lives in `VERSION_REPORT_DATA_DIR` if set, otherwise in a new temporary folder.
/// - The service's flags and settings use their own defaults domain.
/// - Sparkle doesn't start, and nothing is sent to Notification Center or Microsoft Teams.
/// - The notification permission request and the installed-apps prompt don't appear.
/// - The launch version check runs only when `VERSION_REPORT_LAUNCH_CHECK=1`, or by
///   default for profiling launches (`VERSION_REPORT_LAUNCH_CHECK=0` turns it off).
enum RunEnvironment {

    private static let environment = ProcessInfo.processInfo.environment

    /// Running as the host app for unit tests.
    static let isTestHost: Bool =
        environment["XCTestConfigurationFilePath"] != nil
        || environment["XCTestBundlePath"] != nil
        || NSClassFromString("XCTestCase") != nil

    static let isIsolated: Bool = isTestHost || environment["VERSION_REPORT_ISOLATED"] == "1"

    /// Where Version Report keeps its data.
    static let dataDirectory: URL = {
        if isIsolated {
            if let path = environment["VERSION_REPORT_DATA_DIR"], !path.isEmpty {
                return URL(fileURLWithPath: (path as NSString).expandingTildeInPath, isDirectory: true)
            }
            return FileManager.default.temporaryDirectory
                .appendingPathComponent("VersionReport-isolated-\(UUID().uuidString)", isDirectory: true)
        }

        guard let url = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            fatalError("Application Support directory not found")
        }
        return url.appendingPathComponent("Version Report")
    }()

    static let isolatedDefaultsSuite = "com.sherrodsoftware.VersionReport.isolated"

    /// Defaults for the service's own flags and settings. Isolated runs use a separate
    /// domain, cleared at each launch, so they never mark the real data as migrated,
    /// seeded, or backfilled.
    static let defaults: UserDefaults = {
        guard isIsolated, let suite = UserDefaults(suiteName: isolatedDefaultsSuite) else {
            return .standard
        }
        suite.removePersistentDomain(forName: isolatedDefaultsSuite)
        return suite
    }()

    /// Whether to check every source at launch.
    static let runsLaunchCheck: Bool = {
        switch environment["VERSION_REPORT_LAUNCH_CHECK"] {
        case "1": return true
        case "0": return false
        default: return !isTestHost
        }
    }()

    /// Sparkle, notifications, and other effects outside the app.
    static var allowsExternalEffects: Bool { !isIsolated }
}
