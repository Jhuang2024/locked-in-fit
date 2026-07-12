import Foundation

// MARK: - Restaurant discovery (Apple Maps, sample fallback)

/// Prefers real Apple Maps results; falls back to the offline sample catalogue
/// when Maps returns nothing (offline, unsupported region, or no matches) so the
/// screen is never dead.
struct CompositeRestaurantProvider: RestaurantProvider {
    let name = "Apple Maps + sample"
    private let live = MapKitRestaurantProvider()
    private let sample = MockRestaurantProvider()

    func nearby(origin: GeoPoint, filters: RestaurantFilters) async throws -> [Restaurant] {
        if let results = try? await live.nearby(origin: origin, filters: filters), !results.isEmpty {
            return results
        }
        return (try? await sample.nearby(origin: origin, filters: filters)) ?? []
    }

    func search(_ query: RestaurantQuery) async throws -> [Restaurant] {
        if let results = try? await live.search(query), !results.isEmpty {
            return results
        }
        return (try? await sample.search(query)) ?? []
    }
}

// MARK: - Menu retrieval (Nutritionix → AI estimate → sample)

/// Tries official Nutritionix data first, then an AI-estimated menu (via the
/// OpenRouter/BazaarLink gateway), then the sample catalogue for sample
/// restaurants. Sources are tagged honestly (official vs estimated) so the UI
/// never presents an estimate as official.
struct CompositeMenuProvider: MenuProvider {
    let name = "Nutritionix + AI estimate"
    private let nutritionix = NutritionixMenuProvider()
    private let aiEstimator = AIMenuEstimator()
    private let sample = MockMenuProvider()

    func menu(for restaurant: Restaurant) async throws -> [MenuItem] {
        // Curated sample restaurants keep their sample menus.
        if restaurant.id.hasPrefix("sample:") {
            if let items = try? await sample.menu(for: restaurant), !items.isEmpty { return items }
        }
        // Official branded/restaurant nutrition (chains).
        if let items = try? await nutritionix.menu(for: restaurant), !items.isEmpty {
            return items
        }
        // AI-estimated menu, with nutrition computed by the local estimator.
        if KeychainService.hasAnyAIKey {
            if let items = try? await aiEstimator.menu(for: restaurant), !items.isEmpty {
                return items
            }
        }
        throw MenuCheckerError.menuUnavailable
    }
}

/// Builds an official menu from Nutritionix branded data. Returns an empty menu
/// (not an error) when Nutritionix isn't configured or the restaurant isn't a
/// recognized brand, so the composite can move on to estimation.
struct NutritionixMenuProvider: MenuProvider {
    let name = "Nutritionix"
    /// Cap detail lookups so a menu load stays responsive.
    var maxItems = 12

    func menu(for restaurant: Restaurant) async throws -> [MenuItem] {
        guard let client = NutritionixClient() else { return [] }
        let response = try await client.instantSearch(restaurant.name)
        let branded = response.branded ?? []
        guard !branded.isEmpty else { return [] }

        // Prefer items whose brand plausibly matches the restaurant name.
        let key = normalized(restaurant.name)
        let matches = branded.filter { b in
            let brand = normalized(b.brand_name ?? "")
            return !brand.isEmpty && (brand.contains(key) || key.contains(brand))
        }
        let chosen = Array((matches.isEmpty ? branded : matches).prefix(maxItems))

        var items: [MenuItem] = []
        for b in chosen {
            guard let nixID = b.nix_item_id, let food = try? await client.item(nixItemID: nixID) else { continue }
            items.append(makeItem(restaurant: restaurant, food: food))
        }
        return items
    }

    private func makeItem(restaurant: Restaurant, food: NutritionixFood) -> MenuItem {
        let name = (food.food_name ?? "Item").capitalized
        let itemID = restaurant.id + ":nx:" + SampleMenuData.slug(name)
        // Decompose the name so oil / modification controls still work, but the
        // official numbers are authoritative (officialNutrition, used verbatim).
        let est = MenuNutritionEstimator.estimate(name: name, description: "")
        var components = est.components
        for i in components.indices { components[i].id = "\(itemID)#\(i)" }
        let servingNote = [food.serving_qty.map { Formatters.trimmed($0) }, food.serving_unit]
            .compactMap { $0 }.joined(separator: " ")
        let description = [food.brand_name, servingNote.isEmpty ? nil : "Serving: \(servingNote)"]
            .compactMap { $0 }.joined(separator: " · ")
        return MenuItem(
            id: itemID,
            restaurantID: restaurant.id,
            name: name,
            itemDescription: description,
            category: MenuCategory.from(name),
            price: nil,
            currencyCode: restaurant.currencyCode,
            components: components,
            modifications: MenuModificationFactory.standard(for: components),
            dietaryTags: est.dietaryTags,
            defaultOilLevel: est.defaultOilLevel,
            sourceKind: .official,
            baseConfidence: .high,
            officialNutrition: food.resolvedNutrition,
            servingBasis: .perServing)
    }

    private func normalized(_ s: String) -> String {
        s.lowercased().filter { $0.isLetter || $0.isNumber }
    }
}

/// Asks the AI gateway (OpenRouter → BazaarLink) for a plausible menu for a
/// restaurant's cuisine, then computes each item's nutrition with the local
/// estimator — the model suggests dish names, not numbers, so nutrition stays
/// grounded. Everything it returns is flagged as an estimate.
struct AIMenuEstimator {
    struct Dish: Decodable { var name: String; var description: String?; var category: String? }

    func menu(for restaurant: Restaurant) async throws -> [MenuItem] {
        let cuisine = restaurant.primaryCuisine
        let prompt = """
        List 12 typical menu items for a \(cuisine) restaurant named "\(restaurant.name)". \
        Respond with ONLY a JSON array, no prose. Each element is an object with keys: \
        "name" (string), "description" (short string of the main ingredients and cooking method), \
        "category" (one of: breakfast, mains, sides, salads, soups, drinks, desserts). \
        Prefer common, recognizable dishes.
        """
        let body: [String: Any] = [
            "messages": [["role": "user", "content": prompt]],
            "temperature": 0.4,
            "max_tokens": 900
        ]
        let result = try await AIGatewayClient.send(body: body, modelOverride: nil)
        guard let dishes = parseDishes(result.content), !dishes.isEmpty else { return [] }

        return dishes.prefix(14).enumerated().map { index, dish in
            let itemID = restaurant.id + ":ai:" + SampleMenuData.slug(dish.name) + "\(index)"
            let est = MenuNutritionEstimator.estimate(name: dish.name, description: dish.description ?? "")
            var components = est.components
            for i in components.indices { components[i].id = "\(itemID)#\(i)" }
            return MenuItem(
                id: itemID,
                restaurantID: restaurant.id,
                name: dish.name,
                itemDescription: dish.description ?? "",
                category: dish.category.map { MenuCategory.from($0) } ?? .mains,
                price: nil,
                currencyCode: restaurant.currencyCode,
                components: components,
                modifications: MenuModificationFactory.standard(for: components),
                dietaryTags: est.dietaryTags,
                ingredientHints: est.uncertainTerms,
                defaultOilLevel: est.defaultOilLevel,
                // AI-suggested menu → never official; nutrition is a local estimate.
                sourceKind: .estimatedFromIngredients,
                baseConfidence: .low)
        }
    }

    private func parseDishes(_ content: String) -> [Dish]? {
        guard let start = content.firstIndex(of: "["),
              let end = content.lastIndex(of: "]"), start < end else { return nil }
        let json = String(content[start...end])
        guard let data = json.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode([Dish].self, from: data)
    }
}
