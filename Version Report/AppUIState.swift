import Foundation
import Observation

/// Transient UI state. Observation tracks each property separately, so a view
/// redraws only when a property it read changes (selecting a row no longer
/// redraws views that never look at the selection).
@Observable
final class AppUIState {
    var showingAddAppSheet = false
    var selectedAppIDs = Set<MonitoredApp.ID>()
    var editingOriginalAppID: String?
    var showingDeleteConfirmation = false
    var showingLibrarySheet = false
    var showingLibraryConflictsSheet = false
    var installedAppSuggestions: [InstalledAppSuggestion] = []
    var showingInstalledAppsSheet = false
    /// True when opened from the File menu rather than the launch prompt.
    var installedAppsSheetIsManual = false

    // Actions wired up by ContentView. They aren't state anyone renders, so
    // assigning them must not invalidate the views that call them.
    @ObservationIgnored var onEditRequested: () -> Void = {}
    @ObservationIgnored var onDeleteRequested: () -> Void = {}
    @ObservationIgnored var onAddToLibraryRequested: () -> Void = {}
    @ObservationIgnored var onMarkAsReadRequested: () -> Void = {}
    @ObservationIgnored var onMarkAsUnreadRequested: () -> Void = {}
    @ObservationIgnored var onNewGroupRequested: () -> Void = {}
    @ObservationIgnored var onNewGroupFromSelectionRequested: () -> Void = {}
    @ObservationIgnored var onNewSmartGroupRequested: () -> Void = {}
    @ObservationIgnored var onFindInstalledAppsRequested: () -> Void = {}
}
