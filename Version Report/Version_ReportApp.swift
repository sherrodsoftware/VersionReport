//
//  Version_ReportApp.swift
//  Version Report
//
//  Created by John Sherrod on 5/28/26.
//

import SwiftUI

@main
struct Version_ReportApp: App {
    @StateObject private var service = VersionReportService()
    @StateObject private var uiState = AppUIState()
    @AppStorage("showParserColumn") private var showParserColumn = false
    @AppStorage("showPreviousVersionColumn") private var showPreviousVersionColumn = false

    var body: some Scene {
        WindowGroup {
            ContentView(
                service: service,
                uiState: uiState
            )
        }
        .windowResizability(.contentSize)
        .commands {
            CommandGroup(after: .newItem) {
                Button("Add App…") {
                    uiState.editingOriginalAppID = nil
                    uiState.showingAddAppSheet = true
                }
                .keyboardShortcut("n", modifiers: [.command, .shift])

                Button("Add App From Library…") {
                    uiState.showingLibrarySheet = true
                }
                .keyboardShortcut("l", modifiers: [.command, .shift])

                Button("Edit Selected App…") {
                    uiState.editRequested = true
                }
                .keyboardShortcut("e", modifiers: [.command, .option])
                .disabled(uiState.selectedAppIDs.isEmpty)

                Button("Delete Selected App") {
                    uiState.deleteRequested = true
                }
                .keyboardShortcut(.delete, modifiers: [])
                .disabled(uiState.selectedAppIDs.isEmpty)

                Button("Add Selected App To Library") {
                    uiState.addToLibraryRequested = true
                }
                .disabled(uiState.selectedAppIDs.isEmpty)

                Divider()
                Button("Refresh") {
                    NotificationCenter.default.post(name: .versionReportRefresh, object: nil)
                }
                .keyboardShortcut("r", modifiers: [.command])

                Button("Check for Updates…") {
                    NotificationCenter.default.post(name: .versionReportCheckNow, object: nil)
                }
                .keyboardShortcut("r", modifiers: [.command, .shift])

                Divider()
            }

            CommandGroup(after: .pasteboard) {
                Button("Copy Version") {
                    NotificationCenter.default.post(name: .versionReportCopyVersion, object: nil)
                }
                .keyboardShortcut("c", modifiers: [.shift, .command])
                .disabled(uiState.selectedAppIDs.count != 1)
            }

            CommandGroup(after: .toolbar) {
                Toggle("Show Previous Version Column", isOn: $showPreviousVersionColumn)
                Toggle("Show Parser Column", isOn: $showParserColumn)
            }
        }

        Settings {
            SettingsView()
        }
    }
}
