import SwiftUI

private struct AppStoreResult: Identifiable {
    let id: Int
    let name: String
    let developer: String
    let iconURL: URL?
    let storeURL: URL
    let version: String
}

struct AddEditAppSheet: View {

    let service: VersionReportService
    let uiState: AppUIState

    @State private var appName = ""
    @State private var vendor = ""
    @State private var originalVendor: String?

    private var resolvedVendor: String? {
        let trimmed = vendor.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty { return trimmed }
        return originalVendor == nil ? nil : ""
    }
    @State private var sourceType = "appstore"
    @State private var caskName = ""
    @State private var sparkleURL = ""
    @State private var gitHubRepo = ""
    @State private var versionURL = ""
    @State private var parserType = "jq"
    @State private var parserValue = ""
    @State private var lookupResult = ""
    @State private var isLookingUp = false
    @State private var parserTestResult = ""
    @State private var isTestingParser = false

    // App Store search state
    @State private var appStoreQuery = ""
    @State private var appStoreResults: [AppStoreResult] = []
    @State private var isSearchingAppStore = false
    @State private var selectedAppStoreResult: AppStoreResult?
    @State private var appStoreSearchMessage = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {

            Text(uiState.editingOriginalAppID == nil ? "Add App" : "Edit App")
                .font(.headline)

            TextField("App Name", text: $appName)

            TextField("Vendor (optional)", text: $vendor)

            Picker("Source", selection: $sourceType) {
                Text("App Store").tag("appstore")
                Text("Homebrew Cask").tag("homebrew")
                Text("Sparkle Feed").tag("sparkle")
                Text("GitHub Releases").tag("github")
                Text("Custom").tag("custom")
            }

            if sourceType == "homebrew" {

                HStack {
                    TextField("Cask Name", text: $caskName)

                    Button(isLookingUp ? "Looking Up…" : "Look Up") {
                        isLookingUp = true
                        lookupResult = ""

                        Task {
                            do {
                                if let info = try await service.lookupHomebrewCask(caskName) {
                                    await MainActor.run {
                                        if appName.isEmpty { appName = info.name }
                                        lookupResult = "Found version \(info.version)"
                                        isLookingUp = false
                                    }
                                } else {
                                    await MainActor.run {
                                        lookupResult = "Cask not found"
                                        isLookingUp = false
                                    }
                                }
                            } catch {
                                await MainActor.run {
                                    lookupResult = "Look up failed"
                                    isLookingUp = false
                                }
                            }
                        }
                    }
                    .disabled(caskName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isLookingUp)
                }

                if !lookupResult.isEmpty {
                    Text(lookupResult).font(.footnote).foregroundStyle(.secondary)
                }

            } else if sourceType == "sparkle" {

                Text("Paste the app's Sparkle appcast URL. You can usually find it in the app's GitHub repository or release notes page.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)

                HStack {
                    TextField("Appcast Feed URL", text: $sparkleURL)

                    Button(isLookingUp ? "Looking Up…" : "Look Up") {
                        guard let url = URL(string: sparkleURL) else {
                            lookupResult = "Invalid feed URL"
                            return
                        }

                        isLookingUp = true
                        lookupResult = ""

                        Task {
                            do {
                                if let info = try await service.lookupSparkleFeed(url) {
                                    await MainActor.run {
                                        lookupResult = "Found version \(info.version)"
                                        isLookingUp = false
                                    }
                                } else {
                                    await MainActor.run {
                                        lookupResult = "No version found in feed"
                                        isLookingUp = false
                                    }
                                }
                            } catch {
                                await MainActor.run {
                                    lookupResult = "Error: \(error.localizedDescription)"
                                    isLookingUp = false
                                }
                            }
                        }
                    }
                    .disabled(sparkleURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isLookingUp)
                }

                if !lookupResult.isEmpty {
                    Text(lookupResult).font(.footnote).foregroundStyle(.secondary)
                }

            } else if sourceType == "github" {

                Text("Paste a GitHub repository URL or enter owner/repo. Note: GitHub allows 60 unauthenticated API requests per hour.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)

                HStack {
                    TextField("github.com/owner/repo or owner/repo", text: $gitHubRepo)

                    Button(isLookingUp ? "Looking Up…" : "Look Up") {
                        isLookingUp = true
                        lookupResult = ""

                        Task {
                            do {
                                let path = VersionReportService.normalizeGitHubRepoPath(gitHubRepo)
                                if let info = try await service.lookupGitHubRelease(path) {
                                    await MainActor.run {
                                        if appName.isEmpty {
                                            appName = info.repoName
                                                .replacingOccurrences(of: "-", with: " ")
                                                .capitalized
                                        }
                                        gitHubRepo = path
                                        lookupResult = "Found version \(info.version) (\(info.tagName))"
                                        isLookingUp = false
                                    }
                                } else {
                                    await MainActor.run {
                                        lookupResult = "No release found"
                                        isLookingUp = false
                                    }
                                }
                            } catch {
                                await MainActor.run {
                                    lookupResult = "Error: \(error.localizedDescription)"
                                    isLookingUp = false
                                }
                            }
                        }
                    }
                    .disabled(VersionReportService.normalizeGitHubRepoPath(gitHubRepo).isEmpty || isLookingUp)
                }

                if !lookupResult.isEmpty {
                    Text(lookupResult).font(.footnote).foregroundStyle(.secondary)
                }

            } else if sourceType == "appstore" {

                appStoreSearchSection

            } else {

                TextField("Version URL", text: $versionURL)

                Picker("Parser Type", selection: $parserType) {
                    ForEach(service.customParserTypes(), id: \.self) { parser in
                        Text(parser).tag(parser)
                    }
                }

                TextField("Parser Value", text: $parserValue)

                Button(isTestingParser ? "Testing…" : "Test Parser") {
                    guard let url = URL(string: versionURL) else {
                        parserTestResult = "Invalid version URL"
                        return
                    }

                    let config = AppConfig(
                        name: appName.isEmpty ? "Parser Test" : appName,
                        source: .custom(versionURL: url, parserType: parserType, parserValue: parserValue)
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
                        }
                    }
                }
                .disabled(versionURL.isEmpty || parserValue.isEmpty || isTestingParser)

                if !parserTestResult.isEmpty {
                    Text(parserTestResult).font(.footnote).foregroundStyle(.secondary)
                }

            }

            HStack {
                Button("Cancel") {
                    uiState.showingAddAppSheet = false
                }

                Spacer()

                Button(uiState.editingOriginalAppID == nil ? "Save" : "Update") {
                    saveApp()
                }
                .disabled(isSaveDisabled)
            }
        }
        .padding()
        .frame(width: 500)
        .onAppear {
            populateFields()
        }
    }

    @ViewBuilder
    private var appStoreSearchSection: some View {
        HStack {
            TextField("Search App Store", text: $appStoreQuery)
                .onSubmit { performAppStoreSearch() }

            Button(isSearchingAppStore ? "Searching…" : "Search") {
                performAppStoreSearch()
            }
            .disabled(appStoreQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isSearchingAppStore)
        }

        if !appStoreSearchMessage.isEmpty {
            Text(appStoreSearchMessage).font(.footnote).foregroundStyle(.secondary)
        }

        if !appStoreResults.isEmpty {
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(appStoreResults) { result in
                        AppStoreResultRow(
                            result: result,
                            isSelected: selectedAppStoreResult?.id == result.id
                        )
                        .contentShape(Rectangle())
                        .onTapGesture {
                            selectedAppStoreResult = result
                            appName = result.name
                            if vendor.isEmpty { vendor = result.developer }
                        }
                        Divider().padding(.leading, 44)
                    }
                }
            }
            .frame(maxHeight: 220)
            .background(Color(nsColor: .controlBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(Color(nsColor: .separatorColor), lineWidth: 1)
            )
        }

        if let selected = selectedAppStoreResult {
            HStack(spacing: 6) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                Text("Selected: \(selected.name) \(selected.version)")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func performAppStoreSearch() {
        let query = appStoreQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return }

        isSearchingAppStore = true
        appStoreSearchMessage = ""
        appStoreResults = []

        Task {
            do {
                let results = try await searchAppStore(query: query)
                await MainActor.run {
                    appStoreResults = results
                    appStoreSearchMessage = results.isEmpty ? "No results found" : ""
                    isSearchingAppStore = false
                }
            } catch {
                await MainActor.run {
                    appStoreSearchMessage = "Search failed: \(error.localizedDescription)"
                    isSearchingAppStore = false
                }
            }
        }
    }

    private func searchAppStore(query: String) async throws -> [AppStoreResult] {
        var components = URLComponents(string: "https://itunes.apple.com/search")!
        components.queryItems = [
            URLQueryItem(name: "term", value: query),
            URLQueryItem(name: "entity", value: "macSoftware"),
            URLQueryItem(name: "limit", value: "20")
        ]
        guard let url = components.url else { return [] }

        let (data, _) = try await URLSession.shared.data(from: url)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let results = json?["results"] as? [[String: Any]] ?? []

        return results.compactMap { item -> AppStoreResult? in
            guard
                let trackId = item["trackId"] as? Int,
                let name = item["trackName"] as? String,
                let developer = item["artistName"] as? String,
                let storeURLString = item["trackViewUrl"] as? String,
                let storeURL = URL(string: storeURLString)
            else { return nil }

            let iconURL = (item["artworkUrl60"] as? String).flatMap(URL.init)
            let version = item["version"] as? String ?? ""

            return AppStoreResult(
                id: trackId,
                name: name,
                developer: developer,
                iconURL: iconURL,
                storeURL: storeURL,
                version: version
            )
        }
    }

    private var isSaveDisabled: Bool {
        if appName.isEmpty { return true }
        if sourceType == "homebrew" { return caskName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        if sourceType == "sparkle" { return sparkleURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        if sourceType == "github" { return VersionReportService.normalizeGitHubRepoPath(gitHubRepo).isEmpty }
        if sourceType == "appstore" { return selectedAppStoreResult == nil }
        return versionURL.isEmpty || parserValue.isEmpty
    }

    private func populateFields() {
        guard let editingID = uiState.editingOriginalAppID,
              let config = service.loadAppConfigs().first(where: { $0.id == editingID }) else {
            appName = ""
            vendor = ""
            originalVendor = nil
            sourceType = "appstore"
            caskName = ""
            sparkleURL = ""
            gitHubRepo = ""
            versionURL = ""
            parserType = "jq"
            parserValue = ""
            lookupResult = ""
            isLookingUp = false
            parserTestResult = ""
            isTestingParser = false
            return
        }

        appName = config.name
        vendor = config.vendor ?? ""
        originalVendor = config.vendor
        switch config.source {
        case .homebrew(let name):
            sourceType = "homebrew"
            caskName = name
            sparkleURL = ""
            gitHubRepo = ""
            versionURL = ""
            parserType = "jq"
            parserValue = ""
        case .sparkle(let url):
            sourceType = "sparkle"
            caskName = ""
            sparkleURL = url.absoluteString
            gitHubRepo = ""
            versionURL = ""
            parserType = "jq"
            parserValue = ""
        case .github(let path):
            sourceType = "github"
            caskName = ""
            sparkleURL = ""
            gitHubRepo = path
            versionURL = ""
            parserType = "jq"
            parserValue = ""
        case .appstore(let url, let pType, let pValue):
            sourceType = "appstore"
            caskName = ""
            sparkleURL = ""
            gitHubRepo = ""
            versionURL = url.absoluteString
            parserType = pType
            parserValue = pValue
            // Show the existing URL as a placeholder result so Save stays enabled
            selectedAppStoreResult = AppStoreResult(
                id: 0,
                name: config.name,
                developer: "",
                iconURL: nil,
                storeURL: url,
                version: ""
            )
        case .custom(let url, let pType, let pValue):
            sourceType = "custom"
            caskName = ""
            sparkleURL = ""
            gitHubRepo = ""
            versionURL = url.absoluteString
            parserType = pType
            parserValue = pValue
        }

        lookupResult = ""
        isLookingUp = false
        parserTestResult = ""
        isTestingParser = false
    }

    private func saveApp() {
        let source: AppSource
        if sourceType == "homebrew" {
            source = .homebrew(caskName: caskName.trimmingCharacters(in: .whitespacesAndNewlines))
        } else if sourceType == "sparkle" {
            guard let url = URL(string: sparkleURL) else { return }
            source = .sparkle(feedURL: url)
        } else if sourceType == "github" {
            let path = VersionReportService.normalizeGitHubRepoPath(gitHubRepo)
            guard !path.isEmpty else { return }
            source = .github(repoPath: path)
        } else if sourceType == "appstore" {
            guard let result = selectedAppStoreResult else { return }
            if result.id == 0 {
                // Editing without re-searching — preserve the existing source URL
                guard let existingURL = URL(string: versionURL) else { return }
                source = .appstore(pageURL: existingURL, parserType: parserType, parserValue: parserValue)
            } else {
                let lookupURL = URL(string: "https://itunes.apple.com/lookup?id=\(result.id)&entity=macSoftware")
                    ?? result.storeURL
                source = .appstore(pageURL: lookupURL, parserType: "jq", parserValue: ".results.0.version")
            }
        } else {
            guard let url = URL(string: versionURL) else { return }
            source = .custom(versionURL: url, parserType: parserType, parserValue: parserValue)
        }

        let config = AppConfig(
            name: appName,
            source: source,
            vendor: resolvedVendor
        )

        // Download and save App Store icon at add/edit time.
        // Use the stable original ID when editing so the icon lands under the right name.
        if sourceType == "appstore", let iconURL = selectedAppStoreResult?.iconURL {
            let iconID = uiState.editingOriginalAppID ?? config.id
            Task {
                if let (data, _) = try? await URLSession.shared.data(from: iconURL),
                   let image = NSImage(data: data) {
                    service.saveCustomIcon(image, forID: iconID)
                }
            }
        }

        if let editingOriginalAppID = uiState.editingOriginalAppID {
            if let updatedConfig = service.updateAppConfig(config, replacingID: editingOriginalAppID) {
                service.loadApps()

                Task {
                    do {
                        if let version = try await service.fetchCurrentVersion(for: updatedConfig) {
                            _ = service.updateAppState(version: version, for: updatedConfig)
                            let name = updatedConfig.name
                            let time = VersionReportService.displayTimeFormatter.string(from: Date())
                            await MainActor.run {
                                service.reloadApps()
                                service.statusMessage = "Updated \(name) at \(time)"
                            }
                        } else {
                            let name = updatedConfig.name
                            await MainActor.run {
                                service.statusMessage = "Updated \(name), but no version was found"
                            }
                        }
                    } catch {
                        let name = updatedConfig.name
                        await MainActor.run {
                            service.statusMessage = "Updated \(name), but version lookup failed"
                        }
                    }
                }
            }
        } else {
            service.addAppConfig(config)
        }

        uiState.editingOriginalAppID = nil
        uiState.showingAddAppSheet = false
    }
}

private struct AppStoreResultRow: View {
    let result: AppStoreResult
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 8) {
            AsyncImage(url: result.iconURL) { image in
                image.resizable().interpolation(.high)
            } placeholder: {
                Color(nsColor: .quaternaryLabelColor)
            }
            .frame(width: 28, height: 28)
            .clipShape(RoundedRectangle(cornerRadius: 6))

            VStack(alignment: .leading, spacing: 1) {
                Text(result.name)
                    .font(.body)
                    .lineLimit(1)
                Text(result.developer)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            if !result.version.isEmpty {
                Text(result.version)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }

            if isSelected {
                Image(systemName: "checkmark")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color.accentColor)
                    .frame(width: 16)
            } else {
                Color.clear.frame(width: 16)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(isSelected ? Color.accentColor.opacity(0.1) : Color.clear)
    }
}
