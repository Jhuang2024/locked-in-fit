import SwiftUI
import SwiftData
import CoreLocation

/// Menu Checker entry screen: discover nearby restaurants, search worldwide,
/// browse a manual location, apply filters, and jump back into saved / recent
/// restaurants. Location permission is requested only when the user taps
/// "Use my location"; everything works via manual search otherwise.
struct MenuCheckerHomeView: View {
    @Environment(\.modelContext) private var context
    @Query private var settingsList: [UserSettings]
    @Query(filter: #Predicate<Goal> { $0.active }) private var goals: [Goal]
    @Query(sort: \MealLog.date, order: .reverse) private var meals: [MealLog]
    @Query private var cartLines: [CartLine]
    @Query(sort: \SavedRestaurantRecord.savedAt, order: .reverse) private var savedRestaurants: [SavedRestaurantRecord]
    @Query(sort: \SavedMenuItemRecord.savedAt, order: .reverse) private var savedItems: [SavedMenuItemRecord]
    @Query(sort: \RecentRestaurantRecord.viewedAt, order: .reverse) private var recents: [RecentRestaurantRecord]

    @ObservedObject private var location = LocationService.shared

    @State private var searchText = ""
    @State private var worldwide = false
    @State private var manualCity = ""
    @State private var manualOrigin: GeoPoint?
    @State private var filters = RestaurantFilters.none
    @State private var results: [Restaurant] = []
    @State private var loading = false
    @State private var errorText: String?
    @State private var viewMode: ViewMode = .list
    @State private var selectedOnMap: Restaurant?
    @State private var showFilters = false
    @State private var showCart = false
    @State private var showManualLocation = false

    enum ViewMode: String, CaseIterable { case list, map }

    private var settings: UserSettings? { settingsList.first }
    private var profile: ScoringProfile {
        ScoringProfileBuilder.make(settings: settings, goal: goals.first, meals: meals)
    }
    private var effectiveOrigin: GeoPoint {
        manualOrigin ?? location.coordinate ?? SampleMenuData.defaultOrigin
    }
    private var originLabel: String {
        if manualOrigin != nil { return manualCity.isEmpty ? "Custom location" : manualCity }
        if location.coordinate != nil { return "Your location" }
        return "New York (sample)"
    }
    private var searchToken: String {
        "\(searchText)|\(worldwide)|\(effectiveOrigin.latitude),\(effectiveOrigin.longitude)|\(filters.isActive)"
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                searchBar
                locationRow
                if let errorText {
                    Label(errorText, systemImage: "wifi.exclamationmark")
                        .font(.caption).foregroundStyle(.orange)
                }
                resultsHeader
                if viewMode == .map {
                    RestaurantMapView(restaurants: results, origin: effectiveOrigin, selected: $selectedOnMap)
                } else {
                    resultsList
                }
                if searchText.isEmpty {
                    savedSection
                    savedItemsSection
                    recentSection
                }
            }
            .padding(16)
            .padding(.bottom, 40)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("Menu Checker")
        .keyboardDoneToolbar()
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { showFilters = true } label: {
                    Image(systemName: filters.isActive ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle")
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button { showCart = true } label: { CartToolbarButton(count: cartLines.count) }
            }
        }
        .sheet(isPresented: $showFilters) {
            MenuFilterSheet(filters: $filters, availableCuisines: cuisines)
        }
        .sheet(isPresented: $showCart) { MealCartView() }
        .sheet(isPresented: $showManualLocation) {
            ManualLocationSheet(city: $manualCity) { resolved in
                manualOrigin = resolved
                worldwide = false
            }
        }
        .task(id: searchToken) { await reload() }
    }

    // MARK: Search + location

    private var searchBar: some View {
        VStack(spacing: 10) {
            HStack {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("Search restaurants, cuisine, dish, city…", text: $searchText)
                    .autocorrectionDisabled()
                if !searchText.isEmpty {
                    Button { searchText = "" } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary) }
                }
            }
            .padding(12)
            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12))
            Toggle(isOn: $worldwide) {
                Label("Search worldwide", systemImage: "globe").font(.caption)
            }
            .font(.caption)
        }
    }

    private var locationRow: some View {
        HStack(spacing: 10) {
            Image(systemName: "location.circle.fill").foregroundStyle(.tint)
            VStack(alignment: .leading, spacing: 1) {
                Text(originLabel).font(.subheadline.weight(.semibold))
                Text(location.isDenied ? "Location off — using search & manual city"
                     : "Nearby is based on this location").font(.caption2).foregroundStyle(.secondary)
            }
            Spacer()
            Button("Use location") {
                Task { manualOrigin = nil; _ = await location.requestLocation(); await reload() }
            }
            .font(.caption.weight(.semibold))
            Button("Set city") { showManualLocation = true }
                .font(.caption.weight(.semibold))
        }
        .padding(12).cardBackground()
    }

    private var resultsHeader: some View {
        HStack {
            SectionLabel(text: searchText.isEmpty ? (worldwide ? "Worldwide" : "Nearby") : "Results")
            if loading { ProgressView().controlSize(.mini) }
            Spacer()
            Picker("View", selection: $viewMode) {
                Image(systemName: "list.bullet").tag(ViewMode.list)
                Image(systemName: "map").tag(ViewMode.map)
            }
            .pickerStyle(.segmented).frame(width: 96)
        }
    }

    private var resultsList: some View {
        LazyVStack(spacing: 12) {
            if results.isEmpty && !loading {
                EmptyStateView(systemImage: "fork.knife.circle",
                               title: "No restaurants",
                               message: searchText.isEmpty ? "No restaurants near this location. Try worldwide search or a manual city." : "Nothing matched “\(searchText)”. Try another term or turn on worldwide search.")
            }
            ForEach(results) { r in
                NavigationLink { RestaurantMenuView(restaurant: r, origin: effectiveOrigin) } label: {
                    RestaurantRowView(restaurant: r, origin: effectiveOrigin, imperial: settings?.usesImperial ?? false)
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: Saved / recent

    private var savedSection: some View {
        Group {
            if !savedRestaurants.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    SectionLabel(text: "Saved restaurants")
                    ForEach(savedRestaurants.prefix(5), id: \.persistentModelID) { record in
                        if let r = record.restaurant {
                            NavigationLink { RestaurantMenuView(restaurant: r, origin: effectiveOrigin) } label: {
                                RestaurantRowView(restaurant: r, origin: effectiveOrigin, imperial: settings?.usesImperial ?? false)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
    }

    private var savedItemsSection: some View {
        Group {
            if !savedItems.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    SectionLabel(text: "Saved items")
                    ForEach(savedItems.prefix(6), id: \.persistentModelID) { record in
                        if let item = record.item {
                            NavigationLink {
                                MenuItemDetailView(item: item, restaurantName: record.restaurantName, profile: profile)
                            } label: {
                                HStack {
                                    Image(systemName: "bookmark.fill").foregroundStyle(.tint)
                                    VStack(alignment: .leading) {
                                        Text(item.name).font(.subheadline.weight(.semibold))
                                        Text(record.restaurantName).font(.caption).foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    Image(systemName: "chevron.right").font(.caption).foregroundStyle(.secondary)
                                }
                                .padding(12).cardBackground()
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
    }

    private var recentSection: some View {
        Group {
            if !recents.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    SectionLabel(text: "Recently viewed")
                    ForEach(recents.prefix(6), id: \.persistentModelID) { record in
                        if let r = record.restaurant {
                            NavigationLink { RestaurantMenuView(restaurant: r, origin: effectiveOrigin) } label: {
                                RestaurantRowView(restaurant: r, origin: effectiveOrigin, imperial: settings?.usesImperial ?? false)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
    }

    private var cuisines: [String] {
        Array(Set(SampleMenuData.restaurants.flatMap(\.cuisines))).sorted()
    }

    // MARK: Loading

    private func reload() async {
        loading = true
        errorText = nil
        defer { loading = false }
        let repo = MenuCheckerRepository(settings: settings)
        do {
            if searchText.trimmingCharacters(in: .whitespaces).isEmpty {
                if worldwide {
                    results = try await repo.search(RestaurantQuery(text: "", origin: effectiveOrigin, filters: filters, worldwide: true))
                } else {
                    results = try await repo.nearby(origin: effectiveOrigin, filters: filters)
                }
            } else {
                let query = RestaurantQuery(text: searchText, origin: effectiveOrigin, filters: filters, worldwide: worldwide)
                results = try await repo.search(query)
            }
        } catch is CancellationError {
            // Superseded by a newer search (the search token changed, e.g. the
            // location just resolved). Not a real failure — keep current results.
        } catch let urlError as URLError where urlError.code == .cancelled {
            // Same as above, for providers that surface cancellation as URLError.
        } catch {
            errorText = (error as? MenuCheckerError)?.errorDescription ?? error.localizedDescription
            results = []
        }
    }
}
