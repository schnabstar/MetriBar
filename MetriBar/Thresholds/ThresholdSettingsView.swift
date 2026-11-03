import MetriBarKit
import SwiftUI

/// The rules the user set: list, templates and the editor sheet.
struct ThresholdSettingsView: View {
    @Environment(AppModel.self) private var model
    @State private var selection: UUID?
    @State private var sheet: RuleSheet?

    var body: some View {
        VStack(spacing: 0) {
            if model.rules.isEmpty {
                ContentUnavailableView {
                    Label("No Rules", systemImage: "slider.horizontal.3")
                } description: {
                    Text(
                        "Set your own limits, such as CPU above 90 % for 5 minutes. A rule that fires changes the status icon, and is reported by notifications if they are on."
                    )
                } actions: {
                    addMenu
                }
                .frame(maxHeight: .infinity)
            } else {
                List(selection: $selection) {
                    ForEach(model.rules) { rule in
                        RuleRow(rule: rule, serverName: serverName(rule))
                            .tag(rule.id)
                            .simultaneousGesture(
                                TapGesture(count: 2).onEnded { sheet = RuleSheet(rule: rule, isNew: false) }
                            )
                            .contextMenu {
                                Button("Edit…") { sheet = RuleSheet(rule: rule, isNew: false) }
                                Button("Duplicate") { selection = model.duplicateRule(rule.id) }
                                Divider()
                                Button("Delete", role: .destructive) { model.removeRule(rule.id) }
                            }
                    }
                }
                .onDeleteCommand(perform: deleteSelected)
                Text(
                    "Rules only change what MetriBar shows and reports; nothing changes on your servers. A rule that fires changes the status icon like a warning from Glances."
                )
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
            }
            Divider()
            bottomBar
        }
        .sheet(item: $sheet) { sheet in
            RuleEditorView(rule: sheet.rule, isNew: sheet.isNew) { saved in
                if let saved {
                    model.saveRule(saved)
                    selection = saved.id
                }
                self.sheet = nil
            }
            .presentationSizing(.form.fitted(horizontal: false, vertical: true))
        }
    }

    private var bottomBar: some View {
        HStack(spacing: 2) {
            if !model.rules.isEmpty {
                addMenu
                    .menuStyle(.borderlessButton)
                    .labelStyle(.iconOnly)
                    .menuIndicator(.hidden)
                    .frame(width: 24, height: 22)
                    .help("Add Rule")
                Button("Delete", systemImage: "minus", action: deleteSelected)
                    .frame(width: 24, height: 22)
                    .disabled(selection == nil)
                    .help("Delete Rule")
                Spacer()
                Button("Edit…") {
                    if let rule = model.rules.first(where: { $0.id == selection }) {
                        sheet = RuleSheet(rule: rule, isNew: false)
                    }
                }
                .disabled(selection == nil)
            } else {
                Spacer()
            }
        }
        .labelStyle(.iconOnly)
        .buttonStyle(.borderless)
        .padding(4)
        .padding(.horizontal, 4)
    }

    private var addMenu: some View {
        Menu {
            ForEach(RuleTemplate.all) { template in
                Button(template.title) { sheet = RuleSheet(rule: template.rule, isNew: true) }
            }
            Divider()
            Button("Custom Rule…") {
                sheet = RuleSheet(rule: ThresholdRule(metric: RuleMetric(.cpu), limit: 90), isNew: true)
            }
        } label: {
            Label("Add Rule", systemImage: "plus")
        }
    }

    private func deleteSelected() {
        guard let selection else { return }
        let index = model.rules.firstIndex { $0.id == selection }
        model.removeRule(selection)
        self.selection = index.flatMap { model.rules.indices.contains($0) ? model.rules[$0].id : model.rules.last?.id }
    }

    private func serverName(_ rule: ThresholdRule) -> String {
        guard let id = rule.serverID else { return String(localized: "All servers") }
        return model.server(id)?.displayName ?? String(localized: "Unknown server")
    }
}

private struct RuleSheet: Identifiable {
    let id = UUID()
    var rule: ThresholdRule
    var isNew: Bool
}

private struct RuleRow: View {
    @Environment(AppModel.self) private var model
    let rule: ThresholdRule
    let serverName: String

    var body: some View {
        HStack(spacing: 10) {
            Toggle("Enabled", isOn: enabled)
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.small)
            VStack(alignment: .leading, spacing: 2) {
                Text(RuleText.summary(rule))
                Text(
                    "\(Image(systemName: rule.severity.level.symbolName)) \(RuleText.severityLabel(rule.severity)) · \(serverName)"
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            .opacity(rule.isEnabled ? 1 : 0.5)
        }
        .padding(.vertical, 2)
    }

    private var enabled: Binding<Bool> {
        Binding(
            get: { rule.isEnabled },
            set: { value in
                var changed = rule
                changed.isEnabled = value
                model.saveRule(changed)
            })
    }
}
