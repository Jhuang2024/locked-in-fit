import SwiftUI

/// Editable estimate review. The scan is NOT saved until the user confirms.
struct HealthScanDraftEditor: View {
    @Bindable var scan: HealthScan
    let providerUsed: String
    let onSave: () -> Void

    var body: some View {
        Form {
            if let image = scan.photoPath.flatMap(ImageStore.load) {
                Section {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                        .frame(maxHeight: 200)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .frame(maxWidth: .infinity)
                        .listRowBackground(Color.clear)
                }
            }

            Section {
                HStack {
                    ConfidenceBadge(confidence: scan.confidence)
                    Text("via \(providerUsed)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            HealthScanCoreSections(scan: scan)

            Section {
                Button {
                    onSave()
                } label: {
                    Label("Save Scan", systemImage: "checkmark.circle.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
            }
        }
    }
}
