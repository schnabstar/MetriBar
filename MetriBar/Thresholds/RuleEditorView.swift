import MetriBarKit
import SwiftUI

/// Editor of one rule, in a sheet. `onFinish` gets the rule to save, or
/// `nil` if the user cancelled.
struct RuleEditorView: View {
    let isNew: Bool
    let onFinish: (ThresholdRule?) -> Void

    @Environment(AppModel.self) private var model
    @State private var draft: ThresholdRule
    /// Once the user typed a limit, a change of the metric keeps it.
    @State private var limitEdited: Bool

    init(rule: ThresholdRule, isNew: Bool, onFinish: @escaping (ThresholdRule?) -> Void) {
        self.isNew = isNew
        self.onFinish = onFinish
        _draft = State(initialValue: rule)
        _limitEdited = State(initialValue: !isNew)
    }

    private var kind: RuleMetric.Kind { draft.metric.kind }

    var body: some View {
        Form {
            Section {
                Picker("Value", selection: kindBinding) {
                    ForEach(RuleMetric.Kind.allCases, id: \.self) { kind in
                        Text(RuleText.kindName(kind)).tag(kind)
                    }
                }
                if kind.supportsItem {
                    TextField(kind == .disk ? "Mount point" : "Sensor", text: itemBinding, prompt: Text("All"))
                        .autocorrectionDisabled()
                }
                Picker("Fires when", selection: $draft.comparison) {
                    ForEach(ThresholdRule.Comparison.allCases, id: \.self) { comparison in
                        Text(RuleText.comparisonLabel(comparison)).tag(comparison)
                    }
                }
                .pickerStyle(.segmented)
                LabeledContent("Limit") {
                    HStack(spacing: 6) {
                        TextField("Limit", value: limitBinding, format: .number)
                            .labelsHidden()
                            .multilineTextAlignment(.trailing)
                            .frame(width: 90)
                        Text(RuleText.unitSymbol(kind.unit))
                            .foregroundStyle(.secondary)
                            .frame(minWidth: 36, alignment: .leading)
                    }
                }
                Picker("Has to last", selection: $draft.holdSeconds) {
                    ForEach(ThresholdRule.holdChoices, id: \.self) { seconds in
                        Text(RuleText.holdLabel(seconds)).tag(seconds)
                    }
                }
            } header: {
                Text(isNew ? "New Rule" : "Rule")
            } footer: {
                if let message = limitMessage {
                    Text(message).foregroundStyle(.red)
                } else {
                    Text(RuleText.summary(draft))
                }
            }

            Section {
                Picker("Level", selection: $draft.severity) {
                    ForEach(ThresholdRule.Severity.allCases, id: \.self) { severity in
                        Text(RuleText.severityLabel(severity)).tag(severity)
                    }
                }
                Picker("Server", selection: $draft.serverID) {
                    Text("All servers").tag(UUID?.none)
                    ForEach(model.servers) { server in
                        Text(server.displayName).tag(UUID?.some(server.id))
                    }
                }
                Toggle("Rule is on", isOn: $draft.isEnabled)
            }
        }
        .formStyle(.grouped)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { onFinish(nil) }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button(isNew ? "Add Rule" : "Save") { onFinish(draft) }
                    .disabled(limitMessage != nil)
            }
        }
    }

    // MARK: Bindings

    private var kindBinding: Binding<RuleMetric.Kind> {
        Binding(
            get: { kind },
            set: { newKind in
                // A mount point is no sensor: the item does not carry over.
                draft.metric = RuleMetric(newKind, item: newKind == kind ? draft.metric.item : nil)
                if !limitEdited { draft.limit = RuleText.defaultLimit(newKind) }
            })
    }

    private var itemBinding: Binding<String> {
        Binding(
            get: { draft.metric.item ?? "" },
            set: { text in
                let trimmed = text.trimmingCharacters(in: .whitespaces)
                draft.metric = RuleMetric(kind, item: trimmed.isEmpty ? nil : trimmed)
            })
    }

    private var limitBinding: Binding<Double> {
        Binding(
            get: { draft.limit },
            set: { value in
                limitEdited = true
                draft.limit = value
            })
    }

    private var limitMessage: String? {
        let range = RuleText.limitRange(kind)
        guard draft.limit.isFinite, range.contains(draft.limit) else {
            let low = Format.number(range.lowerBound)
            let high = Format.number(range.upperBound)
            return String(localized: "The limit has to be between \(low) and \(high).")
        }
        return nil
    }
}
