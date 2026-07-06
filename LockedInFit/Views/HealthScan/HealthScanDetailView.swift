import SwiftUI
import SwiftData

/// View and edit a saved health scan.
struct HealthScanDetailView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Bindable var scan: HealthScan
    @State private var confirmDelete = false

    var body: some View {
        Form {
            if let image = ImageStore.load(scan.photoPath) {
                Section {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                        .frame(maxHeight: 240)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .frame(maxWidth: .infinity)
                        .listRowBackground(Color.clear)
                }
            }

            Section {
                ConfidenceBadge(confidence: scan.confidence)
            }

            HealthScanCoreSections(scan: scan)

            Section {
                Button("Delete Scan", role: .destructive) { confirmDelete = true }
            }
        }
        .navigationTitle(scan.productName.isEmpty ? "Health Scan" : scan.productName)
        .navigationBarTitleDisplayMode(.inline)
        .keyboardDoneToolbar()
        .confirmationDialog("Delete this scan?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Delete", role: .destructive) {
                ImageStore.delete(scan.photoPath)
                context.delete(scan)
                dismiss()
            }
        }
    }
}
