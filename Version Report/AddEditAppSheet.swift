import SwiftUI

struct AddEditAppSheet: View {

    let service: VersionReportService
    let uiState: AppUIState

    @State private var appName = ""
    @State private var sourceType = "homebrew"
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

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {

            Text(uiState.editingOriginalAppID == nil ? "Add App" : "Edit App")
                .font(.headline)

            TextField("App Name", text: $appName)

            Picker("Source", selection: $sourceType) {
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

    private var isSaveDisabled: Bool {
        if appName.isEmpty { return true }
        if sourceType == "homebrew" { return caskName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        if sourceType == "sparkle" { return sparkleURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        if sourceType == "github" { return VersionReportService.normalizeGitHubRepoPath(gitHubRepo).isEmpty }
        return versionURL.isEmpty || parserValue.isEmpty
    }

    private func populateFields() {
        guard let editingID = uiState.editingOriginalAppID,
              let config = service.loadAppConfigs().first(where: { $0.id == editingID }) else {
            appName = ""
            sourceType = "homebrew"
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
        } else {
            guard let url = URL(string: versionURL) else { return }
            source = .custom(versionURL: url, parserType: parserType, parserValue: parserValue)
        }

        let config = AppConfig(name: appName, source: source)

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
