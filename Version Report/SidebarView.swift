import SwiftUI

/// The sidebar: All Apps, groups, and smart groups.
///
/// The list itself is an AppKit source list (`SidebarOutlineView`). SwiftUI's sidebar `List`
/// decides on its own whether a drop lands on a row or between rows, and only treats the
/// row's top and bottom edges as "on" it, so dropping apps onto a group was hit-or-miss.
/// AppKit lets the sidebar send every app drop to the group under the pointer, the way
/// Mail, Music, and NetNewsWire sidebars work.
struct SidebarView: View {

    let service: VersionReportService
    @Binding var selection: SidebarSelection?

    @Binding var showingSmartGroupSheet: Bool
    @Binding var editingSmartGroup: SmartGroup?
    @State private var renamingGroupID: String?
    @State private var renameText = ""

    var body: some View {
        SidebarOutlineView(
            content: SidebarContent(service: service),
            selection: $selection,
            actions: SidebarActions(
                addApps: { ids, groupID in
                    service.addApps(ids, toGroup: groupID)
                    selection = .group(groupID)
                },
                moveGroup: { from, to in service.moveGroups(from: IndexSet(integer: from), to: to) },
                moveSmartGroup: { from, to in service.moveSmartGroups(from: IndexSet(integer: from), to: to) },
                renameGroup: { group in
                    renameText = group.name
                    renamingGroupID = group.id
                },
                deleteGroup: { id in
                    if selection == .group(id) { selection = .allApps }
                    service.deleteGroup(id: id)
                },
                editSmartGroup: { smartGroup in
                    editingSmartGroup = smartGroup
                    showingSmartGroupSheet = true
                },
                deleteSmartGroup: { id in
                    if selection == .smartGroup(id) { selection = .allApps }
                    service.deleteSmartGroup(id: id)
                }
            )
        )
        .alert("Rename Group", isPresented: Binding(
            get: { renamingGroupID != nil },
            set: { if !$0 { renamingGroupID = nil } }
        )) {
            TextField("Group Name", text: $renameText)
            Button("Cancel", role: .cancel) { renamingGroupID = nil }
            Button("Rename") {
                if let id = renamingGroupID {
                    let trimmed = renameText.trimmingCharacters(in: .whitespaces)
                    if !trimmed.isEmpty { service.renameGroup(id: id, to: trimmed) }
                }
                renamingGroupID = nil
            }
        }
    }
}

// MARK: - Content

/// What the sidebar shows, with every count worked out once per change rather than per row.
struct SidebarContent: Equatable {

    struct Row: Equatable {
        let selection: SidebarSelection
        let title: String
        let systemImage: String
        let unread: Int
        /// Smart groups only: how many apps match.
        let matchCount: Int?
    }

    let allApps: Row
    let groups: [Row]
    let smartGroups: [Row]
    let groupModels: [AppGroup]
    let smartGroupModels: [SmartGroup]

    init(service: VersionReportService) {
        let apps = service.apps
        let unreadIDs = Set(apps.lazy.filter(\.hasUnreadUpdate).map(\.id))

        allApps = Row(selection: .allApps, title: "All Apps", systemImage: "square.stack",
                      unread: unreadIDs.count, matchCount: nil)

        groupModels = service.groups
        groups = service.groups.map { group in
            Row(selection: .group(group.id), title: group.name, systemImage: "folder",
                unread: group.appIDs.reduce(0) { $0 + (unreadIDs.contains($1) ? 1 : 0) },
                matchCount: nil)
        }

        smartGroupModels = service.smartGroups
        smartGroups = service.smartGroups.map { smartGroup in
            let matches = apps.filter { smartGroup.evaluate($0) }
            return Row(selection: .smartGroup(smartGroup.id), title: smartGroup.name,
                       systemImage: "gearshape.2",
                       unread: matches.reduce(0) { $0 + ($1.hasUnreadUpdate ? 1 : 0) },
                       matchCount: matches.count)
        }
    }
}

struct SidebarActions {
    var addApps: ([String], String) -> Void
    var moveGroup: (Int, Int) -> Void
    var moveSmartGroup: (Int, Int) -> Void
    var renameGroup: (AppGroup) -> Void
    var deleteGroup: (String) -> Void
    var editSmartGroup: (SmartGroup) -> Void
    var deleteSmartGroup: (String) -> Void
}

// MARK: - AppKit source list

struct SidebarOutlineView: NSViewRepresentable {

    var content: SidebarContent
    @Binding var selection: SidebarSelection?
    var actions: SidebarActions

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSScrollView {
        let outline = NSOutlineView()
        outline.style = .sourceList
        outline.headerView = nil
        outline.floatsGroupRows = false
        outline.rowSizeStyle = .default
        outline.allowsEmptySelection = true
        outline.setAccessibilityLabel("Sidebar")

        let column = NSTableColumn(identifier: .init("Sidebar"))
        column.resizingMask = .autoresizingMask
        outline.addTableColumn(column)
        outline.outlineTableColumn = column

        outline.dataSource = context.coordinator
        outline.delegate = context.coordinator
        outline.registerForDraggedTypes([.string, Coordinator.sidebarItemType])
        outline.setDraggingSourceOperationMask(.move, forLocal: true)
        outline.draggingDestinationFeedbackStyle = .sourceList

        let menu = NSMenu()
        menu.delegate = context.coordinator
        outline.menu = menu

        let scrollView = NSScrollView()
        scrollView.documentView = outline
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true

        context.coordinator.outline = outline
        context.coordinator.apply(content, selection: selection)
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        context.coordinator.parent = self
        context.coordinator.apply(content, selection: selection)
    }

    // MARK: Coordinator

    @MainActor
    final class Coordinator: NSObject, NSOutlineViewDataSource, NSOutlineViewDelegate, NSMenuDelegate {

        /// Groups and smart groups dragged within the sidebar to reorder them.
        static let sidebarItemType = NSPasteboard.PasteboardType("com.sherrodsoftware.versionreport.sidebar-item")

        enum Section: String { case library = "Library", groups = "Groups", smartGroups = "Smart Groups" }

        /// Outline items. Classes, because NSOutlineView tracks items by identity.
        final class SectionItem: NSObject {
            let section: Section
            var rows: [RowItem] = []
            init(_ section: Section) { self.section = section }
        }
        final class RowItem: NSObject {
            var row: SidebarContent.Row
            init(_ row: SidebarContent.Row) { self.row = row }
        }

        var parent: SidebarOutlineView
        weak var outline: NSOutlineView?

        private let library = SectionItem(.library)
        private let groups = SectionItem(.groups)
        private let smartGroups = SectionItem(.smartGroups)
        private var sections: [SectionItem] = []
        private var current: SidebarContent?
        private var isApplying = false

        init(_ parent: SidebarOutlineView) { self.parent = parent }

        // MARK: Updating

        func apply(_ content: SidebarContent, selection: SidebarSelection?) {
            guard let outline else { return }
            isApplying = true
            defer { isApplying = false }

            if content != current {
                current = content
                // Reuse items whose selection is unchanged, so expansion and drag state survive.
                library.rows = reuse(library.rows, for: [content.allApps])
                groups.rows = reuse(groups.rows, for: content.groups)
                smartGroups.rows = reuse(smartGroups.rows, for: content.smartGroups)
                sections = [library, groups] + (content.smartGroups.isEmpty ? [] : [smartGroups])
                outline.reloadData()
                for section in sections { outline.expandItem(section) }
            }

            let row = selection.flatMap { rowIndex(of: $0) } ?? -1
            if row != outline.selectedRow {
                if row >= 0 {
                    outline.selectRowIndexes([row], byExtendingSelection: false)
                    outline.scrollRowToVisible(row)
                } else {
                    outline.deselectAll(nil)
                }
            }
        }

        private func reuse(_ old: [RowItem], for rows: [SidebarContent.Row]) -> [RowItem] {
            var bySelection = Dictionary(old.map { ($0.row.selection, $0) }, uniquingKeysWith: { a, _ in a })
            return rows.map { row in
                if let item = bySelection.removeValue(forKey: row.selection) {
                    item.row = row
                    return item
                }
                return RowItem(row)
            }
        }

        private func rowIndex(of selection: SidebarSelection) -> Int? {
            guard let outline else { return nil }
            for section in sections {
                if let item = section.rows.first(where: { $0.row.selection == selection }) {
                    let row = outline.row(forItem: item)
                    return row >= 0 ? row : nil
                }
            }
            return nil
        }

        // MARK: Data source

        func outlineView(_ outlineView: NSOutlineView, numberOfChildrenOfItem item: Any?) -> Int {
            guard let item else { return sections.count }
            return (item as? SectionItem)?.rows.count ?? 0
        }

        func outlineView(_ outlineView: NSOutlineView, child index: Int, ofItem item: Any?) -> Any {
            guard let section = item as? SectionItem else { return sections[index] }
            return section.rows[index]
        }

        func outlineView(_ outlineView: NSOutlineView, isItemExpandable item: Any) -> Bool {
            item is SectionItem
        }

        // MARK: Delegate

        func outlineView(_ outlineView: NSOutlineView, isGroupItem item: Any) -> Bool {
            item is SectionItem
        }

        func outlineView(_ outlineView: NSOutlineView, shouldSelectItem item: Any) -> Bool {
            item is RowItem
        }

        func outlineView(_ outlineView: NSOutlineView, viewFor tableColumn: NSTableColumn?, item: Any) -> NSView? {
            if let section = item as? SectionItem {
                let id = NSUserInterfaceItemIdentifier("SidebarHeader")
                let cell = outlineView.makeView(withIdentifier: id, owner: nil) as? NSTableCellView
                    ?? Self.makeHeaderCell(id)
                cell.textField?.stringValue = section.section.rawValue
                return cell
            }
            guard let row = (item as? RowItem)?.row else { return nil }
            let id = NSUserInterfaceItemIdentifier("SidebarRow")
            let cell = outlineView.makeView(withIdentifier: id, owner: nil) as? SidebarRowCell
                ?? SidebarRowCell(identifier: id)
            cell.configure(row)
            return cell
        }

        func outlineViewSelectionDidChange(_ notification: Notification) {
            guard !isApplying, let outline else { return }
            let newSelection = (outline.item(atRow: outline.selectedRow) as? RowItem)?.row.selection
            if newSelection != parent.selection {
                parent.selection = newSelection
            }
        }

        private static func makeHeaderCell(_ id: NSUserInterfaceItemIdentifier) -> NSTableCellView {
            let cell = NSTableCellView()
            cell.identifier = id
            let label = NSTextField(labelWithString: "")
            label.translatesAutoresizingMaskIntoConstraints = false
            cell.addSubview(label)
            cell.textField = label
            NSLayoutConstraint.activate([
                label.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 2),
                label.trailingAnchor.constraint(lessThanOrEqualTo: cell.trailingAnchor),
                label.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
            ])
            return cell
        }

        // MARK: Dragging groups to reorder them

        func outlineView(_ outlineView: NSOutlineView, pasteboardWriterForItem item: Any) -> (any NSPasteboardWriting)? {
            guard let row = (item as? RowItem)?.row else { return nil }
            let token: String
            switch row.selection {
            case .group(let id): token = "group:\(id)"
            case .smartGroup(let id): token = "smartGroup:\(id)"
            case .allApps: return nil
            }
            let pasteboardItem = NSPasteboardItem()
            pasteboardItem.setString(token, forType: Self.sidebarItemType)
            return pasteboardItem
        }

        private func draggedSidebarItem(_ info: any NSDraggingInfo) -> (section: SectionItem, index: Int)? {
            guard let token = info.draggingPasteboard.string(forType: Self.sidebarItemType) else { return nil }
            let parts = token.split(separator: ":", maxSplits: 1).map(String.init)
            guard parts.count == 2 else { return nil }
            let section = parts[0] == "group" ? groups : smartGroups
            let selection: SidebarSelection = parts[0] == "group" ? .group(parts[1]) : .smartGroup(parts[1])
            guard let index = section.rows.firstIndex(where: { $0.row.selection == selection }) else { return nil }
            return (section, index)
        }

        // MARK: Dropping

        func outlineView(_ outlineView: NSOutlineView, validateDrop info: any NSDraggingInfo,
                         proposedItem item: Any?, proposedChildIndex index: Int) -> NSDragOperation {

            // A group or smart group being reordered: only between rows of its own section.
            if let dragged = draggedSidebarItem(info) {
                if let section = item as? SectionItem, section === dragged.section, index != NSOutlineViewDropOnItemIndex {
                    return .move
                }
                // Over one of the section's rows: drop above or below it, whichever half the pointer is in.
                let point = outlineView.convert(info.draggingLocation, from: nil)
                let row = outlineView.row(at: point)
                guard row >= 0, let rowItem = outlineView.item(atRow: row) as? RowItem,
                      let position = dragged.section.rows.firstIndex(of: rowItem) else { return [] }
                let rect = outlineView.rect(ofRow: row)
                let insertion = point.y < rect.midY ? position : position + 1
                outlineView.setDropItem(dragged.section, dropChildIndex: insertion)
                return .move
            }

            // Apps from the table: always onto the group under the pointer, anywhere on its row.
            guard info.draggingPasteboard.canReadObject(forClasses: [NSString.self], options: nil) else { return [] }
            let point = outlineView.convert(info.draggingLocation, from: nil)
            let row = outlineView.row(at: point)
            guard row >= 0, let rowItem = outlineView.item(atRow: row) as? RowItem,
                  case .group = rowItem.row.selection else { return [] }
            outlineView.setDropItem(rowItem, dropChildIndex: NSOutlineViewDropOnItemIndex)
            return .copy
        }

        func outlineView(_ outlineView: NSOutlineView, acceptDrop info: any NSDraggingInfo,
                         item: Any?, childIndex index: Int) -> Bool {

            if let dragged = draggedSidebarItem(info) {
                guard let section = item as? SectionItem, section === dragged.section,
                      index != NSOutlineViewDropOnItemIndex else { return false }
                if section === groups {
                    parent.actions.moveGroup(dragged.index, index)
                } else {
                    parent.actions.moveSmartGroup(dragged.index, index)
                }
                return true
            }

            guard let rowItem = item as? RowItem, case .group(let groupID) = rowItem.row.selection else { return false }
            let strings = (info.draggingPasteboard.pasteboardItems ?? []).compactMap { $0.string(forType: .string) }
            let ids = strings
                .flatMap { $0.components(separatedBy: "\n") }
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
            guard !ids.isEmpty else { return false }
            parent.actions.addApps(ids, groupID)
            return true
        }

        // MARK: Context menu

        func menuNeedsUpdate(_ menu: NSMenu) {
            menu.removeAllItems()
            guard let outline, outline.clickedRow >= 0,
                  let row = (outline.item(atRow: outline.clickedRow) as? RowItem)?.row,
                  let content = current else { return }

            switch row.selection {
            case .allApps:
                break
            case .group(let id):
                guard let group = content.groupModels.first(where: { $0.id == id }) else { return }
                menu.addItem(ClosureMenuItem("Rename…") { [weak self] in self?.parent.actions.renameGroup(group) })
                menu.addItem(.separator())
                menu.addItem(ClosureMenuItem("Delete Group") { [weak self] in self?.parent.actions.deleteGroup(id) })
            case .smartGroup(let id):
                guard let smartGroup = content.smartGroupModels.first(where: { $0.id == id }) else { return }
                let count = row.matchCount ?? 0
                let info = NSMenuItem(title: "\(count) app\(count == 1 ? "" : "s") match\(count == 1 ? "es" : "")",
                                      action: nil, keyEquivalent: "")
                info.isEnabled = false
                menu.addItem(info)
                menu.addItem(.separator())
                menu.addItem(ClosureMenuItem("Edit Smart Group…") { [weak self] in self?.parent.actions.editSmartGroup(smartGroup) })
                menu.addItem(.separator())
                menu.addItem(ClosureMenuItem("Delete Smart Group") { [weak self] in self?.parent.actions.deleteSmartGroup(id) })
            }
        }
    }
}

// MARK: - Row cell

/// An icon, a name, and an unread count, laid out like a standard source list row.
final class SidebarRowCell: NSTableCellView {

    private let icon = NSImageView()
    private let title = NSTextField(labelWithString: "")
    private let badge = NSTextField(labelWithString: "")

    init(identifier: NSUserInterfaceItemIdentifier) {
        super.init(frame: .zero)
        self.identifier = identifier

        icon.translatesAutoresizingMaskIntoConstraints = false
        icon.symbolConfiguration = .init(scale: .medium)
        icon.contentTintColor = .controlAccentColor
        title.translatesAutoresizingMaskIntoConstraints = false
        title.lineBreakMode = .byTruncatingTail
        title.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        badge.translatesAutoresizingMaskIntoConstraints = false
        badge.textColor = .secondaryLabelColor
        badge.alignment = .right
        badge.setContentHuggingPriority(.required, for: .horizontal)
        badge.setContentCompressionResistancePriority(.required, for: .horizontal)

        addSubview(icon)
        addSubview(title)
        addSubview(badge)
        imageView = icon
        textField = title

        NSLayoutConstraint.activate([
            icon.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 2),
            icon.centerYAnchor.constraint(equalTo: centerYAnchor),
            icon.widthAnchor.constraint(equalToConstant: 18),
            title.leadingAnchor.constraint(equalTo: icon.trailingAnchor, constant: 6),
            title.centerYAnchor.constraint(equalTo: centerYAnchor),
            badge.leadingAnchor.constraint(greaterThanOrEqualTo: title.trailingAnchor, constant: 6),
            badge.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -6),
            badge.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    func configure(_ row: SidebarContent.Row) {
        icon.image = NSImage(systemSymbolName: row.systemImage, accessibilityDescription: nil)
        title.stringValue = row.title
        badge.stringValue = row.unread > 0 ? "\(row.unread)" : ""
        badge.isHidden = row.unread == 0
        setAccessibilityLabel(row.unread > 0 ? "\(row.title), \(row.unread) unread" : row.title)
    }
}

/// A menu item that runs a closure, for the sidebar's context menu.
private final class ClosureMenuItem: NSMenuItem {
    private let handler: () -> Void

    init(_ title: String, handler: @escaping () -> Void) {
        self.handler = handler
        super.init(title: title, action: #selector(run), keyEquivalent: "")
        target = self
    }

    required init(coder: NSCoder) { fatalError("init(coder:) is not used") }

    @objc private func run() { handler() }
}
