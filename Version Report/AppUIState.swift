import Foundation
import Combine

final class AppUIState: ObservableObject {
    @Published var showingAddAppSheet = false
    @Published var selectedAppIDs = Set<MonitoredApp.ID>()
    @Published var editingOriginalAppID: String?
    @Published var showingDeleteConfirmation = false
    @Published var showingLibrarySheet = false
    @Published var showingLibraryConflictsSheet = false

    var onEditRequested: () -> Void = {}
    var onDeleteRequested: () -> Void = {}
    var onAddToLibraryRequested: () -> Void = {}
    var onMarkAsReadRequested: () -> Void = {}
    var onMarkAsUnreadRequested: () -> Void = {}
    var onNewGroupRequested: () -> Void = {}
    var onNewGroupFromSelectionRequested: () -> Void = {}
    var onNewSmartGroupRequested: () -> Void = {}
}
