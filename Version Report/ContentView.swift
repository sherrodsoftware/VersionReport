import SwiftUI
import Foundation

let versionReportBaseURL: URL = {
    guard let url = FileManager.default
        .urls(for: .applicationSupportDirectory, in: .userDomainMask)
        .first
    else {
        fatalError("Application Support directory not found")
    }
    return url.appendingPathComponent("Version Report")
}()

extension Notification.Name {
    static let versionReportCheckNow = Notification.Name("versionReportCheckNow")
    static let versionReportCopyVersion = Notification.Name("versionReportCopyVersion")
    static let versionReportRefreshDockBadge = Notification.Name("versionReportRefreshDockBadge")
}

struct MonitoredApp: Identifiable, Equatable {
    let id: String
    let name: String
    let version: String
    let previousVersion: String
    let sourceType: String
    let lastChecked: Date?
    let lastUpdated: Date?
    let iconName: String
    let hasUnreadUpdate: Bool

    var unreadSortValue: Int {
        hasUnreadUpdate ? 1 : 0
    }

    var lastCheckedSortValue: TimeInterval {
        lastChecked?.timeIntervalSinceReferenceDate ?? 0
    }

    var lastUpdatedSortValue: TimeInterval {
        lastUpdated?.timeIntervalSinceReferenceDate ?? 0
    }

    var displayVersion: String {
        String(version.prefix(while: { $0 != "," }))
    }

    var displayPreviousVersion: String {
        String(previousVersion.prefix(while: { $0 != "," }))
    }

    var buildNumber: String? {
        guard let commaIndex = version.firstIndex(of: ",") else { return nil }
        let build = String(version[version.index(after: commaIndex)...])
        return build.isEmpty ? nil : build
    }
}


struct ContentView: View {

    @ObservedObject var service: VersionReportService
    @ObservedObject var uiState: AppUIState
    @State private var sortOrder = [KeyPathComparator(\MonitoredApp.name)]
    @State private var columnCustomization = TableColumnCustomization<MonitoredApp>()
    @AppStorage("showSourceColumn") private var showSourceColumn = false
    @AppStorage("showPreviousVersionColumn") private var showPreviousVersionColumn = false
    @AppStorage("showBuildNumberColumn") private var showBuildNumberColumn = false
    @AppStorage("showAppDetail") private var showAppDetail = false

    @State private var searchText = ""
    @State private var librarySearchText = ""
    @State private var selectedLibraryAppIDs = Set<String>()
    @State private var cachedLibraryApps: [AppConfig] = []
    @State private var sidebarSelection: SidebarSelection? = .allApps
    @State private var showingNewGroupAlert = false
    @State private var newGroupName = ""

    private var filteredApps: [MonitoredApp] {
        var baseApps = service.apps

        if case .group(let groupID) = sidebarSelection ?? .allApps,
           let group = service.groups.first(where: { $0.id == groupID }) {
            baseApps = baseApps.filter { group.appIDs.contains($0.id) }
        }

        let sortedApps = baseApps.sorted(using: sortOrder)

        guard !searchText.isEmpty else {
            return sortedApps
        }

        return sortedApps.filter {
            $0.name.localizedCaseInsensitiveContains(searchText)
        }
    }

    private var selectedApp: MonitoredApp? {
        guard uiState.selectedAppIDs.count == 1,
              let id = uiState.selectedAppIDs.first else { return nil }
        return service.apps.first { $0.id == id }
    }

    private var availableLibraryApps: [AppConfig] {
        guard !librarySearchText.isEmpty else {
            return cachedLibraryApps
        }

        return cachedLibraryApps.filter {
            $0.name.localizedCaseInsensitiveContains(librarySearchText)
        }
    }

    private func applySortOrder(for apps: [MonitoredApp]) {
        if apps.contains(where: { $0.hasUnreadUpdate }) {
            sortOrder = [KeyPathComparator(\MonitoredApp.unreadSortValue, order: .reverse), KeyPathComparator(\MonitoredApp.name)]
        } else {
            sortOrder = [KeyPathComparator(\MonitoredApp.name)]
        }
    }

    private func loadCachedLibraryApps() {
        let monitoredAppNames = Set(service.loadAppConfigs().map { $0.name })
        cachedLibraryApps = service.loadAppLibrary().filter { !monitoredAppNames.contains($0.name) }
    }

    private func formatDate(_ date: Date?) -> String {
        date?.formatted(date: .abbreviated, time: .shortened) ?? "Never"
    }

    private func selectedAppsContainUnread(_ ids: Set<MonitoredApp.ID>) -> Bool {
        ids.contains { id in service.apps.first(where: { $0.id == id })?.hasUnreadUpdate == true }
    }

    private func selectedAppsContainRead(_ ids: Set<MonitoredApp.ID>) -> Bool {
        ids.contains { id in service.apps.first(where: { $0.id == id })?.hasUnreadUpdate == false }
    }

    private func editSelectedApp() {
        guard let selectedAppID = uiState.selectedAppIDs.first,
              let selectedApp = service.apps.first(where: { $0.id == selectedAppID }),
              let config = service.loadAppConfigs().first(where: { $0.name == selectedApp.name }) else {
            return
        }

        uiState.editingOriginalAppID = config.id
        uiState.showingAddAppSheet = true
    }

    private func addSelectedAppToLibrary() {
        guard let selectedAppID = uiState.selectedAppIDs.first,
              let selectedApp = service.apps.first(where: { $0.id == selectedAppID }),
              let config = service.loadAppConfigs().first(where: { $0.name == selectedApp.name }) else {
            return
        }

        service.addAppConfigToLibrary(config)
    }

    private func copySelectedVersion() {
        guard let selectedAppID = uiState.selectedAppIDs.first,
              let selectedApp = service.apps.first(where: { $0.id == selectedAppID }) else {
            return
        }

        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(selectedApp.version, forType: .string)
    }

    private func markSelectedUpdatesAsRead() {
        service.markUpdatesAsRead(for: uiState.selectedAppIDs)
    }

    private func markSelectedUpdatesAsUnread() {
        service.markUpdatesAsUnread(for: uiState.selectedAppIDs)
    }

    private func libraryIcon(for config: AppConfig) -> NSImage {
        service.icon(forID: config.id)
    }

    private var librarySheet: some View {
        VStack(alignment: .leading, spacing: 12) {

            Text("Add App From Library")
                .font(.headline)

            TextField("Search library...", text: $librarySearchText)
                .textFieldStyle(.roundedBorder)

            if availableLibraryApps.isEmpty {
                Text("No library apps available to add.")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 220, alignment: .center)
            } else {
                List(availableLibraryApps, selection: $selectedLibraryAppIDs) { app in
                    HStack(spacing: 10) {
                        Image(nsImage: libraryIcon(for: app))
                            .resizable()
                            .scaledToFit()
                            .frame(width: 24, height: 24)

                        VStack(alignment: .leading, spacing: 4) {
                            Text(app.name)
                                .font(.body)

                            Text(app.source.displayName)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 2)
                }
                .frame(minHeight: 260)
            }

            HStack {
                Button("Cancel") {
                    librarySearchText = ""
                    selectedLibraryAppIDs.removeAll()
                    uiState.showingLibrarySheet = false
                }

                Spacer()

                Button(selectedLibraryAppIDs.count == 1 ? "Add" : "Add \(selectedLibraryAppIDs.count) Apps") {
                    let selectedConfigs = availableLibraryApps.filter {
                        selectedLibraryAppIDs.contains($0.id)
                    }

                    for config in selectedConfigs {
                        service.addAppConfig(config)
                    }

                    librarySearchText = ""
                    selectedLibraryAppIDs.removeAll()
                    uiState.showingLibrarySheet = false
                }
                .disabled(selectedLibraryAppIDs.isEmpty)
            }
        }
        .padding()
        .frame(width: 500, height: 420)
    }

    @ViewBuilder private var appsTable: some View {
        Table(filteredApps, selection: $uiState.selectedAppIDs, sortOrder: $sortOrder, columnCustomization: $columnCustomization) {
            TableColumn("", value: \.unreadSortValue) { app in
                if app.hasUnreadUpdate {
                    Circle().frame(width: 8, height: 8).foregroundStyle(.blue)
                }
            }
            .width(8)

            TableColumn("") { app in
                Image(nsImage: service.icon(for: app))
                    .resizable().scaledToFit().frame(width: 20, height: 20)
            }
            .width(32)

            TableColumn("App", value: \.name) { app in
                Text(app.name).lineLimit(1)
                    .onTapGesture(count: 2) {
                        uiState.selectedAppIDs = [app.id]
                        showAppDetail = true
                    }
            }
            .width(min: 180, ideal: 220)
            .customizationID("app")

            TableColumn("Current Version", value: \.version) { app in
                Text(app.displayVersion).foregroundStyle(.secondary).lineLimit(1)
            }
            .width(min: 90, ideal: 110)
            .customizationID("currentVersion")

            if showBuildNumberColumn {
                TableColumn("Current Build", value: \.version) { app in
                    Text(app.buildNumber ?? "—").foregroundStyle(.secondary).lineLimit(1)
                }
                .width(min: 80, ideal: 100)
                .customizationID("currentBuild")
            }

            if showPreviousVersionColumn {
                TableColumn("Previous Version", value: \.previousVersion) { app in
                    Text(app.displayPreviousVersion).foregroundStyle(.secondary).lineLimit(1)
                }
                .width(min: 100, ideal: 120)
                .customizationID("previousVersion")
            }

            if showSourceColumn {
                TableColumn("Source", value: \.sourceType) { app in
                    Text(app.sourceType).foregroundStyle(.secondary).lineLimit(1)
                }
                .width(min: 110, ideal: 130)
                .customizationID("source")
            }

            TableColumn("Last Checked", value: \.lastCheckedSortValue) { app in
                Text(formatDate(app.lastChecked)).foregroundStyle(.secondary).lineLimit(1)
            }
            .width(min: 160, ideal: 180)
            .customizationID("lastChecked")

            TableColumn("Last Updated", value: \.lastUpdatedSortValue) { app in
                Text(formatDate(app.lastUpdated)).foregroundStyle(.secondary).lineLimit(1)
            }
            .width(min: 160, ideal: 180)
            .customizationID("lastUpdated")
        }
        .background(
            TableDragSourceView(
                filteredApps: filteredApps,
                selectedAppIDs: uiState.selectedAppIDs,
                iconProvider: { service.icon(for: $0) }
            )
        )
        .selectionDisabled(false)
        .contextMenu(forSelectionType: MonitoredApp.ID.self) { ids in
            Button("Copy Version") {
                guard let id = ids.first else { return }
                uiState.selectedAppIDs = [id]
                copySelectedVersion()
            }
            .disabled(ids.count != 1)

            Button("Mark as Read") {
                uiState.selectedAppIDs = ids
                markSelectedUpdatesAsRead()
            }
            .disabled(!selectedAppsContainUnread(ids))

            Button("Mark as Unread") {
                uiState.selectedAppIDs = ids
                markSelectedUpdatesAsUnread()
            }
            .disabled(!selectedAppsContainRead(ids))

            Divider()

            Button("Edit App…") {
                guard let id = ids.first else { return }
                uiState.selectedAppIDs = [id]
                editSelectedApp()
            }
            .disabled(ids.isEmpty)

            Button("Delete App") {
                guard let id = ids.first else { return }
                uiState.selectedAppIDs = [id]
                uiState.showingDeleteConfirmation = true
            }
            .disabled(ids.isEmpty)

            if !service.groups.isEmpty {
                Divider()

                Menu("Add to Group") {
                    ForEach(service.groups) { group in
                        Button(group.name) {
                            for id in ids {
                                service.addApp(id, toGroup: group.id)
                            }
                        }
                    }
                }
                .disabled(ids.isEmpty)

                Menu("Remove from Group") {
                    let memberGroups = service.groups.filter { group in
                        ids.contains { group.appIDs.contains($0) }
                    }
                    ForEach(memberGroups) { group in
                        Button(group.name) {
                            for id in ids {
                                service.removeApp(id, fromGroup: group.id)
                            }
                        }
                    }
                }
                .disabled({
                    !service.groups.contains { group in ids.contains { group.appIDs.contains($0) } }
                }())
            }
        }
        .frame(minHeight: 360)
    }

    @ViewBuilder private var contentColumn: some View {
        VStack(alignment: .leading, spacing: 0) {
            appsTable

            HStack {
                ControlGroup {
                    Menu {
                        Button("Add App…") {
                            uiState.editingOriginalAppID = nil
                            uiState.showingAddAppSheet = true
                        }
                        Button("Add App From Library…") {
                            uiState.showingLibrarySheet = true
                        }
                    } label: {
                        Image(systemName: "plus").frame(width: 16, height: 16)
                    }
                    .menuIndicator(.hidden)

                    Button {
                        guard !uiState.selectedAppIDs.isEmpty else { return }
                        uiState.showingDeleteConfirmation = true
                    } label: {
                        Image(systemName: "minus").frame(width: 16, height: 16)
                    }
                    .disabled(uiState.selectedAppIDs.isEmpty)
                }

                Spacer()

                Text(service.statusMessage)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)

            if !service.pendingLibraryConflicts.isEmpty {
                HStack(spacing: 8) {
                    Image(systemName: "info.circle.fill").foregroundStyle(.blue)
                    Text(service.pendingLibraryConflicts.count == 1
                        ? "Version Report now natively tracks \(service.pendingLibraryConflicts[0].bundledConfig.name)."
                        : "\(service.pendingLibraryConflicts.count) apps you added are now natively tracked.")
                        .font(.footnote)
                    Spacer()
                    Button("Review") { uiState.showingLibraryConflictsSheet = true }
                        .font(.footnote)
                }
                .padding(8)
                .background(.blue.opacity(0.08))
            }
        }
    }

    var body: some View {

        Group {
            if showAppDetail {
                NavigationSplitView {
                    SidebarView(service: service, selection: $sidebarSelection)
                        .navigationSplitViewColumnWidth(min: 170, ideal: 210, max: 300)
                } content: {
                    contentColumn
                        .navigationSplitViewColumnWidth(min: 380, ideal: 560)
                } detail: {
                    Group {
                        if let app = selectedApp {
                            AppDetailView(app: app, service: service) {
                                editSelectedApp()
                            }
                        } else {
                            AppDetailPlaceholderView()
                        }
                    }
                    .navigationSplitViewColumnWidth(min: 220, ideal: 260, max: 340)
                }
            } else {
                NavigationSplitView {
                    SidebarView(service: service, selection: $sidebarSelection)
                        .navigationSplitViewColumnWidth(min: 170, ideal: 210, max: 300)
                } detail: {
                    contentColumn
                }
            }
        }
        .sheet(isPresented: $uiState.showingAddAppSheet) {
            AddEditAppSheet(service: service, uiState: uiState)
        }
        .sheet(isPresented: $uiState.showingLibrarySheet) {
            librarySheet
        }
        .sheet(isPresented: $uiState.showingLibraryConflictsSheet) {
            LibraryConflictsSheet(service: service, uiState: uiState)
        }
        .alert("Delete App?", isPresented: $uiState.showingDeleteConfirmation) {
            Button("Cancel", role: .cancel) { }

            Button("Delete", role: .destructive) {
                let selectedApps = service.apps.filter {
                    uiState.selectedAppIDs.contains($0.id)
                }

                for selectedApp in selectedApps {
                    service.deleteAppConfig(id: selectedApp.id)
                }

                self.uiState.selectedAppIDs.removeAll()
            }
        } message: {
            let selectedApps = service.apps.filter {
                uiState.selectedAppIDs.contains($0.id)
            }

            if selectedApps.count == 1, let selectedApp = selectedApps.first {
                Text("Remove \(selectedApp.name) from Version Report?")
            } else {
                Text("Remove \(selectedApps.count) apps from Version Report?")
            }
        }
        .frame(minWidth: 960, minHeight: 560)
        .onAppear {
            service.requestNotificationPermission()
            service.loadApps()
            applySortOrder(for: service.apps)
            service.scheduleNextHourlyCheck()
            if let data = UserDefaults.standard.data(forKey: "columnCustomization"),
               let saved = try? JSONDecoder().decode(TableColumnCustomization<MonitoredApp>.self, from: data) {
                columnCustomization = saved
            }
            uiState.onEditRequested = { editSelectedApp() }
            uiState.onDeleteRequested = {
                guard !uiState.selectedAppIDs.isEmpty else { return }
                uiState.showingDeleteConfirmation = true
            }
            uiState.onAddToLibraryRequested = { addSelectedAppToLibrary() }
            uiState.onMarkAsReadRequested = { markSelectedUpdatesAsRead() }
            uiState.onMarkAsUnreadRequested = { markSelectedUpdatesAsUnread() }
            uiState.onNewGroupRequested = {
                newGroupName = ""
                showingNewGroupAlert = true
            }
            uiState.onNewGroupFromSelectionRequested = {
                newGroupName = ""
                showingNewGroupAlert = true
            }
        }
        .onChange(of: service.apps) { _, apps in
            applySortOrder(for: apps)
        }
        .onChange(of: columnCustomization) { _, newValue in
            if let data = try? JSONEncoder().encode(newValue) {
                UserDefaults.standard.set(data, forKey: "columnCustomization")
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .versionReportCheckNow)) { _ in
            service.runVersionCheck()
        }
        .onReceive(NotificationCenter.default.publisher(for: .versionReportCopyVersion)) { _ in
            copySelectedVersion()
        }
        .onChange(of: uiState.showingLibrarySheet) { _, isShowing in
            guard isShowing else {
                return
            }

            librarySearchText = ""
            selectedLibraryAppIDs.removeAll()
            loadCachedLibraryApps()
        }
        .onDisappear {
            service.stopHourlyCheck()
        }
        .alert("New Group", isPresented: $showingNewGroupAlert) {
            TextField("Group Name", text: $newGroupName)
            Button("Cancel", role: .cancel) { }
            Button("Create") {
                let trimmed = newGroupName.trimmingCharacters(in: .whitespaces)
                guard !trimmed.isEmpty else { return }
                service.createGroup(named: trimmed)
                let newGroup = service.groups.last
                // If triggered from selection, add selected apps to the new group
                if !uiState.selectedAppIDs.isEmpty, let group = newGroup {
                    for appID in uiState.selectedAppIDs {
                        service.addApp(appID, toGroup: group.id)
                    }
                }
                if let group = newGroup {
                    sidebarSelection = .some(.group(group.id))
                }
            }
        }
        .searchable(text: $searchText, placement: .toolbar)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    service.runVersionCheck()
                } label: {
                    Label("Check for Updates", systemImage: "arrow.clockwise")
                }
                .disabled(service.isChecking)
                .help("Check for Updates")
            }

            ToolbarItem(placement: .automatic) {
                Menu {
                    Toggle("Current Build", isOn: $showBuildNumberColumn)
                    Toggle("Previous Version", isOn: $showPreviousVersionColumn)
                    Toggle("Source", isOn: $showSourceColumn)
                } label: {
                    Label("Columns", systemImage: "checklist")
                }
                .help("Show or hide optional columns")
            }

            ToolbarItem(placement: .automatic) {
                Button {
                    showAppDetail.toggle()
                } label: {
                    Label("App Details", systemImage: "sidebar.right")
                }
                .help(showAppDetail ? "Hide App Details" : "Show App Details")
            }
        }

    }

}
