import BallastCore
import SwiftUI

/// The Smart Collection rule editor (spec §9.7), editing a copy — Cancel
/// discards, Save writes back wholesale. U10 refinements: the star widget has
/// an "Unrated" position, a Capture Date rule exists, all meaningful operators
/// are offered, and an empty rule list shows a hint instead of silently
/// matching everything.
struct CollectionEditorSheet: View {
    @State var draft: CollectionDraft
    let keywordGroups: [KeywordGroupRecord]
    let onSave: (CollectionDraft) -> Void

    @Environment(\.dismiss) private var dismiss

    /// The types the editor offers (dateRange/importBatch stay internal).
    private static let selectableTypes: [RuleType] =
        [.keyword, .keywordGroup, .rating, .filename, .keywordCount, .captureDate]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Name")
                TextField("Name", text: $draft.collection.name)
                    .textFieldStyle(.roundedBorder)
            }

            Picker("Match", selection: $draft.collection.matchAll) {
                Text("All").tag(true)
                Text("Any").tag(false)
            }
            .pickerStyle(.segmented)
            .frame(width: 220)

            if draft.rules.isEmpty {
                // U10 hint — Q6 makes an empty list match every photo.
                Label(
                    "No rules yet — this collection currently matches every photo. Add rules to narrow it down.",
                    systemImage: "info.circle"
                )
                .font(.callout)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(8)
                .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 6))
            }

            List {
                ForEach($draft.rules) { $rule in
                    ruleRow($rule)
                }
                .onDelete { draft.rules.remove(atOffsets: $0) }
            }
            .listStyle(.inset)
            .frame(minHeight: 150)

            HStack {
                Button {
                    draft.rules.append(.init(type: .keyword, operation: .contains, value: ""))
                } label: {
                    Image(systemName: "plus")
                }
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Save") {
                    onSave(draft)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(16)
        .frame(minWidth: 500, minHeight: 400)
    }

    // MARK: Rule row: type (130) · operator (120) · value control

    private func ruleRow(_ rule: Binding<CollectionDraft.DraftRule>) -> some View {
        HStack(spacing: 8) {
            Picker("", selection: typeBinding(rule)) {
                ForEach(Self.selectableTypes, id: \.self) { type in
                    Text(typeName(type)).tag(type)
                }
            }
            .labelsHidden()
            .frame(width: 130)

            Picker("", selection: rule.operation) {
                ForEach(operators(for: rule.wrappedValue.type, including: rule.wrappedValue.operation), id: \.self) { op in
                    Text(operatorName(op, for: rule.wrappedValue.type)).tag(op)
                }
            }
            .labelsHidden()
            .frame(width: 120)

            // The value takes whatever is left so the delete button always
            // sits at the right edge, whatever control the type uses.
            valueControl(rule)
                .frame(maxWidth: .infinity, alignment: .leading)

            Button {
                draft.rules.removeAll { $0.id == rule.wrappedValue.id }
            } label: {
                Image(systemName: "minus.circle")
            }
            .buttonStyle(.borderless)
        }
    }

    /// Changing the type resets operator and value so a rule can never reach
    /// an unsupported combination through the UI (spec §9.7).
    private func typeBinding(_ rule: Binding<CollectionDraft.DraftRule>) -> Binding<RuleType> {
        Binding(
            get: { rule.wrappedValue.type },
            set: { newType in
                guard newType != rule.wrappedValue.type else { return }
                rule.wrappedValue.type = newType
                rule.wrappedValue.operation = operators(for: newType).first ?? .equals
                rule.wrappedValue.value = defaultValue(for: newType)
            }
        )
    }

    @ViewBuilder
    private func valueControl(_ rule: Binding<CollectionDraft.DraftRule>) -> some View {
        switch rule.wrappedValue.type {
        case .rating:
            starPicker(rule.value)
        case .keywordGroup:
            Picker("", selection: rule.value) {
                Text("Select Group…").tag("")
                ForEach(keywordGroups) { group in
                    if let id = group.id {
                        Text(group.name).tag("\(id)")
                    }
                }
            }
            .labelsHidden()
        case .captureDate, .dateRange:
            // Both compare dates — a raw Unix-timestamp text field would
            // silently produce a never-matching rule.
            DatePicker(
                "",
                selection: dateBinding(rule.value),
                displayedComponents: .date
            )
            .labelsHidden()
        case .keywordCount:
            // Digits only: a non-numeric count would silently never match.
            TextField("Count", text: numericBinding(rule.value))
                .textFieldStyle(.roundedBorder)
                .frame(width: 60)
        case .keyword, .filename, .importBatch:
            TextField("Value", text: rule.value)
                .textFieldStyle(.roundedBorder)
        }
    }

    private func numericBinding(_ value: Binding<String>) -> Binding<String> {
        Binding(
            get: { value.wrappedValue },
            set: { value.wrappedValue = String($0.filter(\.isNumber)) }
        )
    }

    /// U10: unlike the original, "Unrated" (0) is expressible directly —
    /// no more `rating lessThan 1` workaround (Q28 lifted deliberately).
    private func starPicker(_ value: Binding<String>) -> some View {
        HStack(spacing: 2) {
            Button("Unrated") { value.wrappedValue = "0" }
                .buttonStyle(.borderless)
                .font(.caption)
                .foregroundStyle(value.wrappedValue == "0" ? Color.accentColor : .secondary)
            ForEach(1...5, id: \.self) { star in
                let current = Int(value.wrappedValue) ?? -1
                Button {
                    value.wrappedValue = "\(star)"
                } label: {
                    Image(systemName: star <= current ? "star.fill" : "star")
                        .foregroundStyle(star <= current ? .yellow : .secondary)
                }
                .buttonStyle(.borderless)
            }
        }
    }

    private func dateBinding(_ value: Binding<String>) -> Binding<Date> {
        Binding(
            get: { Double(value.wrappedValue).map { Date(timeIntervalSince1970: $0) } ?? Date() },
            set: { value.wrappedValue = "\(Int($0.timeIntervalSince1970))" }
        )
    }

    // MARK: Vocabulary

    private func typeName(_ type: RuleType) -> String {
        switch type {
        case .keyword: "Keyword"
        case .keywordGroup: "Keyword Group"
        case .rating: "Rating"
        case .filename: "Filename"
        case .keywordCount: "Keyword Count"
        case .captureDate: "Capture Date"
        case .dateRange: "Date Added"
        case .importBatch: "Import Batch"
        }
    }

    /// A persisted operator outside the list for its type (older data, a
    /// type whose list shrank) would otherwise render an empty picker the
    /// user cannot correct without changing the type.
    private func operators(for type: RuleType, including current: RuleOperator) -> [RuleOperator] {
        let offered = operators(for: type)
        return offered.contains(current) ? offered : offered + [current]
    }

    private func operators(for type: RuleType) -> [RuleOperator] {
        switch type {
        case .keyword, .filename, .keywordGroup:
            [.contains, .equals, .doesNotContain, .doesNotEqual]
        case .rating, .keywordCount:
            [.equals, .doesNotEqual, .greaterThan, .lessThan]
        case .captureDate, .dateRange:
            [.greaterThan, .lessThan]
        case .importBatch:
            [.equals]
        }
    }

    private func operatorName(_ op: RuleOperator, for type: RuleType) -> String {
        let isDate = type == .captureDate || type == .dateRange
        switch op {
        case .contains: return "Contains"
        case .equals: return "Equals"
        case .doesNotContain: return "Does Not Contain"
        case .doesNotEqual: return "Does Not Equal"
        case .greaterThan: return isDate ? "After" : "Is Bigger"
        case .lessThan: return isDate ? "Before" : "Is Lower"
        }
    }

    private func defaultValue(for type: RuleType) -> String {
        switch type {
        case .rating: "0"
        case .captureDate, .dateRange: "\(Int(Date().timeIntervalSince1970))"
        default: ""
        }
    }
}
