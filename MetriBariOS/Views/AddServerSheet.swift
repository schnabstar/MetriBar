import MetriBarKit
import SwiftUI

struct AddServerSheet: View {
    var editingServerID: UUID? = nil
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ServerEditorView(
                mode: editingServerID.map { .edit($0) } ?? .add,
                onFinish: { dismiss() }
            )
            .navigationTitle(editingServerID == nil ? "Add Server" : "Edit Server")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if editingServerID != nil {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Done") { dismiss() }
                    }
                }
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
    }
}
