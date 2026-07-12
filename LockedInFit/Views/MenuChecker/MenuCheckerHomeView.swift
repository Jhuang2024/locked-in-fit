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
    /// The location "nearby" is based on. No default — nil means we simply don't
    /// know where the user is, so we prompt instead of inventing a location.
    private var origin: GeoPoint? {
        manualOrigin ?? location.coordinate
    }
    private var originLabel: String {
        if manualOrigin != nil { return manualCity.isEmpty ? "Custom location" : manualCity }
        if location.coordinate != nil { return "Your location" }
        return "No location set"
    }
    /// True when we have nothing to base "nearby" on and the user isn't searching.
    private var needsLocation: Bool {
        origin == nil && !worldwide && searchText.trimmingCharacters(in: .whitespaces).isEmpty
    }
    private var searchToken: String {
        // Round to ~100 m so GPS jitter doesn't re-fire the search every frame.
        let o = origin.map { "\(Int(($0.latitude * 1000).rounded())),\(Int(($0.longitude * 1000).rounded()))" } ?? "none"
        return "\(searchText.trimmingCharacters(in: .whitespaces).lowercased())|\(worldwide)|\(o)|\(filters.isActive)"
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
                    RestaurantMapView(restaurants: results, origin: origin, selected: $selectedOnMap)
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
        // Single lazy destination for the whole Menu Checker stack — restaurant
        // menus and item details pushed from here or from RestaurantMenuView all
        // resolve through this, so no eager destination views are ever built.
        .navigationDestination(for: MenuRoute.self) { route in
            switch route {
            case .menu(let restaurant, let routeOrigin):
                RestaurantMenuView(restaurant: restaurant, origin: routeOrigin)
            case .item(let item, let restaurantName):
                MenuItemDetailView(item: item, restaurantName: restaurantName, profile: profile)
            }
        }
        .task(id: searchToken) { await reload() }
        // Automatically use the device location on entry (prompts once if the
        // user hasn't decided yet; silently skips if they've denied it). The
        // resulting coordinate flows into searchToken and loads nearby.
        .task { await autoLocate() }
    }

    private func autoLocate() async {
        guard manualOrigin == nil, location.coordinate == nil, !location.isDenied else { return }
        _ = await location.requestLocation()
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
                // Just request; the coordinate change re-fires the search via
                // .task(id: searchToken) — no manual reload (that double-loaded).
                Task { manualOrigin = nil; _ = await location.requestLocation() }
            }
            .font(.caption.weight(.semibold))
            Button("Set city") { showManualLocation = true }
                .font(.caption.weight(.semibold))
        }
        .padding(12).cardBackground()
    }

    private var resultsHeader: some View {
        HStack {
            SectionLabel(text: searchText.isEmpty ? (worldwide ? "Worldwide" : (needsLocation ? "Discover" : "Nearby")) : "Results")
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
            if needsLocation {
                locationPrompt
            } else if results.isEmpty && !loading {
                EmptyStateView(systemImage: "fork.knife.circle",
                               title: "No restaurants",
                               message: searchText.isEmpty ? "Nothing here. Try worldwide search or a different city." : "Nothing matched “\(searchText)”. Try another term or turn on worldwide search.")
            }
            ForEach(results) { r in
                NavigationLink(value: MenuRoute.menu(r, origin)) {
                    RestaurantRowView(restaurant: r, origin: origin, imperial: settings?.usesImperial ?? false)
                }
                .buttonStyle(.plain)
            }
        }
    }

    /// Shown when there's no location and no search — we don't invent a place.
    private var locationPrompt: some View {
        VStack(spacing: 12) {
            Image(systemName: "location.magnifyingglass")
                .font(.system(size: 30)).foregroundStyle(.tint)
            Text("Where are you eating?")
                .font(.headline)
            Text(location.isDenied
                 ? "Location is off. Set a city or search worldwide to find restaurants."
                 : "Share your location for nearby restaurants, set a city, or search worldwide.")
                .font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center)
            HStack(spacing: 10) {
                if !location.isDenied {
                    Button {
                        Task { manualOrigin = nil; _ = await location.requestLocation() }
                    } label: { Label("Use my location", systemImage: "location.fill") }
                        .buttonStyle(.borderedProminent).controlSize(.small)
                }
                Button { showManualLocation = true } label: { Label("Set city", systemImage: "building.2") }
                    .buttonStyle(.bordered).controlSize(.small)
                Button { worldwide = true } label: { Label("Worldwide", systemImage: "globe") }
                    .buttonStyle(.bordered).controlSize(.small)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
        .padding(.horizontal, 12)
        .cardBackground()
    }

    // MARK: Saved / recent

    private var savedSection: some View {
        Group {
            if !savedRestaurants.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    SectionLabel(text: "Saved restaurants")
                    ForEach(savedRestaurants.prefix(5), id: \.persistentModelID) { record in
                        if let r = record.restaurant {
                            NavigationLink(value: MenuRoute.menu(r, origin)) {
                                RestaurantRowView(restaurant: r, origin: origin, imperial: settings?.usesImperial ?? false)
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
                            NavigationLink(value: MenuRoute.item(item, record.restaurantName)) {
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
                            NavigationLink(value: MenuRoute.menu(r, origin)) {
                                RestaurantRowView(restaurant: r, origin: origin, imperial: settings?.usesImperial ?? false)
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
        // Without a location and not searching, don't invent a place — prompt.
        if needsLocation {
            results = []
            errorText = nil
            return
        }
        loading = true
        errorText = nil
        defer { loading = false }
        let repo = MenuCheckerRepository(settings: settings)
        do {
            let trimmed = searchText.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty {
                if let origin, !worldwide {
                    results = try await repo.nearby(origin: origin, filters: filters)
                } else {
                    // Worldwide (or no origin): list everything, distance-sorted when known.
                    results = try await repo.search(RestaurantQuery(text: "", origin: origin, filters: filters, worldwide: true))
                }
            } else {
                let query = RestaurantQuery(text: trimmed, origin: origin, filters: filters, worldwide: worldwide)
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
