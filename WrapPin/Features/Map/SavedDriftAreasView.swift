import SwiftUI

/// Lists saved drift boxes: tap to use one, swipe to delete, long-press to rename.
struct SavedDriftAreasView: View {
    @Environment(AppModel.self) private var appModel
    @Environment(\.dismiss) private var dismiss
    let currentAreaID: UUID?
    let onSelect: (DriftArea) -> Void

    @State private var renaming: DriftArea?
    @State private var newName = ""

    var body: some View {
        NavigationStack {
            Group {
                if appModel.savedDriftAreas.isEmpty {
                    ContentUnavailableView(
                        "No Saved Areas",
                        systemImage: "square.dashed",
                        description: Text("Draw a box on the map, then tap Save Area to keep it here.")
                    )
                } else {
                    List {
                        ForEach(appModel.savedDriftAreas) { area in
                            Button {
                                onSelect(area)
                                dismiss()
                            } label: {
                                row(for: area)
                            }
                            .buttonStyle(.pressable)
                            .contextMenu {
                                Button {
                                    newName = area.name
                                    renaming = area
                                } label: {
                                    Label("Rename", systemImage: "pencil")
                                }
                                Button(role: .destructive) {
                                    appModel.deleteDriftAreas(withIDs: [area.id])
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                            }
                        }
                        .onDelete { offsets in
                            let ids = Set(offsets.map { appModel.savedDriftAreas[$0].id })
                            withAnimation { appModel.deleteDriftAreas(withIDs: ids) }
                        }
                    }
                }
            }
            .navigationTitle("Saved Areas")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
                if !appModel.savedDriftAreas.isEmpty {
                    ToolbarItem(placement: .topBarLeading) {
                        EditButton()
                    }
                }
            }
            .alert(
                "Rename Area",
                isPresented: Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } })
            ) {
                TextField("Name", text: $newName)
                Button("Save") {
                    if let renaming {
                        appModel.renameDriftArea(id: renaming.id, to: newName)
                    }
                    renaming = nil
                }
                Button("Cancel", role: .cancel) { renaming = nil }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func row(for area: DriftArea) -> some View {
        HStack(spacing: 12) {
            Image(systemName: area.id == currentAreaID ? "checkmark.square.fill" : "square.dashed")
                .font(.title3)
                .foregroundStyle(.purple)
                .frame(width: 32)
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: area.name)
                    .font(.body.weight(.medium))
                    .foregroundStyle(.primary)
                Text(verbatim: Self.detail(for: area))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.tertiary)
        }
        .contentShape(Rectangle())
        .padding(.vertical, 4)
    }

    private static func detail(for area: DriftArea) -> String {
        func format(_ metres: Double) -> String {
            metres >= 1_000 ? String(format: "%.2f km", metres / 1_000) : String(format: "%.0f m", metres)
        }
        let size = "\(format(area.widthMetres)) × \(format(area.heightMetres))"
        let coordinate = String(format: "%.4f, %.4f", area.centerLatitude, area.centerLongitude)
        return "\(size) · \(coordinate)"
    }
}
