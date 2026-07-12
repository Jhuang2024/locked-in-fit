import SwiftUI
import CoreLocation

/// A restaurant row in discovery lists: name, cuisine, distance, price, open
/// status, average menu health, and whether official nutrition is available.
struct RestaurantRowView: View {
    let restaurant: Restaurant
    var origin: GeoPoint?
    var imperial: Bool

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(LinearGradient(colors: [.orange.opacity(0.25), .pink.opacity(0.16)], startPoint: .top, endPoint: .bottom))
                Image(systemName: "fork.knife").foregroundStyle(.secondary)
            }
            .frame(width: 54, height: 54)

            VStack(alignment: .leading, spacing: 3) {
                Text(restaurant.name).font(.subheadline.weight(.bold))
                Text(restaurant.cuisines.joined(separator: " · ") + "  " + restaurant.priceLevel.glyphs)
                    .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                HStack(spacing: 8) {
                    if let dist = MenuFormat.distance(restaurant.distanceMeters(from: origin), imperial: imperial) {
                        Label(dist, systemImage: "location").font(.caption2).foregroundStyle(.secondary)
                    }
                    Text(restaurant.city).font(.caption2).foregroundStyle(.secondary)
                    if let open = restaurant.isOpen() {
                        Text(open ? "Open" : "Closed").font(.caption2.weight(.semibold)).foregroundStyle(open ? .green : .red)
                    }
                }
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 4) {
                if let avg = restaurant.averageMenuHealthScore {
                    HealthChip(score: avg)
                }
                if restaurant.hasOfficialNutrition {
                    Label("Official", systemImage: "checkmark.seal.fill").font(.system(size: 9, weight: .semibold)).foregroundStyle(.green)
                }
            }
        }
        .padding(12).cardBackground()
    }
}

/// The full discovery filter sheet.
struct MenuFilterSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var filters: RestaurantFilters
    let availableCuisines: [String]

    var body: some View {
        NavigationStack {
            Form {
                Section("Distance") {
                    Toggle("Limit distance", isOn: Binding(
                        get: { filters.maxDistanceMeters != nil },
                        set: { filters.maxDistanceMeters = $0 ? 5000 : nil }))
                    if let dist = filters.maxDistanceMeters {
                        VStack(alignment: .leading) {
                            Text("Within \(Int(dist / 1000)) km")
                            Slider(value: Binding(get: { dist }, set: { filters.maxDistanceMeters = $0 }), in: 500...50000, step: 500)
                        }
                    }
                }
                Section("Cuisine") {
                    ForEach(availableCuisines, id: \.self) { cuisine in
                        toggleRow(cuisine, on: filters.cuisines.contains(cuisine)) {
                            if filters.cuisines.contains(cuisine) { filters.cuisines.remove(cuisine) } else { filters.cuisines.insert(cuisine) }
                        }
                    }
                }
                Section("Availability & price") {
                    Toggle("Open now", isOn: $filters.openNow)
                    Toggle("Official nutrition only", isOn: $filters.officialNutritionOnly)
                    Picker("Max price", selection: Binding(
                        get: { filters.maxPrice ?? .luxury },
                        set: { filters.maxPrice = $0 })) {
                        Text("Any").tag(PriceLevel.luxury)
                        Text("$").tag(PriceLevel.budget)
                        Text("$$").tag(PriceLevel.moderate)
                        Text("$$$").tag(PriceLevel.premium)
                    }
                }
                Section("Nutrition targets") {
                    macroField("Max calories", value: $filters.maxCalories, unit: "kcal")
                    macroField("Min protein", value: $filters.minProtein, unit: "g")
                    scoreSlider("Min Health Score", value: $filters.minHealthScore)
                    scoreSlider("Min Satiety Score", value: $filters.minSatietyScore)
                }
                Section("Dietary") {
                    ForEach(DietaryTag.allCases) { tag in
                        toggleRow(tag.label, on: filters.dietary.contains(tag)) {
                            if filters.dietary.contains(tag) { filters.dietary.remove(tag) } else { filters.dietary.insert(tag) }
                        }
                    }
                }
                Section {
                    Button("Reset filters", role: .destructive) { filters = .none }
                }
            }
            .navigationTitle("Filters")
            .navigationBarTitleDisplayMode(.inline)
            .keyboardDoneToolbar()
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
    }

    private func toggleRow(_ label: String, on: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                Text(label).foregroundStyle(.primary)
                Spacer()
                if on { Image(systemName: "checkmark").foregroundStyle(.tint) }
            }
        }
    }

    private func macroField(_ label: String, value: Binding<Double?>, unit: String) -> some View {
        // Bridge the optional to a plain Double (0 == no limit) so the numeric
        // TextField's FormatStyle is happy.
        let proxy = Binding<Double>(
            get: { value.wrappedValue ?? 0 },
            set: { value.wrappedValue = $0 <= 0 ? nil : $0 })
        return HStack {
            Text(label)
            Spacer()
            TextField("Any", value: proxy, format: .number)
                .keyboardType(.decimalPad).multilineTextAlignment(.trailing).frame(width: 80)
            Text(unit).font(.caption).foregroundStyle(.secondary)
        }
    }

    private func scoreSlider(_ label: String, value: Binding<Double?>) -> some View {
        VStack(alignment: .leading) {
            HStack {
                Text(label)
                Spacer()
                Text(value.wrappedValue.map { "\(Int($0))+" } ?? "Any").foregroundStyle(.secondary)
            }
            Slider(value: Binding(get: { value.wrappedValue ?? 0 }, set: { value.wrappedValue = $0 == 0 ? nil : $0 }),
                   in: 0...100, step: 5)
        }
    }
}

/// Lets the user browse another city without changing their device location.
struct ManualLocationSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var city: String
    let onResolved: (GeoPoint?) -> Void

    @State private var input = ""
    @State private var resolving = false
    @State private var error: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("City, e.g. London or Tokyo", text: $input)
                        .autocorrectionDisabled()
                } footer: {
                    Text("Browse restaurants in another city. This doesn't change your device location.")
                }
                if let error { Text(error).font(.caption).foregroundStyle(.red) }
                Section {
                    ForEach(CityLookup.suggestions, id: \.name) { suggestion in
                        Button(suggestion.name) {
                            city = suggestion.name
                            onResolved(suggestion.point)
                            dismiss()
                        }
                    }
                }
            }
            .navigationTitle("Manual Location")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(resolving ? "…" : "Set") { resolve() }.disabled(input.isEmpty || resolving)
                }
            }
            .onAppear { input = city }
        }
    }

    private func resolve() {
        if let match = CityLookup.match(input) {
            city = match.name; onResolved(match.point); dismiss(); return
        }
        resolving = true
        error = nil
        CLGeocoder().geocodeAddressString(input) { placemarks, _ in
            resolving = false
            if let loc = placemarks?.first?.location {
                city = input
                onResolved(GeoPoint(latitude: loc.coordinate.latitude, longitude: loc.coordinate.longitude))
                dismiss()
            } else {
                error = "Couldn't find that place. Try a nearby major city."
            }
        }
    }
}

/// Known-city fallback so manual location works offline for our sample cities.
enum CityLookup {
    struct City { var name: String; var point: GeoPoint }
    static let suggestions: [City] = [
        City(name: "New York", point: GeoPoint(latitude: 40.7549, longitude: -73.9880)),
        City(name: "London", point: GeoPoint(latitude: 51.5155, longitude: -0.1320)),
        City(name: "Tokyo", point: GeoPoint(latitude: 35.6717, longitude: 139.7640)),
        City(name: "San Francisco", point: GeoPoint(latitude: 37.7946, longitude: -122.4066)),
        City(name: "Los Angeles", point: GeoPoint(latitude: 34.0780, longitude: -118.2606)),
        City(name: "Paris", point: GeoPoint(latitude: 48.8558, longitude: 2.3588)),
        City(name: "Sydney", point: GeoPoint(latitude: -33.8690, longitude: 151.2050)),
        City(name: "Bangkok", point: GeoPoint(latitude: 13.7380, longitude: 100.5608)),
        City(name: "Berlin", point: GeoPoint(latitude: 52.5290, longitude: 13.4010)),
    ]
    static func match(_ text: String) -> City? {
        let l = text.lowercased()
        return suggestions.first { $0.name.lowercased() == l || l.contains($0.name.lowercased()) }
    }
}
