import SwiftUI
import SwiftData

/// A restaurant's menu: header (name, address, distance, cuisine, hours, source),
/// in-menu search, sort/filter, and category sections of scored item cards.
struct RestaurantMenuView: View {
    @Environment(\.modelContext) private var context
    @Query private var settingsList: [UserSettings]
    @Query(filter: #Predicate<Goal> { $0.active }) private var goals: [Goal]
    @Query(sort: \MealLog.date, order: .reverse) private var meals: [MealLog]
    @Query private var cartLines: [CartLine]
    @Query private var savedRestaurants: [SavedRestaurantRecord]

    let restaurant: Restaurant
    var origin: GeoPoint?

    @State private var items: [MenuItem] = []
    @State private var loadState: LoadState = .loading
    @State private var fetchedAt: Date?
    @State private var isStale = false
    @State private var search = ""
    @State private var sort: MenuSort = .recommended
    @State private var dietaryFilter: Set<DietaryTag> = []
    @State private var officialOnly = false
    @State private var showCart = false
    @State private var dishDescription = ""
    @State private var estimatingDish = false
    @State private var dishError: String?
    @State private var describedDish: EstimatedDish?

    enum LoadState: Equatable { case loading, loaded, failed(String) }
    enum MenuSort: String, CaseIterable, Identifiable {
        case recommended, calories, protein, price, name
        var id: String { rawValue }
        var label: String {
            switch self {
            case .recommended: return "Health"
            case .calories: return "Calories"
            case .protein: return "Protein"
            case .price: return "Price"
            case .name: return "Name"
            }
        }
    }

    private var settings: UserSettings? { settingsList.first }
    private var profile: ScoringProfile {
        ScoringProfileBuilder.make(settings: settings, goal: goals.first, meals: meals)
    }
    private var isSaved: Bool { savedRestaurants.contains { $0.restaurantID == restaurant.id } }

    var body: some View {
        #if DEBUG
        let _ = Self._printChanges()
        #endif
        return ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                headerCard
                describeCard
                switch loadState {
                case .loading:
                    ProgressView("Loading menu…").frame(maxWidth: .infinity).padding(.vertical, 40)
                case .failed(let message):
                    EmptyStateView(systemImage: "menucard", title: "Menu unavailable", message: message)
                        .padding(.top, 20)
                case .loaded:
                    controls
                    menuSections
                }
            }
            .padding(16)
            .padding(.bottom, 80)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle(restaurant.name)
        .navigationBarTitleDisplayMode(.inline)
        .keyboardDoneToolbar()
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { toggleSaved() } label: {
                    Image(systemName: isSaved ? "bookmark.fill" : "bookmark")
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button { showCart = true } label: {
                    CartToolbarButton(count: cartLines.count)
                }
            }
        }
        .sheet(isPresented: $showCart) { MealCartView() }
        .task { await loadMenu() }
        .onAppear { recordRecent() }
    }

    // MARK: Describe a dish

    private var describeCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Describe a dish", systemImage: "text.bubble")
                .font(.subheadline.weight(.semibold))
            Text("Type anything on the menu and AI estimates its calories, macros, and scores for \(restaurant.name).")
                .font(.caption).foregroundStyle(.secondary)
            TextField("e.g. large pepperoni pizza slice, or chicken pad thai", text: $dishDescription, axis: .vertical)
                .lineLimit(1...3)
                .textFieldStyle(.roundedBorder)
            Button {
                estimateDish()
            } label: {
                if estimatingDish {
                    HStack(spacing: 6) { ProgressView().controlSize(.small); Text("Estimating…") }
                } else {
                    Label("Estimate this dish", systemImage: "wand.and.stars")
                }
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
            .disabled(estimatingDish || dishDescription.trimmingCharacters(in: .whitespaces).isEmpty)
            if !KeychainService.hasAnyAIKey {
                Text("Add an OpenRouter or BazaarLink key in Settings → AI Analysis to use this.")
                    .font(.caption2).foregroundStyle(.orange)
            }
            if let dishError {
                Text(dishError).font(.caption).foregroundStyle(.red)
            }
        }
        .padding(16).frame(maxWidth: .infinity, alignment: .leading).cardBackground()
        .sheet(item: $describedDish) { dish in
            NavigationStack {
                DescribedDishView(dish: dish, restaurant: restaurant)
            }
        }
    }

    private func estimateDish() {
        let text = dishDescription.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        estimatingDish = true
        dishError = nil
        Task {
            defer { estimatingDish = false }
            do {
                let dish = try await MenuDishEstimator.estimate(restaurant: restaurant, description: text, settings: settings)
                describedDish = dish
                dishDescription = ""
            } catch {
                dishError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            }
        }
    }

    // MARK: Header

    private var headerCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text(restaurant.primaryCuisine).font(.caption.weight(.semibold))
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .background(Color.accentColor.opacity(0.14), in: Capsule())
                Text(restaurant.priceLevel.glyphs).font(.caption.weight(.bold)).foregroundStyle(.secondary)
                if let open = restaurant.isOpen() {
                    Text(open ? "Open now" : "Closed")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(open ? .green : .red)
                }
                Spacer()
            }
            Text(restaurant.address + ", " + restaurant.city).font(.subheadline).foregroundStyle(.secondary)
            HStack(spacing: 14) {
                if let dist = MenuFormat.distance(restaurant.distanceMeters(from: origin), imperial: settings?.usesImperial ?? false) {
                    Label(dist, systemImage: "location").font(.caption).foregroundStyle(.secondary)
                }
                Label(restaurant.hours.todayString(for: .now), systemImage: "clock").font(.caption).foregroundStyle(.secondary)
            }
            HStack(spacing: 8) {
                NutritionSourceBadge(kind: restaurant.hasOfficialNutrition ? .official : .estimatedFromIngredients, compact: true)
                if let fetchedAt {
                    Text("Menu updated \(CachedResult(value: 0, fetchedAt: fetchedAt).ageDescription)")
                        .font(.caption2)
                        .foregroundStyle(isStale ? AnyShapeStyle(.orange) : AnyShapeStyle(.tertiary))
                }
            }
        }
        .padding(16).frame(maxWidth: .infinity, alignment: .leading).cardBackground()
    }

    // MARK: Controls

    private var controls: some View {
        VStack(spacing: 10) {
            HStack {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("Search this menu", text: $search)
            }
            .padding(10).background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 10))

            HStack {
                Menu {
                    Picker("Sort", selection: $sort) {
                        ForEach(MenuSort.allCases) { Text($0.label).tag($0) }
                    }
                } label: {
                    Label("Sort: \(sort.label)", systemImage: "arrow.up.arrow.down").font(.caption.weight(.semibold))
                }
                Spacer()
                Toggle(isOn: $officialOnly) { Text("Official only").font(.caption) }
                    .toggleStyle(.button).controlSize(.small)
                Menu {
                    ForEach([DietaryTag.vegetarian, .vegan, .glutenFree], id: \.self) { tag in
                        Button {
                            if dietaryFilter.contains(tag) { dietaryFilter.remove(tag) } else { dietaryFilter.insert(tag) }
                        } label: {
                            Label(tag.label, systemImage: dietaryFilter.contains(tag) ? "checkmark" : tag.systemImage)
                        }
                    }
                } label: {
                    Image(systemName: "line.3.horizontal.decrease.circle\(dietaryFilter.isEmpty ? "" : ".fill")")
                }
            }
        }
    }

    // MARK: Sections

    private var filteredItems: [MenuItem] {
        var result = items
        if !search.isEmpty {
            result = result.filter { $0.name.localizedCaseInsensitiveContains(search) || $0.itemDescription.localizedCaseInsensitiveContains(search) }
        }
        if officialOnly { result = result.filter { $0.sourceKind == .official } }
        if !dietaryFilter.isEmpty {
            result = result.filter { dietaryFilter.isSubset(of: Set($0.dietaryTags)) }
        }
        return result
    }

    private func sorted(_ list: [MenuItem]) -> [MenuItem] {
        switch sort {
        case .name: return list.sorted { $0.name < $1.name }
        case .price: return list.sorted { ($0.price ?? .greatestFiniteMagnitude) < ($1.price ?? .greatestFiniteMagnitude) }
        default:
            let scored = list.map { ($0, MenuItemResolver.resolve(item: $0, profile: profile)) }
            switch sort {
            case .recommended: return scored.sorted { $0.1.healthScore > $1.1.healthScore }.map(\.0)
            case .calories: return scored.sorted { $0.1.perUnit.calories < $1.1.perUnit.calories }.map(\.0)
            case .protein: return scored.sorted { $0.1.perUnit.protein > $1.1.perUnit.protein }.map(\.0)
            default: return list
            }
        }
    }

    private var menuSections: some View {
        let visible = filteredItems
        return VStack(alignment: .leading, spacing: 16) {
            if visible.isEmpty {
                EmptyStateView(systemImage: "magnifyingglass", title: "No matches", message: "Try a different search or clear the filters.")
            }
            ForEach(MenuCategory.allCases) { category in
                let categoryItems = sorted(visible.filter { $0.category == category })
                if !categoryItems.isEmpty {
                    VStack(alignment: .leading, spacing: 10) {
                        Label(category.label, systemImage: category.systemImage)
                            .font(.headline)
                        ForEach(categoryItems) { item in
                            NavigationLink(value: MenuRoute.item(item, restaurant.name)) {
                                MenuItemCardView(item: item, restaurantName: restaurant.name, profile: profile)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
    }

    // MARK: Data

    private func loadMenu() async {
        loadState = .loading
        let repo = MenuCheckerRepository(settings: settings)
        do {
            let result = try await repo.menu(for: restaurant)
            // Unique ids only — duplicate ids in the category ForEach would make
            // SwiftUI thrash the list.
            var seen = Set<String>()
            items = result.items.filter { seen.insert($0.id).inserted }
            fetchedAt = result.fetchedAt
            isStale = result.stale
            loadState = .loaded
        } catch {
            let message = (error as? MenuCheckerError)?.errorDescription ?? error.localizedDescription
            loadState = .failed(message)
        }
    }

    private func recordRecent() {
        // Keep a small rolling window of recently viewed restaurants.
        MenuCheckerLibrary.recordRecent(restaurant, context: context)
    }

    private func toggleSaved() {
        if let existing = savedRestaurants.first(where: { $0.restaurantID == restaurant.id }) {
            context.delete(existing)
        } else {
            context.insert(SavedRestaurantRecord(restaurant: restaurant))
        }
        try? context.save()
    }
}

/// Toolbar cart button with an item-count badge.
struct CartToolbarButton: View {
    let count: Int
    var body: some View {
        ZStack(alignment: .topTrailing) {
            Image(systemName: "cart")
            if count > 0 {
                Text("\(count)")
                    .font(.system(size: 10, weight: .bold)).foregroundStyle(.white)
                    .padding(4).background(Color.red, in: Circle())
                    .offset(x: 10, y: -10)
            }
        }
    }
}
