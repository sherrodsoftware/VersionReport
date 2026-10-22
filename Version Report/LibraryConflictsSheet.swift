import SwiftUI

struct LibraryConflictsSheet: View {

    let service: VersionReportService
    let uiState: AppUIState

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {

            Text("Natively Tracked Apps")
                .font(.headline)

            Text("Version Report now includes built-in tracking for the following apps that you added manually. You can keep your version or switch to the built-in one, which will stay up to date automatically.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Divider()

            ForEach(service.pendingLibraryConflicts) { conflict in
                ConflictRow(conflict: conflict, service: service)
                Divider()
            }

            HStack {
                Button("Use All Built-in") {
                    for conflict in service.pendingLibraryConflicts {
                        service.resolveLibraryConflict(conflict, useBuiltin: true)
                    }
                    uiState.showingLibraryConflictsSheet = false
                }

                Spacer()

                Button("Keep All Mine") {
                    for conflict in service.pendingLibraryConflicts {
                        service.resolveLibraryConflict(conflict, useBuiltin: false)
                    }
                    uiState.showingLibraryConflictsSheet = false
                }

                Button("Done") {
                    uiState.showingLibraryConflictsSheet = false
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding()
        .frame(width: 520)
        .fixedSize(horizontal: false, vertical: true)
    }
}

private struct ConflictRow: View {

    let conflict: LibraryConflict
    let service: VersionReportService

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(nsImage: service.icon(forID: conflict.bundledConfig.id))
                .resizable()
                .scaledToFit()
                .frame(width: 32, height: 32)

            VStack(alignment: .leading, spacing: 4) {
                Text(conflict.bundledConfig.name)
                    .fontWeight(.medium)

                HStack(spacing: 16) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Your version")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(conflict.userConfig.source.displayName)
                            .font(.caption)
                    }

                    Image(systemName: "arrow.right")
                        .foregroundStyle(.secondary)
                        .font(.caption)

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Built-in version")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(conflict.bundledConfig.source.displayName)
                            .font(.caption)
                    }
                }
            }

            Spacer()

            VStack(spacing: 6) {
                Button("Use Built-in") {
                    service.resolveLibraryConflict(conflict, useBuiltin: true)
                }
                .controlSize(.small)

                Button("Keep Mine") {
                    service.resolveLibraryConflict(conflict, useBuiltin: false)
                }
                .controlSize(.small)
            }
        }
        .padding(.vertical, 4)
    }
}
