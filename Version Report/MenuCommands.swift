import SwiftUI

// Menu contents are small views that read the models themselves, so their enabled
// state follows the selection and the apps through observation, without depending
// on the app's scene body being re-evaluated.

/// File menu: groups, adding and editing apps, and checking versions.
struct FileMenuCommands: View {
    let uiState: AppUIState

    var body: some View {
        let hasSelection = !uiState.selectedAppIDs.isEmpty

        Button("New Group") {
            uiState.onNewGroupRequested()
        }
        .keyboardShortcut("n", modifiers: [.command])

        Button("New Group from Selection") {
            uiState.onNewGroupFromSelectionRequested()
        }
        .disabled(!hasSelection)

        Button("New Smart Group…") {
            uiState.onNewSmartGroupRequested()
        }
        .keyboardShortcut("n", modifiers: [.command, .shift])

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

        Button("Add Installed Apps…") {
            uiState.onFindInstalledAppsRequested()
        }

        Button("Edit Selected App…") {
            uiState.onEditRequested()
        }
        .keyboardShortcut("e", modifiers: [.command, .option])
        .disabled(!hasSelection)

        Button("Delete Selected App") {
            uiState.onDeleteRequested()
        }
        .keyboardShortcut(.delete, modifiers: [])
        .disabled(!hasSelection)

        Button("Add Selected App To Library") {
            uiState.onAddToLibraryRequested()
        }
        .disabled(!hasSelection)

        Divider()

        Button("Check Versions Now") {
            NotificationCenter.default.post(name: .versionReportCheckNow, object: nil)
        }
        .keyboardShortcut("r", modifiers: [.command])

        Divider()
    }
}

/// Edit menu: copying the selected app's version.
struct CopyVersionCommand: View {
    let uiState: AppUIState

    var body: some View {
        Button("Copy Version") {
            NotificationCenter.default.post(name: .versionReportCopyVersion, object: nil)
        }
        .keyboardShortcut("c", modifiers: [.option, .command])
        .disabled(uiState.selectedAppIDs.count != 1)
    }
}

/// View menu: read status and optional columns.
struct ViewMenuCommands: View {
    let service: VersionReportService
    let uiState: AppUIState

    @AppStorage("showSourceColumn") private var showSourceColumn = false
    @AppStorage("showVendorColumn") private var showVendorColumn = false
    @AppStorage("showInstalledVersionColumn") private var showInstalledVersionColumn = false
    @AppStorage("showBuildNumberColumn") private var showBuildNumberColumn = false
    @AppStorage("showPreviousVersionColumn") private var showPreviousVersionColumn = false

    var body: some View {
        let selectedIDs = uiState.selectedAppIDs
        let selectedApps = service.apps.filter { selectedIDs.contains($0.id) }

        Button("Mark as Read") {
            uiState.onMarkAsReadRequested()
        }
        .disabled(!selectedApps.contains { $0.hasUnreadUpdate })

        Button("Mark as Unread") {
            uiState.onMarkAsUnreadRequested()
        }
        .disabled(!selectedApps.contains { !$0.hasUnreadUpdate })

        Divider()
        Toggle("Show Installed Version Column", isOn: $showInstalledVersionColumn)
        Toggle("Show Previous Version Column", isOn: $showPreviousVersionColumn)
        Toggle("Show Current Build Column", isOn: $showBuildNumberColumn)
        Toggle("Show Vendor Column", isOn: $showVendorColumn)
        Toggle("Show Source Column", isOn: $showSourceColumn)
    }
}
