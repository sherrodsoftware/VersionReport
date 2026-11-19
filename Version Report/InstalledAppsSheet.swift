import SwiftUI

/// Offers built-in library apps that are installed on this Mac but not tracked yet.
struct InstalledAppsSheet: View {

    let service: VersionReportService
    @ObservedObject var uiState: AppUIState

    @State private var selectedIDs: Set<String> = []
    @State private var dontShowAgain = false

    private var suggestions: [InstalledAppSuggestion] { uiState.installedAppSuggestions }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {

            VStack(alignment: .leading, spacing: 4) {
                Text("Add Your Installed Apps?")
                    .font(.headline)
                Text(suggestions.count == 1
                     ? "This app on your Mac is in Version Report's built-in library. Would you like to track it?"
                     : "These \(suggestions.count) apps on your Mac are in Version Report's built-in library. Choose the ones you'd like to track.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if suggestions.count > 1 {
                HStack {
                    Button("Select All") { selectedIDs = Set(suggestions.map(\.id)) }
                    Button("Select None") { selectedIDs = [] }
                }
                .buttonStyle(.link)
                .font(.callout)
            }

            List(suggestions) { suggestion in
                // The checkbox is its own control so it centers on the row; a
                // labeled checkbox aligns to its label's first line instead.
                HStack(alignment: .center, spacing: 10) {
                    Toggle("Track \(suggestion.config.name)", isOn: binding(for: suggestion.id))
                        .toggleStyle(.checkbox)
                        .labelsHidden()

                    Image(nsImage: service.icon(forID: suggestion.config.id))
                        .resizable()
                        .scaledToFit()
                        .frame(width: 24, height: 24)

                    VStack(alignment: .leading, spacing: 1) {
                        Text(suggestion.config.name)
                        if let vendor = suggestion.config.displayVendor {
                            Text(vendor)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }

                    Spacer()

                    Text(VersionReportService.marketingVersion(suggestion.installed.version))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .help("Installed at \(suggestion.installed.url.path)")
                }
                .padding(.vertical, 2)
                .contentShape(Rectangle())
                .onTapGesture {
                    binding(for: suggestion.id).wrappedValue.toggle()
                }
                // VoiceOver reads the whole row as one checkbox, matching how it works with the mouse.
                .accessibilityRepresentation {
                    Toggle(accessibilityLabel(for: suggestion), isOn: binding(for: suggestion.id))
                        .toggleStyle(.checkbox)
                }
            }
            .frame(minHeight: 160, idealHeight: min(CGFloat(suggestions.count) * 40 + 20, 360), maxHeight: 360)
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color(nsColor: .separatorColor), lineWidth: 1))

            if !uiState.installedAppsSheetIsManual {
                Toggle("Don't show this again", isOn: $dontShowAgain)
                    .toggleStyle(.checkbox)
                    .help("You can turn this back on in Settings, or use File → Add Installed Apps… at any time.")
            }

            HStack {
                Button("Not Now") { finish(adding: []) }
                    .keyboardShortcut(.cancelAction)

                Spacer()

                Button(selectedIDs.count == 1 ? "Add 1 App" : "Add \(selectedIDs.count) Apps") {
                    finish(adding: suggestions.filter { selectedIDs.contains($0.id) }.map(\.config))
                }
                .keyboardShortcut(.defaultAction)
                .disabled(selectedIDs.isEmpty)
            }
        }
        .padding(20)
        .frame(width: 460)
        .onAppear {
            selectedIDs = Set(suggestions.map(\.id))
            dontShowAgain = false
        }
    }

    private func accessibilityLabel(for suggestion: InstalledAppSuggestion) -> String {
        let version = "version \(VersionReportService.marketingVersion(suggestion.installed.version))"
        return [suggestion.config.name, suggestion.config.displayVendor, version]
            .compactMap { $0 }
            .joined(separator: ", ")
    }

    private func binding(for id: String) -> Binding<Bool> {
        Binding(
            get: { selectedIDs.contains(id) },
            set: { isOn in
                if isOn { selectedIDs.insert(id) } else { selectedIDs.remove(id) }
            }
        )
    }

    private func finish(adding configs: [AppConfig]) {
        // Everything shown has now been offered, so the launch prompt won't repeat it.
        service.markInstalledAppsOffered(suggestions.map(\.id))
        if dontShowAgain {
            service.suggestsInstalledAppsAtLaunch = false
        }

        for config in configs {
            service.addAppConfig(config)
        }
        if !configs.isEmpty {
            service.statusMessage = configs.count == 1
                ? "Added \(configs[0].name)"
                : "Added \(configs.count) apps from your Applications folder"
        }

        uiState.showingInstalledAppsSheet = false
    }
}
