import SwiftUI
import Foundation

let versionReportBaseURL =
    FileManager.default
        .urls(for: .applicationSupportDirectory, in: .userDomainMask)
        .first!
        .appendingPathComponent("Version Report")

extension Notification.Name {
    static let versionReportRefresh = Notification.Name("versionReportRefresh")
    static let versionReportCheckNow = Notification.Name("versionReportCheckNow")
    static let versionReportCopyVersion = Notification.Name("versionReportCopyVersion")
    static let versionReportRefreshDockBadge = Notification.Name("versionReportRefreshDockBadge")
}

struct MonitoredApp: Identifiable {
    let id: String
    let name: String
    let version: String
    let previousVersion: String
    let sourceType: String
    let lastChecked: String
    let lastUpdated: String
    let iconName: String
    let hasUnreadUpdate: Bool

    var unreadSortValue: Int {
        hasUnreadUpdate ? 1 : 0
    }
}

struct SearchField: NSViewRepresentable {
    @Binding var text: String

    func makeNSView(context: Context) -> NSSearchField {
        let searchField = NSSearchField()
        searchField.placeholderString = "Search"
        searchField.delegate = context.coordinator
        return searchField
    }

    func updateNSView(_ nsView: NSSearchField, context: Context) {
        if nsView.stringValue != text {
            nsView.stringValue = text
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text)
    }

    final class Coordinator: NSObject, NSSearchFieldDelegate {
        @Binding var text: String

        init(text: Binding<String>) {
            _text = text
        }

        func controlTextDidChange(_ notification: Notification) {
            guard let searchField = notification.object as? NSSearchField else {
                return
            }

            text = searchField.stringValue
        }
    }
}

struct ContentView: View {

    @ObservedObject var service: VersionReportService
    @ObservedObject var uiState: AppUIState
    @State private var sortOrder = [KeyPathComparator(\MonitoredApp.name)]
    @AppStorage("showParserColumn") private var showParserColumn = false
    @AppStorage("showPreviousVersionColumn") private var showPreviousVersionColumn = false

    @State private var newAppName = ""
    @State private var newVersionURL = ""
    @State private var newParserType = "jq"
    @State private var newParserValue = ""
    @State private var parserTestResult = ""
    @State private var isTestingParser = false

    @State private var searchText = ""
    @State private var librarySearchText = ""
    @State private var selectedLibraryAppIDs = Set<String>()

    private var filteredApps: [MonitoredApp] {
        let sortedApps = service.apps.sorted(using: sortOrder)

        guard !searchText.isEmpty else {
            return sortedApps
        }

        return sortedApps.filter {
            $0.name.localizedCaseInsensitiveContains(searchText)
        }
    }

    private var availableLibraryApps: [AppConfig] {
        let monitoredAppNames = Set(service.loadAppConfigs().map { $0.name })
        let libraryApps = service.loadAppLibrary().filter { !monitoredAppNames.contains($0.name) }

        guard !librarySearchText.isEmpty else {
            return libraryApps
        }

        return libraryApps.filter {
            $0.name.localizedCaseInsensitiveContains(librarySearchText)
        }
    }

    private func editSelectedApp() {
        guard let selectedAppID = uiState.selectedAppIDs.first,
              let selectedApp = service.apps.first(where: { $0.id == selectedAppID }),
              let config = service.loadAppConfigs().first(where: { $0.name == selectedApp.name }) else {
            return
        }

        uiState.editingOriginalAppID = config.id
        newAppName = config.name
        newVersionURL = config.versionURL.absoluteString
        newParserType = config.parserType
        newParserValue = config.parserValue
        parserTestResult = ""
        isTestingParser = false
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
        let app = MonitoredApp(
            id: config.id,
            name: config.name,
            version: "",
            previousVersion: "",
            sourceType: config.parserType,
            lastChecked: "",
            lastUpdated: "",
            iconName: config.id,
            hasUnreadUpdate: false
        )

        return service.icon(for: app)
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

                            Text(app.parserType)
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

    var body: some View {

        VStack(alignment: .leading, spacing: 12) {

            Table(filteredApps, selection: $uiState.selectedAppIDs, sortOrder: $sortOrder) {

                TableColumn("", value: \.unreadSortValue) { app in
                    if app.hasUnreadUpdate {
                        Circle()
                            .frame(width: 8, height: 8)
                            .foregroundStyle(.blue)
                    }
                }
                .width(8)

                TableColumn("") { app in
                    Image(nsImage: service.icon(for: app))
                        .resizable()
                        .scaledToFit()
                        .frame(width: 20, height: 20)
                }
                .width(32)

                TableColumn("App", value: \.name) { app in
                    Text(app.name)
                        .lineLimit(1)
                }
                .width(min: 180, ideal: 220)

                TableColumn("Current Version", value: \.version) { app in
                    Text(app.version)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                .width(min: 90, ideal: 110)

                if showPreviousVersionColumn {
                    TableColumn("Previous Version", value: \.previousVersion) { app in
                        Text(app.previousVersion)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    .width(min: 100, ideal: 120)
                }

                if showParserColumn {
                    TableColumn("Parser", value: \.sourceType) { app in
                        Text(app.sourceType)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    .width(min: 110, ideal: 130)
                }

                TableColumn("Last Checked", value: \.lastChecked) { app in
                    Text(app.lastChecked)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                .width(min: 160, ideal: 180)

                TableColumn("Last Updated", value: \.lastUpdated) { app in
                    Text(app.lastUpdated)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                .width(min: 160, ideal: 180)

            }
            .selectionDisabled(false)
            .contextMenu(forSelectionType: MonitoredApp.ID.self) { selectedAppIDs in
                Button("Copy Version") {
                    guard let selectedAppID = selectedAppIDs.first else {
                        return
                    }

                    uiState.selectedAppIDs = [selectedAppID]
                    copySelectedVersion()
                }
                .disabled(selectedAppIDs.count != 1)

                Button("Mark as Read") {
                    uiState.selectedAppIDs = selectedAppIDs
                    markSelectedUpdatesAsRead()
                }
                .disabled(!selectedAppIDs.contains { selectedAppID in
                    service.apps.first(where: { $0.id == selectedAppID })?.hasUnreadUpdate == true
                })

                Button("Mark as Unread") {
                    uiState.selectedAppIDs = selectedAppIDs
                    markSelectedUpdatesAsUnread()
                }
                .disabled(!selectedAppIDs.contains { selectedAppID in
                    service.apps.first(where: { $0.id == selectedAppID })?.hasUnreadUpdate == false
                })

                Divider()

                Button("Edit App…") {
                    guard let selectedAppID = selectedAppIDs.first else {
                        return
                    }

                    uiState.selectedAppIDs = [selectedAppID]
                    uiState.editRequested = true
                }
                .disabled(selectedAppIDs.isEmpty)

                Button("Delete App") {
                    guard let selectedAppID = selectedAppIDs.first else {
                        return
                    }

                    uiState.selectedAppIDs = [selectedAppID]
                    uiState.deleteRequested = true
                }
                .disabled(selectedAppIDs.isEmpty)
            }
            .frame(minHeight: 360)

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
                        Image(systemName: "plus")
                            .frame(width: 16, height: 16)
                    }
                    .menuIndicator(.hidden)

                    Button {
                        uiState.deleteRequested = true
                    } label: {
                        Image(systemName: "minus")
                            .frame(width: 16, height: 16)
                    }
                    .disabled(uiState.selectedAppIDs.isEmpty)
                }

                Spacer()
            }
            .padding(.leading, 4)

            Text(service.statusMessage)
                .font(.footnote)
                .foregroundStyle(.secondary)

        }
        .padding(.horizontal)
        .padding(.bottom)
        .sheet(isPresented: $uiState.showingAddAppSheet) {
            VStack(alignment: .leading, spacing: 12) {

                Text(uiState.editingOriginalAppID == nil ? "Add App" : "Edit App")
                    .font(.headline)

                TextField("App Name", text: $newAppName)

                TextField("Version URL", text: $newVersionURL)

                Picker("Parser Type", selection: $newParserType) {
                    ForEach(service.parserTypes(), id: \.self) { parser in
                        Text(parser).tag(parser)
                    }
                }

                TextField("Parser Value", text: $newParserValue)

                Button(isTestingParser ? "Testing…" : "Test Parser") {
                    guard let url = URL(string: newVersionURL) else {
                        parserTestResult = "Invalid version URL"
                        return
                    }

                    let config = AppConfig(
                        name: newAppName.isEmpty ? "Parser Test" : newAppName,
                        versionURL: url,
                        parserType: newParserType,
                        parserValue: newParserValue
                    )

                    isTestingParser = true
                    parserTestResult = ""

                    Task {
                        do {
                            if let version = try await service.fetchCurrentVersion(for: config) {
                                await MainActor.run {
                                    parserTestResult = "Found version: \(version)"
                                    isTestingParser = false
                                }
                            } else {
                                await MainActor.run {
                                    parserTestResult = "No version found"
                                    isTestingParser = false
                                }
                            }
                        } catch {
                            await MainActor.run {
                                parserTestResult = "Parser test failed"
                                isTestingParser = false
                            }

                            print("Parser test failed for \(config.name): \(error)")
                        }
                    }
                }
                .disabled(newVersionURL.isEmpty || newParserValue.isEmpty || isTestingParser)

                if !parserTestResult.isEmpty {
                    Text(parserTestResult)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                HStack {

                    Button("Cancel") {
                        parserTestResult = ""
                        isTestingParser = false
                        uiState.showingAddAppSheet = false
                    }

                    Spacer()

                    Button(uiState.editingOriginalAppID == nil ? "Save" : "Update") {
                        guard let url = URL(string: newVersionURL) else {
                            return
                        }

                        let config = AppConfig(
                            name: newAppName,
                            versionURL: url,
                            parserType: newParserType,
                            parserValue: newParserValue
                        )

                        if let editingOriginalAppID = uiState.editingOriginalAppID {
                            if let updatedConfig = service.updateAppConfig(config, replacingID: editingOriginalAppID) {
                                service.loadApps()

                                Task {
                                    do {
                                        if let version = try await service.fetchCurrentVersion(for: updatedConfig) {
                                            _ = service.updateAppState(version: version, for: updatedConfig)

                                            await MainActor.run {
                                                service.reloadApps()

                                                let formatter = DateFormatter()
                                                formatter.timeStyle = .short
                                                formatter.dateStyle = .none

                                                service.statusMessage = "Updated \(updatedConfig.name) at \(formatter.string(from: Date()))"
                                            }
                                        } else {
                                            await MainActor.run {
                                                service.statusMessage = "Updated \(updatedConfig.name), but no version was found"
                                            }
                                        }
                                    } catch {
                                        await MainActor.run {
                                            service.statusMessage = "Updated \(updatedConfig.name), but version lookup failed"
                                        }

                                        print("Updated check failed for \(updatedConfig.name): \(error)")
                                    }
                                }
                            }
                        } else {
                            service.addAppConfig(config)
                        }

                        newAppName = ""
                        newVersionURL = ""
                        newParserType = "jq"
                        newParserValue = ""
                        parserTestResult = ""
                        isTestingParser = false
                        self.uiState.editingOriginalAppID = nil

                        uiState.showingAddAppSheet = false
                    }
                    .disabled(newAppName.isEmpty || newVersionURL.isEmpty || newParserValue.isEmpty)
                }
            }
            .padding()
            .frame(width: 500)
        }
        .sheet(isPresented: $uiState.showingLibrarySheet) {
            librarySheet
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
        .frame(minWidth: 780, minHeight: 560)
        .onAppear {
            service.requestNotificationPermission()
            service.loadApps()
            service.runVersionCheck()
            service.scheduleNextHourlyCheck()
        }
        .onReceive(NotificationCenter.default.publisher(for: .versionReportRefresh)) { _ in
            service.loadApps()
        }
        .onReceive(NotificationCenter.default.publisher(for: .versionReportCheckNow)) { _ in
            service.runVersionCheck()
        }
        .onReceive(NotificationCenter.default.publisher(for: .versionReportCopyVersion)) { _ in
            copySelectedVersion()
        }
        .onChange(of: uiState.showingAddAppSheet) { _, isShowing in
            guard isShowing, uiState.editingOriginalAppID == nil else {
                return
            }

            newAppName = ""
            newVersionURL = ""
            newParserType = "jq"
            newParserValue = ""
            parserTestResult = ""
            isTestingParser = false
        }
        .onChange(of: uiState.showingLibrarySheet) { _, isShowing in
            guard isShowing else {
                return
            }

            librarySearchText = ""
            selectedLibraryAppIDs.removeAll()
        }
        .onChange(of: uiState.editRequested) { _, requested in
            guard requested else {
                return
            }

            editSelectedApp()
            uiState.editRequested = false
        }
        .onChange(of: uiState.markAsReadRequested) { _, requested in
            guard requested else {
                return
            }

            markSelectedUpdatesAsRead()
            uiState.markAsReadRequested = false
        }
        .onChange(of: uiState.markAsUnreadRequested) { _, requested in
            guard requested else {
                return
            }

            markSelectedUpdatesAsUnread()
            uiState.markAsUnreadRequested = false
        }
        .onChange(of: uiState.deleteRequested) { _, requested in
            guard requested else {
                return
            }

            guard !uiState.selectedAppIDs.isEmpty else {
                uiState.deleteRequested = false
                return
            }

            uiState.showingDeleteConfirmation = true
            uiState.deleteRequested = false
        }
        .onChange(of: uiState.addToLibraryRequested) { _, requested in
            guard requested else {
                return
            }

            addSelectedAppToLibrary()
            uiState.addToLibraryRequested = false
        }
        .onDisappear {
            service.stopHourlyCheck()
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                SearchField(text: $searchText)
                    .frame(width: 220)
            }
        }

    }

}
