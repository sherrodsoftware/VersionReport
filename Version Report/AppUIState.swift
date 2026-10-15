import Foundation
import Combine

final class AppUIState: ObservableObject {
    @Published var showingAddAppSheet = false
    @Published var selectedAppIDs = Set<MonitoredApp.ID>()
    @Published var editingOriginalAppID: String?
    @Published var showingDeleteConfirmation = false

    @Published var editRequested = false
    @Published var deleteRequested = false
    @Published var addToLibraryRequested = false
    @Published var markAsReadRequested = false
    @Published var markAsUnreadRequested = false
    @Published var showingLibrarySheet = false
}
