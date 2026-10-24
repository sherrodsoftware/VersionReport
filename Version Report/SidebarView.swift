import SwiftUI
import UniformTypeIdentifiers

struct SidebarView: View {

    @ObservedObject var service: VersionReportService
    @Binding var selection: SidebarSelection?

    @Binding var showingSmartGroupSheet: Bool
    @Binding var editingSmartGroup: SmartGroup?
    @State private var renamingGroupID: String?
    @State private var renameText = ""
    @State private var dropTargetGroupID: String?

    private var unreadCount: Int {
        service.apps.filter { $0.hasUnreadUpdate }.count
    }

    var body: some View {
        List {
            Section("Library") {
                sidebarRow(
                    label: Label("All Apps", systemImage: "square.stack"),
                    tag: .allApps,
                    badge: unreadCount
                )
            }

            Section("Groups") {
                ForEach(service.groups) { group in
                    groupRow(group)
                }
                .onMove { from, to in
                    service.moveGroups(from: from, to: to)
                }
            }

            if !service.smartGroups.isEmpty {
                Section("Smart Groups") {
                    ForEach(service.smartGroups) { sg in
                        smartGroupRow(sg)
                    }
                    .onMove { from, to in
                        service.moveSmartGroups(from: from, to: to)
                    }
                }
            }
        }
        .listStyle(.sidebar)
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

    // Generic row with manual tap-based selection and native highlight via listRowBackground.
    private func sidebarRow<L: View>(label: L, tag: SidebarSelection, badge: Int) -> some View {
        label
            .badge(badge)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .onTapGesture { selection = tag }
            .listRowBackground(
                RoundedRectangle(cornerRadius: 6)
                    .fill(selection == tag
                          ? Color.accentColor.opacity(0.18)
                          : Color.clear)
                    .padding(.horizontal, 4)
            )
    }

    private func groupRow(_ group: AppGroup) -> some View {
        let unread = service.apps.filter { group.appIDs.contains($0.id) && $0.hasUnreadUpdate }.count
        let isDropTarget = dropTargetGroupID == group.id

        return Label(group.name, systemImage: "folder")
            .badge(unread)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .onTapGesture { selection = .group(group.id) }
            .listRowBackground(
                RoundedRectangle(cornerRadius: 6)
                    .fill(selectionOrDropColor(for: group.id, isDropTarget: isDropTarget))
                    .padding(.horizontal, 4)
            )
            .contextMenu {
                Button("Rename…") {
                    renameText = group.name
                    renamingGroupID = group.id
                }
                Divider()
                Button("Delete Group", role: .destructive) {
                    if case .group(let id) = selection, id == group.id {
                        selection = .allApps
                    }
                    service.deleteGroup(id: group.id)
                }
            }
            .onDrop(of: [UTType.utf8PlainText], isTargeted: Binding(
                get: { dropTargetGroupID == group.id },
                set: { dropTargetGroupID = $0 ? group.id : nil }
            )) { providers in
                for provider in providers {
                    provider.loadDataRepresentation(for: .utf8PlainText) { data, _ in
                        guard let data,
                              let raw = String(data: data, encoding: .utf8) else { return }
                        let ids = raw.components(separatedBy: "\n").filter { !$0.isEmpty }
                        DispatchQueue.main.async {
                            for id in ids { service.addApp(id, toGroup: group.id) }
                            selection = .group(group.id)
                        }
                    }
                }
                return true
            }
    }

    private func smartGroupRow(_ sg: SmartGroup) -> some View {
        let count = service.apps.filter { sg.evaluate($0) }.count
        let unread = service.apps.filter { sg.evaluate($0) && $0.hasUnreadUpdate }.count
        return Label(sg.name, systemImage: "gearshape.2")
            .badge(unread)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .onTapGesture { selection = .smartGroup(sg.id) }
            .listRowBackground(
                RoundedRectangle(cornerRadius: 6)
                    .fill(selectionIsSmartGroup(sg.id) ? Color.accentColor.opacity(0.18) : Color.clear)
                    .padding(.horizontal, 4)
            )
            .contextMenu {
                Text("\(count) app\(count == 1 ? "" : "s") match\(count == 1 ? "es" : "")")
                Divider()
                Button("Edit Smart Group…") {
                    editingSmartGroup = sg
                    showingSmartGroupSheet = true
                }
                Divider()
                Button("Delete Smart Group", role: .destructive) {
                    if case .smartGroup(let id) = selection, id == sg.id {
                        selection = .allApps
                    }
                    service.deleteSmartGroup(id: sg.id)
                }
            }
    }

    private func selectionIsSmartGroup(_ id: String) -> Bool {
        if case .smartGroup(let sid) = selection { return sid == id }
        return false
    }

    private func selectionOrDropColor(for groupID: String, isDropTarget: Bool) -> Color {
        if isDropTarget { return Color.accentColor.opacity(0.28) }
        if case .group(let id) = selection, id == groupID { return Color.accentColor.opacity(0.18) }
        return .clear
    }
}
