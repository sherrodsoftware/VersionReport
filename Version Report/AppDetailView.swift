import SwiftUI

struct AppDetailView: View {

    let app: MonitoredApp
    let service: VersionReportService
    let onEdit: () -> Void

    private func formatDate(_ date: Date?) -> String {
        date?.formatted(date: .abbreviated, time: .shortened) ?? "Never"
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {

                HStack(spacing: 16) {
                    Image(nsImage: service.icon(for: app))
                        .resizable()
                        .scaledToFit()
                        .frame(width: 64, height: 64)

                    VStack(alignment: .leading, spacing: 4) {
                        Text(app.name)
                            .font(.title2)
                            .fontWeight(.semibold)
                            .lineLimit(2)

                        if app.hasUnreadUpdate {
                            Label("New Update", systemImage: "circle.fill")
                                .font(.caption)
                                .foregroundStyle(.blue)
                        }
                    }

                    Spacer()

                    Button("Edit…", action: onEdit)
                        .buttonStyle(.borderless)
                }

                Divider()

                VStack(alignment: .leading, spacing: 8) {
                    detailRow("Current Version", value: app.displayVersion)

                    if let build = app.buildNumber {
                        detailRow("Build Number", value: build)
                    }

                    if !app.displayPreviousVersion.isEmpty {
                        detailRow("Previous Version", value: app.displayPreviousVersion)
                    }

                    detailRow("Source", value: app.sourceType)
                    detailRow("Last Checked", value: formatDate(app.lastChecked))
                    detailRow("Last Updated", value: formatDate(app.lastUpdated))
                }

                Spacer()
            }
            .padding(20)
        }
    }

    @ViewBuilder
    private func detailRow(_ label: String, value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(label)
                .foregroundStyle(.secondary)
                .frame(width: 130, alignment: .trailing)
            Text(value)
                .textSelection(.enabled)
        }
    }
}

struct AppDetailPlaceholderView: View {
    var body: some View {
        ContentUnavailableView(
            "No App Selected",
            systemImage: "square.stack",
            description: Text("Select an app from the list to view its details.")
        )
    }
}
