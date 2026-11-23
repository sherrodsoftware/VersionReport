import SwiftUI
import Foundation

let versionReportBaseURL: URL = RunEnvironment.dataDirectory

extension Notification.Name {
    static let versionReportCheckNow = Notification.Name("versionReportCheckNow")
    static let versionReportCopyVersion = Notification.Name("versionReportCopyVersion")
    static let versionReportRefreshDockBadge = Notification.Name("versionReportRefreshDockBadge")
}

struct MonitoredApp: Identifiable, Equatable {
    let id: String
    let name: String
    let vendor: String?
    let version: String
    let previousVersion: String
    let sourceType: String
    let lastChecked: Date?
    let lastUpdated: Date?
    let iconName: String
    let hasUnreadUpdate: Bool
    let lastCheckError: String?
    let latestReleaseURL: URL?
    let updateCycle: UpdateCycle?
    var installed: InstalledAppInfo? = nil
    var tracksInstall: Bool = false

    var installStatus: InstallStatus {
        InstalledApps.status(installed: installed, available: version, tracksInstall: tracksInstall)
    }

    var installedVersionSortValue: String {
        installed?.version ?? ""
    }

    var isOverdue: Bool {
        updateCycle?.isOverdue ?? false
    }

    var vendorSortValue: String {
        vendor ?? ""
    }

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
        VersionReportService.marketingVersion(version)
    }

    var displayPreviousVersion: String {
        VersionReportService.marketingVersion(previousVersion)
    }

    var buildNumber: String? {
        guard let commaIndex = version.firstIndex(of: ",") else { return nil }
        let build = String(version[version.index(after: commaIndex)...])
        return build.isEmpty ? nil : build
    }
}


struct ContentView: View {

    let service: VersionReportService
    @Bindable var uiState: AppUIState
    @State private var sortOrder = [KeyPathComparator(\MonitoredApp.name)]
    @State private var columnCustomization = TableColumnCustomization<MonitoredApp>()
    // v2: earlier layouts saved the status and icon columns under per-launch IDs and can't be restored correctly.
    private static let columnCustomizationKey = "columnCustomization.v2"
    @AppStorage("showSourceColumn") private var showSourceColumn = false
    @AppStorage("showVendorColumn") private var showVendorColumn = false
    @AppStorage("showInstalledVersionColumn") private var showInstalledVersionColumn = false
    @AppStorage("showPreviousVersionColumn") private var showPreviousVersionColumn = false
    @AppStorage("showBuildNumberColumn") private var showBuildNumberColumn = false
    @AppStorage("showAppDetail") private var showAppDetail = false

    @State private var searchText = ""
    /// The table's rows: filtered for the sidebar selection, sorted, and searched.
    /// Stored rather than computed in body, so selecting a row (which redraws this
    /// view for the detail panel) doesn't re-filter and re-sort every app.
    @State private var displayedApps: [MonitoredApp] = []
    @State private var librarySearchText = ""
    @State private var selectedLibraryAppIDs = Set<String>()
    @State private var cachedLibraryApps: [AppConfig] = []
    @State private var sidebarSelection: SidebarSelection? = .allApps
    @State private var showingNewGroupAlert = false
    @State private var newGroupName = ""
    @State private var showingSmartGroupSheet = false
    @State private var editingSmartGroup: SmartGroup?
    @State private var showingRemoveFromGroupConfirmation = false


    private func refreshDisplayedApps() {
        let apps = makeDisplayedApps()
        if apps != displayedApps {
            displayedApps = apps
        }
    }

    private func makeDisplayedApps() -> [MonitoredApp] {
        var baseApps = service.apps

        switch sidebarSelection ?? .allApps {
        case .allApps:
            break
        case .group(let groupID):
            if let group = service.groups.first(where: { $0.id == groupID }) {
                baseApps = baseApps.filter { group.appIDs.contains($0.id) }
            }
        case .smartGroup(let sgID):
            if let sg = service.smartGroups.first(where: { $0.id == sgID }) {
                baseApps = baseApps.filter { sg.evaluate($0) }
            }
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

    private func presentInstalledApps(manual: Bool) {
        let suggestions = service.installedAppSuggestions()

        if suggestions.isEmpty {
            if manual { service.statusMessage = "All installed apps from the built-in library are already tracked." }
            return
        }

        // At launch, never stack on top of a sheet the user already opened.
        if !manual && (uiState.showingAddAppSheet || uiState.showingLibrarySheet || uiState.showingLibraryConflictsSheet) {
            return
        }

        uiState.installedAppSuggestions = suggestions
        uiState.installedAppsSheetIsManual = manual
        uiState.showingInstalledAppsSheet = true
    }

    private func loadCachedLibraryApps() {
        let monitoredAppNames = Set(service.loadAppConfigs().map { $0.name })
        cachedLibraryApps = service.loadAppLibraryForAdding().filter { !monitoredAppNames.contains($0.name) }
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

    private var currentGroupID: String? {
        if case .group(let id) = sidebarSelection { return id }
        return nil
    }

    private var isSmartGroupSelected: Bool {
        if case .smartGroup = sidebarSelection { return true }
        return false
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
        pasteboard.setString(selectedApp.displayVersion, forType: .string)
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

                    service.addAppConfigs(selectedConfigs)

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
        Table(of: MonitoredApp.self, selection: $uiState.selectedAppIDs, sortOrder: $sortOrder, columnCustomization: $columnCustomization) {
            TableColumn("", value: \.unreadSortValue) { app in
                if app.lastCheckError != nil {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 9))
                        .foregroundStyle(.orange)
                } else if app.hasUnreadUpdate {
                    Circle().frame(width: 8, height: 8).foregroundStyle(.blue)
                } else if app.isOverdue {
                    Image(systemName: "clock.badge.exclamationmark")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                        .help("Overdue for an update — Version Report may not be tracking this app correctly")
                }
            }
            .width(16)
            .customizationID("status")

            TableColumn("") { app in
                Image(nsImage: service.icon(for: app))
                    .resizable().scaledToFit().frame(width: 20, height: 20)
            }
            .width(32)
            .customizationID("icon")

            TableColumn("App", value: \.name) { app in
                Text(app.name).lineLimit(1)
            }
            .width(min: 180, ideal: 220)
            .customizationID("app")

            if showVendorColumn {
                TableColumn("Vendor", value: \.vendorSortValue) { app in
                    Text(app.vendor ?? "").foregroundStyle(.secondary).lineLimit(1)
                }
                .width(min: 100, ideal: 140)
                .customizationID("vendor")
            }

            TableColumn("Current Version", value: \.version) { app in
                Text(app.displayVersion).foregroundStyle(.secondary).lineLimit(1)
            }
            .width(min: 90, ideal: 110)
            .customizationID("currentVersion")

            if showInstalledVersionColumn {
                TableColumn("Installed Version", value: \.installedVersionSortValue) { app in
                    InstalledVersionCell(app: app)
                }
                .width(min: 100, ideal: 120)
                .customizationID("installedVersion")
            }

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

            // Grouped because a table accepts at most 10 columns per builder block.
            Group {
                TableColumn("Last Checked", value: \MonitoredApp.lastCheckedSortValue) { app in
                    Text(formatDate(app.lastChecked)).foregroundStyle(.secondary).lineLimit(1)
                }
                .width(min: 160, ideal: 180)
                .customizationID("lastChecked")

                TableColumn("Last Updated", value: \MonitoredApp.lastUpdatedSortValue) { app in
                    Text(formatDate(app.lastUpdated)).foregroundStyle(.secondary).lineLimit(1)
                }
                .width(min: 160, ideal: 180)
                .customizationID("lastUpdated")
            }
        } rows: {
            // The table's own row dragging: a drag starts anywhere on a row, takes the
            // whole selection when the row is selected, and shows the rows with a count.
            ForEach(displayedApps) { app in
                TableRow(app)
                    .draggable(app.id)
            }
        }
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
        } primaryAction: { ids in
            // Double-clicking a row (or pressing Return) opens its details. The table's own
            // primary action replaces a double-tap gesture on the name, which held back the
            // next click anywhere in the window while it waited for a possible second tap.
            guard let id = ids.first else { return }
            uiState.selectedAppIDs = [id]
            showAppDetail = true
        }
        .frame(minHeight: 360)
    }

    @ViewBuilder private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "square.stack")
                .font(.system(size: 48))
                .foregroundStyle(.tertiary)

            Text("No Apps Yet")
                .font(.title2)
                .fontWeight(.semibold)

            Text("Add the apps you manage to start tracking their versions.")
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 280)

            HStack(spacing: 10) {
                Button("Add App…") {
                    uiState.editingOriginalAppID = nil
                    uiState.showingAddAppSheet = true
                }
                .buttonStyle(.borderedProminent)

                Button("Add From Library…") {
                    uiState.showingLibrarySheet = true
                }
                .buttonStyle(.bordered)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder private var contentColumn: some View {
        VStack(alignment: .leading, spacing: 0) {
            if service.apps.isEmpty {
                emptyState
            } else {
                appsTable
            }

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
                    .disabled(isSmartGroupSelected)

                    Button {
                        guard !uiState.selectedAppIDs.isEmpty else { return }
                        if currentGroupID != nil {
                            showingRemoveFromGroupConfirmation = true
                        } else {
                            uiState.showingDeleteConfirmation = true
                        }
                    } label: {
                        Image(systemName: "minus").frame(width: 16, height: 16)
                    }
                    .disabled(uiState.selectedAppIDs.isEmpty || isSmartGroupSelected)
                    .keyboardShortcut(.delete, modifiers: .command)
                }

                Spacer()

                Text(service.statusMessage)
                    .font(.footnote)
                    .foregroundStyle(service.checkHadErrors ? .orange : .secondary)
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
                    SidebarView(service: service, selection: $sidebarSelection, showingSmartGroupSheet: $showingSmartGroupSheet, editingSmartGroup: $editingSmartGroup)
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
                    .navigationSplitViewColumnWidth(min: 300, ideal: 320, max: 400)
                }

            } else {
                NavigationSplitView {
                    SidebarView(service: service, selection: $sidebarSelection, showingSmartGroupSheet: $showingSmartGroupSheet, editingSmartGroup: $editingSmartGroup)
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
        .sheet(isPresented: $uiState.showingInstalledAppsSheet) {
            InstalledAppsSheet(service: service, uiState: uiState)
        }
        .sheet(isPresented: $showingSmartGroupSheet) {
            SmartGroupSheet(
                service: service,
                editingSmartGroup: editingSmartGroup,
                onDismiss: {
                    showingSmartGroupSheet = false
                    editingSmartGroup = nil
                },
                onSave: { sg in
                    if editingSmartGroup != nil {
                        service.updateSmartGroup(sg)
                    } else {
                        service.createSmartGroup(sg)
                        sidebarSelection = .smartGroup(sg.id)
                    }
                    showingSmartGroupSheet = false
                    editingSmartGroup = nil
                }
            )
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
        .alert("Remove from Group?", isPresented: $showingRemoveFromGroupConfirmation) {
            Button("Cancel", role: .cancel) { }
            Button("Remove", role: .destructive) {
                guard let groupID = currentGroupID else { return }
                for appID in uiState.selectedAppIDs {
                    service.removeApp(appID, fromGroup: groupID)
                }
                uiState.selectedAppIDs.removeAll()
            }
        } message: {
            let selectedApps = service.apps.filter { uiState.selectedAppIDs.contains($0.id) }
            let groupName = currentGroupID.flatMap { id in service.groups.first { $0.id == id }?.name } ?? "this group"
            if selectedApps.count == 1, let app = selectedApps.first {
                Text("Remove \(app.name) from \(groupName)?")
            } else {
                Text("Remove \(selectedApps.count) apps from \(groupName)?")
            }
        }
        .searchable(text: $searchText, placement: .toolbar)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    service.runVersionCheck()
                } label: {
                    Label("Check Versions Now", systemImage: "arrow.clockwise")
                }
                .disabled(service.isChecking)
                .help("Check monitored apps for new versions")
            }
            ToolbarItem(placement: .automatic) {
                Menu {
                    Toggle("Installed Version", isOn: $showInstalledVersionColumn)
                    Toggle("Current Build", isOn: $showBuildNumberColumn)
                    Toggle("Previous Version", isOn: $showPreviousVersionColumn)
                    Toggle("Vendor", isOn: $showVendorColumn)
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
        .frame(minWidth: 1100, minHeight: 620)
        .onAppear {
            service.requestNotificationPermission()
            service.loadApps()
            applySortOrder(for: service.apps)
            refreshDisplayedApps()
            service.runLaunchCheck()
            service.scheduleAutoCheck()
            uiState.onFindInstalledAppsRequested = { presentInstalledApps(manual: true) }
            if service.suggestsInstalledAppsAtLaunch && RunEnvironment.allowsExternalEffects {
                // Let the window finish appearing before presenting a sheet over it.
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { presentInstalledApps(manual: false) }
            }
            if let data = RunEnvironment.defaults.data(forKey: Self.columnCustomizationKey),
               let saved = try? JSONDecoder().decode(TableColumnCustomization<MonitoredApp>.self, from: data) {
                columnCustomization = saved
            }
            uiState.onEditRequested = { editSelectedApp() }
            uiState.onDeleteRequested = {
                guard !uiState.selectedAppIDs.isEmpty else { return }
                if currentGroupID != nil {
                    showingRemoveFromGroupConfirmation = true
                } else {
                    uiState.showingDeleteConfirmation = true
                }
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
            uiState.onNewSmartGroupRequested = {
                editingSmartGroup = nil
                showingSmartGroupSheet = true
            }
        }
        .onChange(of: service.apps) { _, apps in
            applySortOrder(for: apps)
            refreshDisplayedApps()
        }
        .onChange(of: service.groups) { refreshDisplayedApps() }
        .onChange(of: service.smartGroups) { refreshDisplayedApps() }
        .onChange(of: sidebarSelection) { refreshDisplayedApps() }
        .onChange(of: sortOrder) { refreshDisplayedApps() }
        .onChange(of: searchText) { refreshDisplayedApps() }
        .onChange(of: columnCustomization) { _, newValue in
            if let data = try? JSONEncoder().encode(newValue) {
                RunEnvironment.defaults.set(data, forKey: Self.columnCustomizationKey)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            // Pick up apps the user installed or updated while Version Report was in the background.
            service.refreshInstalledApps()
            // Smart group rules such as "checked within 7 days" depend on the time.
            refreshDisplayedApps()
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
    }


}

/// Installed version, highlighted when an update is waiting to be installed.
struct InstalledVersionCell: View {
    let app: MonitoredApp

    var body: some View {
        switch app.installStatus {
        case .outdated:
            HStack(spacing: 4) {
                Image(systemName: "arrow.up.circle.fill")
                    .foregroundStyle(.orange)
                Text(app.installed.map { VersionReportService.marketingVersion($0.version) } ?? "")
                    .lineLimit(1)
            }
            .help("Version \(app.displayVersion) is available")
        case .notInstalled:
            Text("Not installed").foregroundStyle(.tertiary).lineLimit(1)
        case .notTracked:
            Text("—").foregroundStyle(.tertiary)
        case .upToDate, .unknown:
            Text(app.installed.map { VersionReportService.marketingVersion($0.version) } ?? "")
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
    }
}
