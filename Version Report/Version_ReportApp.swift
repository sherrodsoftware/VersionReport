//
//  Version_ReportApp.swift
//  Version Report
//
//  Created by John Sherrod on 5/28/26.
//

import SwiftUI
import Sparkle

final class VersionReportAppDelegate: NSObject, NSApplicationDelegate {
    let updaterController = SPUStandardUpdaterController(
        startingUpdater: false,
        updaterDelegate: nil,
        userDriverDelegate: nil
    )

    func applicationDidFinishLaunching(_ notification: Notification) {
        requestDockBadgeRefresh()
        // Tests and profiling launches must never check for, download, or install updates.
        guard RunEnvironment.allowsExternalEffects else { return }
        // Delay updater start so the main window appears before any Sparkle dialogs
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            try? self.updaterController.updater.start()
        }
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        requestDockBadgeRefresh()
    }

    private func requestDockBadgeRefresh() {
        DispatchQueue.main.async {
            NotificationCenter.default.post(name: .versionReportRefreshDockBadge, object: nil)
        }
    }
}

@main
struct Version_ReportApp: App {
    @State private var service = VersionReportService()
    @State private var uiState = AppUIState()
    @NSApplicationDelegateAdaptor(VersionReportAppDelegate.self) private var appDelegate

    private var updaterController: SPUStandardUpdaterController { appDelegate.updaterController }

    var body: some Scene {
        WindowGroup {
            ContentView(
                service: service,
                uiState: uiState
            )
        }
        .commands {
            CommandGroup(replacing: .appInfo) {
                Button("About Version Report") {
                    let credits = NSMutableAttributedString()
                    let smallFont = NSFont.systemFont(ofSize: NSFont.smallSystemFontSize)
                    credits.append(NSAttributedString(
                        string: "© Sherrod Software\n",
                        attributes: [.font: smallFont]
                    ))
                    credits.append(NSAttributedString(
                        string: "www.sherrodsoftware.com",
                        attributes: [
                            .font: smallFont,
                            .link: URL(string: "https://www.sherrodsoftware.com")!
                        ]
                    ))
                    NSApplication.shared.orderFrontStandardAboutPanel(options: [
                        .applicationName: "Version Report",
                        .credits: credits
                    ])
                }
            }
            CommandGroup(after: .appInfo) {
                Button("Check for Updates…") {
                    updaterController.checkForUpdates(nil)
                }
            }
            CommandGroup(replacing: .newItem) {
                FileMenuCommands(uiState: uiState)
            }

            CommandGroup(after: .pasteboard) {
                CopyVersionCommand(uiState: uiState)
            }

            CommandGroup(replacing: .help) {
                Button("Version Report Help") {
                    NSWorkspace.shared.open(URL(string: "https://github.com/sherrodsoftware/VersionReport")!)
                }
                .keyboardShortcut("?", modifiers: .command)
            }

            CommandGroup(after: .toolbar) {
                ViewMenuCommands(service: service, uiState: uiState)
            }
        }

        Settings {
            SettingsView()
        }
    }
}
