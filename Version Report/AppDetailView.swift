import SwiftUI
import UniformTypeIdentifiers

struct AppDetailView: View {

    let app: MonitoredApp
    let service: VersionReportService
    let onEdit: () -> Void

    @State private var iconDropTargeted = false

    private func formatDate(_ date: Date?) -> String {
        date?.formatted(date: .abbreviated, time: .shortened) ?? "Never"
    }

    private func handleIconDrop(_ providers: [NSItemProvider]) -> Bool {
        let imageTypes = [UTType.image, UTType.png, UTType.jpeg, UTType.tiff, UTType.icns]
        guard let provider = providers.first(where: { p in
            imageTypes.contains { p.hasItemConformingToTypeIdentifier($0.identifier) }
        }) else { return false }

        let type = imageTypes.first { provider.hasItemConformingToTypeIdentifier($0.identifier) }!
        provider.loadDataRepresentation(for: type) { data, _ in
            guard let data, let image = NSImage(data: data) else { return }
            DispatchQueue.main.async {
                service.saveCustomIcon(image, forID: app.iconName)
            }
        }
        return true
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {

                HStack(spacing: 16) {
                    ZStack(alignment: .bottomTrailing) {
                        Image(nsImage: service.icon(for: app))
                            .resizable()
                            .scaledToFit()
                            .frame(width: 64, height: 64)
                            .clipShape(RoundedRectangle(cornerRadius: 12))

                        // Camera badge — always visible to signal the drop zone
                        Image(systemName: "camera.circle.fill")
                            .symbolRenderingMode(.palette)
                            .foregroundStyle(.white, iconDropTargeted ? Color.accentColor : Color.secondary)
                            .font(.system(size: 18))
                            .offset(x: 4, y: 4)
                    }
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .strokeBorder(iconDropTargeted ? Color.accentColor : Color.secondary.opacity(0.3),
                                          style: StrokeStyle(lineWidth: iconDropTargeted ? 2 : 1,
                                                             dash: iconDropTargeted ? [] : [4, 3]))
                    )
                    .onDrop(of: [.image, .png, .jpeg, .tiff, .icns],
                            isTargeted: $iconDropTargeted,
                            perform: handleIconDrop)
                    .help("Drag an image here to set a custom icon")

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

                if let error = app.lastCheckError {
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                        Text(error)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                    }
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))

                    Divider()
                }

                VStack(alignment: .leading, spacing: 8) {
                    if let vendor = app.vendor {
                        detailRow("Vendor", value: vendor)
                    }

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

                    if let url = app.latestReleaseURL {
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Text("Download")
                                .foregroundStyle(.secondary)
                                .frame(width: 130, alignment: .trailing)
                            Link("Get Latest Release", destination: url)
                                .font(.body)
                        }
                    }
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
