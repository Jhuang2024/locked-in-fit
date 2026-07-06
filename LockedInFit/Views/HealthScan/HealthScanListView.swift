import SwiftUI
import SwiftData

/// History of past product/food scans. Scanning here never logs a meal or affects daily totals.
struct HealthScanListView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \HealthScan.date, order: .reverse) private var scans: [HealthScan]
    @State private var showCapture = false

    var body: some View {
        List {
            if scans.isEmpty {
                EmptyStateView(systemImage: "text.magnifyingglass",
                               title: "No scans yet",
                               message: "Scan a product's label or nutrition facts to get a health score, satiety score, and a look at what's in it.")
            } else {
                ForEach(scans, id: \.persistentModelID) { scan in
                    NavigationLink(destination: HealthScanDetailView(scan: scan)) {
                        HealthScanRowView(scan: scan)
                    }
                }
                .onDelete { offsets in
                    for index in offsets {
                        ImageStore.delete(scans[index].photoPath)
                        context.delete(scans[index])
                    }
                }
            }
        }
        .navigationTitle("Health Scans")
        .toolbar {
            Button { showCapture = true } label: { Image(systemName: "camera") }
        }
        .sheet(isPresented: $showCapture) { HealthScanCaptureView() }
    }
}
