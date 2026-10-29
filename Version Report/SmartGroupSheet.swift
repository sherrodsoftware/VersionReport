import SwiftUI

struct SmartGroupSheet: View {

    let service: VersionReportService
    let editingSmartGroup: SmartGroup?
    let onDismiss: () -> Void
    let onSave: (SmartGroup) -> Void

    @State private var name: String
    @State private var match: SmartGroupMatch
    @State private var criteria: [SmartGroupCriterion]

    private let sourceTypeOptions = ["Homebrew Cask", "GitHub Releases", "App Store", "Sparkle Feed"]

    init(service: VersionReportService, editingSmartGroup: SmartGroup? = nil, onDismiss: @escaping () -> Void, onSave: @escaping (SmartGroup) -> Void) {
        self.service = service
        self.editingSmartGroup = editingSmartGroup
        self.onDismiss = onDismiss
        self.onSave = onSave
        _name = State(initialValue: editingSmartGroup?.name ?? "")
        _match = State(initialValue: editingSmartGroup?.match ?? .all)
        _criteria = State(initialValue: editingSmartGroup?.criteria ?? [SmartGroupCriterion.defaultCriterion()])
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {

            Text(editingSmartGroup == nil ? "New Smart Group" : "Edit Smart Group")
                .font(.headline)

            HStack(spacing: 8) {
                Text("Name:")
                TextField("Smart Group Name", text: $name)
                    .textFieldStyle(.roundedBorder)
            }

            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 6) {
                    Text("Match")
                    Picker("", selection: $match) {
                        ForEach(SmartGroupMatch.allCases, id: \.self) { m in
                            Text(m.displayName).tag(m)
                        }
                    }
                    .fixedSize()
                    .labelsHidden()
                    Text("of the following criteria:")
                }
                .font(.body)

                VStack(spacing: 6) {
                    ForEach($criteria) { $criterion in
                        CriterionRow(criterion: $criterion, sourceTypeOptions: sourceTypeOptions) {
                            if criteria.count > 1 {
                                criteria.removeAll { $0.id == criterion.id }
                            }
                        }
                    }
                }

                Button {
                    criteria.append(SmartGroupCriterion.defaultCriterion())
                } label: {
                    Label("Add Criterion", systemImage: "plus.circle")
                        .font(.callout)
                }
                .buttonStyle(.borderless)
            }
            .padding(12)
            .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 8))

            // Preview
            let matched = service.apps.filter { app in
                let sg = SmartGroup(id: editingSmartGroup?.id ?? UUID().uuidString,
                                    name: name, match: match, criteria: criteria)
                return sg.evaluate(app)
            }
            HStack {
                Image(systemName: "eye")
                    .foregroundStyle(.secondary)
                Text(matched.isEmpty
                     ? "No apps match these criteria."
                     : "\(matched.count) app\(matched.count == 1 ? "" : "s") match\(matched.count == 1 ? "es" : "") these criteria.")
                    .foregroundStyle(.secondary)
            }
            .font(.callout)

            HStack {
                Button("Cancel", action: onDismiss)
                Spacer()
                Button(editingSmartGroup == nil ? "Create" : "Save") {
                    let sg = SmartGroup(
                        id: editingSmartGroup?.id ?? UUID().uuidString,
                        name: name.trimmingCharacters(in: .whitespaces),
                        match: match,
                        criteria: criteria
                    )
                    onSave(sg)
                }
                .buttonStyle(.borderedProminent)
                .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty || criteria.isEmpty)
            }
        }
        .padding(24)
        .frame(width: 540)
    }
}

private struct CriterionRow: View {

    @Binding var criterion: SmartGroupCriterion
    let sourceTypeOptions: [String]
    let onRemove: () -> Void

    private var availableOperators: [SmartGroupOperator] {
        validOperators(for: criterion.field)
    }

    private var needsTextValue: Bool {
        switch criterion.op {
        case .lessThanDaysAgo, .moreThanDaysAgo: return true
        default: return false
        }
    }

    private var needsVendorText: Bool {
        criterion.field == .vendor && criterion.op != .isNotSet
    }

    private var needsSourcePicker: Bool {
        criterion.field == .sourceType
    }

    var body: some View {
        HStack(spacing: 8) {
            // Field picker
            Picker("", selection: $criterion.field) {
                ForEach(SmartGroupField.allCases, id: \.self) { field in
                    Text(field.displayName).tag(field)
                }
            }
            .labelsHidden()
            .fixedSize()
            .onChange(of: criterion.field) { _, newField in
                // Reset operator to a valid one for the new field
                let ops = validOperators(for: newField)
                if !ops.contains(criterion.op) {
                    criterion.op = ops.first ?? .equals
                }
                criterion.value = defaultValue(for: newField, op: criterion.op)
            }

            // Operator picker
            Picker("", selection: $criterion.op) {
                ForEach(availableOperators, id: \.self) { op in
                    Text(op.displayName).tag(op)
                }
            }
            .labelsHidden()
            .fixedSize()
            .onChange(of: criterion.op) { _, newOp in
                // Keep typed vendor text when switching between is / is not / contains.
                if criterion.field == .vendor && newOp != .isNotSet { return }
                criterion.value = defaultValue(for: criterion.field, op: newOp)
            }

            // Value input
            if needsSourcePicker {
                Picker("", selection: $criterion.value) {
                    ForEach(sourceTypeOptions, id: \.self) { opt in
                        Text(opt).tag(opt)
                    }
                }
                .labelsHidden()
                .fixedSize()
            } else if needsVendorText {
                TextField("Vendor", text: $criterion.value)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 160)
            } else if needsTextValue {
                TextField("days", text: $criterion.value)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 60)
            }

            Spacer()

            Button(action: onRemove) {
                Image(systemName: "minus.circle.fill")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.borderless)
        }
    }

    private func validOperators(for field: SmartGroupField) -> [SmartGroupOperator] {
        switch field {
        case .sourceType:      return [.equals, .notEquals]
        case .vendor:          return [.equals, .notEquals, .contains, .isNotSet]
        case .hasUnreadUpdate: return [.isTrue, .isFalse]
        case .lastChecked, .lastUpdated: return [.lessThanDaysAgo, .moreThanDaysAgo, .never]
        }
    }

    private func defaultValue(for field: SmartGroupField, op: SmartGroupOperator) -> String {
        switch field {
        case .sourceType:      return "Homebrew Cask"
        case .vendor:          return ""
        case .hasUnreadUpdate: return ""
        case .lastChecked, .lastUpdated:
            switch op {
            case .lessThanDaysAgo, .moreThanDaysAgo: return "7"
            default: return ""
            }
        }
    }
}
