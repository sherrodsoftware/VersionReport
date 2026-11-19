import Foundation
import Combine

final class AppUIState: ObservableObject {
    @Published var showingAddAppSheet = false
    @Published var selectedAppIDs = Set<MonitoredApp.ID>()
    @Published var editingOriginalAppID: String?
    @Published var showingDeleteConfirmation = false
    @Published var showingLibrarySheet = false
    @Published var showingLibraryConflictsSheet = false
    @Published var installedAppSuggestions: [InstalledAppSuggestion] = []
    @Published var showingInstalledAppsSheet = false
    /// True when opened from the File menu rather than the launch prompt.
    @Published var installedAppsSheetIsManual = false

    var onEditRequested: () -> Void = {}
    var onDeleteRequested: () -> Void = {}
    var onAddToLibraryRequested: () -> Void = {}
    var onMarkAsReadRequested: () -> Void = {}
    var onMarkAsUnreadRequested: () -> Void = {}
    var onNewGroupRequested: () -> Void = {}
    var onNewGroupFromSelectionRequested: () -> Void = {}
    var onNewSmartGroupRequested: () -> Void = {}
    var onFindInstalledAppsRequested: () -> Void = {}
}
