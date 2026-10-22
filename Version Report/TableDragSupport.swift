import AppKit
import SwiftUI

/// Bridges AppKit drag-and-drop into the SwiftUI Table.
///
/// SwiftUI's Table is backed by NSTableView, which intercepts mouse events
/// before SwiftUI's .onDrag ever fires. The correct AppKit approach is to
/// observe mouse events via NSEvent.addLocalMonitorForEvents and call
/// NSTableView.beginDraggingSession directly when a drag is detected.
///
/// This does NOT replace SwiftUI's own dataSource/delegate on NSTableView.
/// The event monitor always returns the original event unchanged, so SwiftUI's
/// row selection, sorting, and column resizing all continue to work normally.
final class TableDragCoordinator: NSObject, NSDraggingSource {

    var filteredApps: [MonitoredApp] = []
    var selectedAppIDs: Set<MonitoredApp.ID> = []
    var iconProvider: ((MonitoredApp) -> NSImage)?

    private weak var tableView: NSTableView?
    private var monitor: Any?
    private var mouseDownRow: Int = -1
    private var mouseDownPoint: NSPoint = .zero
    private var sessionActive = false

    func attach(to window: NSWindow) {
        guard monitor == nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(
            matching: [.leftMouseDown, .leftMouseDragged, .leftMouseUp]
        ) { [weak self] event in
            self?.handle(event, in: window)
            return event  // always pass through — never block SwiftUI's handling
        }
    }

    func detach() {
        if let m = monitor { NSEvent.removeMonitor(m) }
        monitor = nil
        tableView = nil
    }

    // MARK: - Event handling

    private func handle(_ event: NSEvent, in window: NSWindow) {
        guard let tv = resolvedTableView(in: window) else { return }
        let pt = tv.convert(event.locationInWindow, from: nil)

        switch event.type {

        case .leftMouseDown:
            sessionActive = false
            let row = tv.row(at: pt)
            mouseDownRow = row >= 0 ? row : -1
            mouseDownPoint = pt

        case .leftMouseDragged:
            guard !sessionActive,
                  mouseDownRow >= 0,
                  mouseDownRow < filteredApps.count else { return }

            let dx = pt.x - mouseDownPoint.x
            let dy = pt.y - mouseDownPoint.y
            guard dx * dx + dy * dy > 25 else { return }  // 5 pt threshold

            sessionActive = true

            let app = filteredApps[mouseDownRow]

            // If the dragged row is part of the current selection, drag all
            // selected apps; otherwise drag only the row under the cursor.
            let appsToDrag: [MonitoredApp]
            if selectedAppIDs.contains(app.id) {
                appsToDrag = filteredApps.filter { selectedAppIDs.contains($0.id) }
            } else {
                appsToDrag = [app]
            }

            let ids = appsToDrag.map(\.id).joined(separator: "\n")
            let pbItem = NSPasteboardItem()
            pbItem.setString(ids, forType: .string)

            let dragItem = NSDraggingItem(pasteboardWriter: pbItem)
            let icon = iconProvider?(app) ?? NSImage()
            dragItem.setDraggingFrame(
                NSRect(x: pt.x - 16, y: pt.y - 16, width: 32, height: 32),
                contents: icon
            )

            tv.beginDraggingSession(with: [dragItem], event: event, source: self)

        case .leftMouseUp:
            sessionActive = false
            if mouseDownRow >= 0 { mouseDownRow = -1 }

        default:
            break
        }
    }

    // MARK: - NSDraggingSource

    func draggingSession(
        _ session: NSDraggingSession,
        sourceOperationMaskFor context: NSDraggingContext
    ) -> NSDragOperation { .copy }

    // MARK: - Helpers

    private func resolvedTableView(in window: NSWindow) -> NSTableView? {
        if let tv = tableView { return tv }
        tableView = firstTableView(in: window.contentView)
        return tableView
    }

    private func firstTableView(in view: NSView?) -> NSTableView? {
        guard let view else { return nil }
        if let tv = view as? NSTableView { return tv }
        for sub in view.subviews {
            if let found = firstTableView(in: sub) { return found }
        }
        return nil
    }
}

/// Zero-size NSViewRepresentable placed inside the Table that attaches the
/// drag coordinator to the window once the view hierarchy is live.
struct TableDragSourceView: NSViewRepresentable {

    let filteredApps: [MonitoredApp]
    let selectedAppIDs: Set<MonitoredApp.ID>
    let iconProvider: (MonitoredApp) -> NSImage

    func makeCoordinator() -> TableDragCoordinator { TableDragCoordinator() }

    func makeNSView(context: Context) -> NSView { NSView() }

    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.filteredApps = filteredApps
        context.coordinator.selectedAppIDs = selectedAppIDs
        context.coordinator.iconProvider = iconProvider
        DispatchQueue.main.async {
            guard let window = nsView.window else { return }
            context.coordinator.attach(to: window)
        }
    }

    static func dismantleNSView(_ nsView: NSView, coordinator: TableDragCoordinator) {
        coordinator.detach()
    }
}
