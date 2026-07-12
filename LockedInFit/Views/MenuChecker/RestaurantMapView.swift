import SwiftUI
import MapKit

/// Map view of restaurants. Tapping a marker selects it; the caller shows a card
/// and can push into the menu. Falls back gracefully when no coordinates exist.
struct RestaurantMapView: View {
    let restaurants: [Restaurant]
    let origin: GeoPoint?
    @Binding var selected: Restaurant?

    @State private var camera: MapCameraPosition = .automatic

    var body: some View {
        Map(position: $camera, selection: selectionBinding) {
            ForEach(restaurants) { r in
                Marker(r.name, systemImage: "fork.knife",
                       coordinate: CLLocationCoordinate2D(latitude: r.location.latitude, longitude: r.location.longitude))
                    .tint(markerColor(r))
                    .tag(r.id)
            }
            if let origin {
                Annotation("You", coordinate: CLLocationCoordinate2D(latitude: origin.latitude, longitude: origin.longitude)) {
                    Circle().fill(.blue).frame(width: 14, height: 14).overlay(Circle().stroke(.white, lineWidth: 2))
                }
            }
        }
        .frame(height: 320)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(alignment: .bottom) {
            if let selected {
                selectedCard(selected).padding(8)
            }
        }
        .onAppear { focus() }
    }

    private var selectionBinding: Binding<String?> {
        Binding(
            get: { selected?.id },
            set: { id in selected = restaurants.first { $0.id == id } })
    }

    private func markerColor(_ r: Restaurant) -> Color {
        guard let avg = r.averageMenuHealthScore else { return .gray }
        return MealScoreTier(avg).color
    }

    private func selectedCard(_ r: Restaurant) -> some View {
        NavigationLink(value: MenuRoute.menu(r, origin)) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(r.name).font(.subheadline.weight(.bold))
                    Text(r.primaryCuisine + " · " + r.priceLevel.glyphs).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "chevron.right").foregroundStyle(.secondary)
            }
            .padding(12)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
    }

    private func focus() {
        if let origin {
            camera = .region(MKCoordinateRegion(
                center: CLLocationCoordinate2D(latitude: origin.latitude, longitude: origin.longitude),
                span: MKCoordinateSpan(latitudeDelta: 0.08, longitudeDelta: 0.08)))
        }
    }
}
