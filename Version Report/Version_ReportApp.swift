//
//  Version_ReportApp.swift
//  Version Report
//
//  Created by John Sherrod on 5/28/26.
//

import SwiftUI

final class VersionReportAppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        requestDockBadgeRefresh()
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
    @StateObject private var service = VersionReportService()
    @StateObject private var uiState = AppUIState()
    @NSApplicationDelegateAdaptor(VersionReportAppDelegate.self) private var appDelegate
    @AppStorage("showSourceColumn") private var showSourceColumn = false
    @AppStorage("showBuildNumberColumn") private var showBuildNumberColumn = false
    @AppStorage("showPreviousVersionColumn") private var showPreviousVersionColumn = false

    var body: some Scene {
        WindowGroup {
            ContentView(
                service: service,
                uiState: uiState
            )
        }
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("New Group") {
                    uiState.onNewGroupRequested()
                }
                .keyboardShortcut("n", modifiers: [.command])

                Button("New Group from Selection") {
                    uiState.onNewGroupFromSelectionRequested()
                }
                .keyboardShortcut("n", modifiers: [.command, .shift])
                .disabled(uiState.selectedAppIDs.isEmpty)

                Divider()

                Button("Add App…") {
                    uiState.editingOriginalAppID = nil
                    uiState.showingAddAppSheet = true
                }
                .keyboardShortcut("a", modifiers: [.command, .shift])

                Button("Add App From Library…") {
                    uiState.showingLibrarySheet = true
                }
                .keyboardShortcut("l", modifiers: [.command, .option])

                Button("Edit Selected App…") {
                    uiState.onEditRequested()
                }
                .keyboardShortcut("e", modifiers: [.command, .option])
                .disabled(uiState.selectedAppIDs.isEmpty)

                Button("Delete Selected App") {
                    uiState.onDeleteRequested()
                }
                .keyboardShortcut(.delete, modifiers: [])
                .disabled(uiState.selectedAppIDs.isEmpty)

                Button("Add Selected App To Library") {
                    uiState.onAddToLibraryRequested()
                }
                .disabled(uiState.selectedAppIDs.isEmpty)

                Divider()
                Button("Check for Updates…") {
                    NotificationCenter.default.post(name: .versionReportCheckNow, object: nil)
                }
                .keyboardShortcut("r", modifiers: [.command])

                Divider()
            }

            CommandGroup(after: .pasteboard) {
                Button("Copy Version") {
                    NotificationCenter.default.post(name: .versionReportCopyVersion, object: nil)
                }
                .keyboardShortcut("c", modifiers: [.option, .command])
                .disabled(uiState.selectedAppIDs.count != 1)
            }

            CommandGroup(after: .toolbar) {
                Button("Mark as Read") {
                    uiState.onMarkAsReadRequested()
                }
                .disabled(!service.apps.contains { uiState.selectedAppIDs.contains($0.id) && $0.hasUnreadUpdate })

                Button("Mark as Unread") {
                    uiState.onMarkAsUnreadRequested()
                }
                .disabled(!service.apps.contains { uiState.selectedAppIDs.contains($0.id) && !$0.hasUnreadUpdate })

                Divider()
                Toggle("Show Previous Version Column", isOn: $showPreviousVersionColumn)
                Toggle("Show Current Build Column", isOn: $showBuildNumberColumn)
                Toggle("Show Source Column", isOn: $showSourceColumn)
            }
        }

        Settings {
            SettingsView()
        }
    }
}
