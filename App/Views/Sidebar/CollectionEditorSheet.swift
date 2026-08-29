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
            // Labels share one column so the controls line up.
            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 12) {
                GridRow {
                    Text("Name")
                    TextField("Name", text: $draft.collection.name)
                        .textFieldStyle(.roundedBorder)
                }
                GridRow {
                    Text("Match")
                    // Empty title: even a hidden label reserves width on macOS
                    // and pushes the control off the Name field's edge.
                    Picker("", selection: $draft.collection.matchAll) {
                        Text("All").tag(true)
                        Text("Any").tag(false)
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .fixedSize()
                }
            }

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

            // A plain scroll view, not a List: List adds side insets of its
            // own that no style removes, and rows are deleted via their button.
            ScrollView {
                VStack(spacing: 8) {
                    ForEach($draft.rules) { $rule in
                        ruleRow($rule)
                    }
                }
            }
            .frame(maxWidth: .infinity, minHeight: 150)

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

    // MARK: Rule row: type · operator · value, three equal columns

    private func ruleRow(_ rule: Binding<CollectionDraft.DraftRule>) -> some View {
        HStack(spacing: 8) {
            FullWidthPicker(
                selection: typeBinding(rule),
                options: Self.selectableTypes,
                title: typeName
            )

            FullWidthPicker(
                selection: rule.operation,
                options: operators(for: rule.wrappedValue.type, including: rule.wrappedValue.operation),
                title: { operatorName($0, for: rule.wrappedValue.type) }
            )

            // Equal-width columns keep the delete button at the right edge,
            // whatever control the type uses.
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
            FullWidthPicker(
                selection: rule.value,
                options: [""] + keywordGroups.compactMap { $0.id.map(String.init) },
                title: { id in keywordGroups.first { $0.id.map(String.init) == id }?.name ?? "Select Group…" }
            )
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
            // star.slash matches the sidebar's UNRATED row (U28).
            Button {
                value.wrappedValue = "0"
            } label: {
                Image(systemName: "star.slash")
                    .foregroundStyle(value.wrappedValue == "0" ? Color.accentColor : .secondary)
            }
            .buttonStyle(.borderless)
            .help("Unrated")
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

    /// Day-granular: the picker offers only a date, so the stored timestamp
    /// is local midnight of that day (`QueryEngine.dateRule` compares raw
    /// timestamps). "After 23 May" therefore starts at 00:00 of the 23rd and
    /// "Before 23 May" ends at that same instant — not at the wall-clock time
    /// the rule happened to be created.
    private func dateBinding(_ value: Binding<String>) -> Binding<Date> {
        Binding(
            get: { Double(value.wrappedValue).map { Date(timeIntervalSince1970: $0) } ?? Date() },
            set: { value.wrappedValue = Self.dayTimestamp($0) }
        )
    }

    private static func dayTimestamp(_ date: Date) -> String {
        "\(Int(Calendar.current.startOfDay(for: date).timeIntervalSince1970))"
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
        case .captureDate, .dateRange: Self.dayTimestamp(Date())
        default: ""
        }
    }
}

/// A pop-up that fills its column. SwiftUI's menu `Picker` (and `Menu`) wrap
/// an NSPopUpButton sized to its widest item and ignore `maxWidth`, which left
/// the three rule columns visibly unequal — so the button is hosted directly
/// with horizontal hugging turned off.
private struct FullWidthPicker<Option: Hashable>: NSViewRepresentable {
    @Binding var selection: Option
    let options: [Option]
    let title: (Option) -> String

    func makeNSView(context: Context) -> NSPopUpButton {
        let button = NSPopUpButton(frame: .zero, pullsDown: false)
        button.target = context.coordinator
        button.action = #selector(Coordinator.changed(_:))
        button.setContentHuggingPriority(.defaultLow, for: .horizontal)
        button.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return button
    }

    func updateNSView(_ button: NSPopUpButton, context: Context) {
        context.coordinator.parent = self
        let titles = options.map(title)
        if button.itemTitles != titles {
            button.removeAllItems()
            button.addItems(withTitles: titles)
        }
        if let index = options.firstIndex(of: selection), button.indexOfSelectedItem != index {
            button.selectItem(at: index)
        }
    }

    /// Take the full proposed width; otherwise SwiftUI falls back to the
    /// button's intrinsic (widest-item) width and centres it in the column.
    func sizeThatFits(_ proposal: ProposedViewSize, nsView: NSPopUpButton, context: Context) -> CGSize? {
        CGSize(width: proposal.width ?? nsView.intrinsicContentSize.width,
               height: nsView.intrinsicContentSize.height)
    }

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    final class Coordinator: NSObject {
        var parent: FullWidthPicker
        init(parent: FullWidthPicker) { self.parent = parent }

        @objc func changed(_ sender: NSPopUpButton) {
            let index = sender.indexOfSelectedItem
            guard parent.options.indices.contains(index) else { return }
            parent.selection = parent.options[index]
        }
    }
}
