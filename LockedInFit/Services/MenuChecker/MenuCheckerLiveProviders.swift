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

// MARK: - Menu retrieval (sample → AI estimate)

/// Uses the sample catalogue for sample restaurants, otherwise an AI-estimated
/// menu (via the OpenRouter/BazaarLink gateway; the model suggests dish names,
/// the on-device estimator computes nutrition). Everything is tagged honestly
/// by source — nothing is presented as official unless it came from the sample
/// chains.
struct CompositeMenuProvider: MenuProvider {
    let name = "Sample + AI estimate"
    private let aiEstimator = AIMenuEstimator()
    private let sample = MockMenuProvider()

    func menu(for restaurant: Restaurant) async throws -> [MenuItem] {
        // Curated sample restaurants keep their sample menus.
        if restaurant.id.hasPrefix("sample:") {
            if let items = try? await sample.menu(for: restaurant), !items.isEmpty { return items }
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
