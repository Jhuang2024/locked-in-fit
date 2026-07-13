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

// MARK: - Menu retrieval (sample → AI real-menu lookup)

/// Uses the sample catalogue for sample restaurants, otherwise an AI menu lookup
/// (via the OpenRouter/BazaarLink gateway) that tries to reconstruct THIS
/// restaurant's actual menu and only falls back to a generic cuisine menu when
/// the model doesn't recognise the place. Nutrition is always computed by the
/// on-device estimator, so numbers stay grounded and nothing is presented as
/// official. The repository caches the result (in memory and on disk) so each
/// restaurant costs at most one AI call per TTL.
struct CompositeMenuProvider: MenuProvider {
    let name = "Sample + AI real-menu lookup"
    private let aiEstimator = AIMenuEstimator()
    private let sample = MockMenuProvider()

    func menu(for restaurant: Restaurant) async throws -> [MenuItem] {
        // Curated sample restaurants keep their sample menus.
        if restaurant.id.hasPrefix("sample:") {
            if let items = try? await sample.menu(for: restaurant), !items.isEmpty { return items }
        }
        // AI menu lookup (real menu when the model knows it, generic otherwise),
        // with nutrition computed by the local estimator.
        if KeychainService.hasAnyAIKey {
            if let items = try? await aiEstimator.menu(for: restaurant), !items.isEmpty {
                return items
            }
        }
        throw MenuCheckerError.menuUnavailable
    }
}

/// Asks the AI gateway (OpenRouter → BazaarLink) for THIS specific restaurant's
/// real menu — identified by name, city, address, and cuisine — in a single
/// call, then computes each item's nutrition with the local estimator (the model
/// supplies dish names + ingredient/prep descriptions, never numbers, so
/// nutrition stays grounded). The model self-reports whether the menu is the
/// restaurant's actual one or a generic stand-in; real menus are given medium
/// confidence, generic fallbacks low. One call regardless of outcome.
struct AIMenuEstimator {
    struct Dish: Decodable { var name: String; var description: String?; var category: String? }
    /// `{"real": true|false, "items": [...]}` — `real` distinguishes this
    /// restaurant's actual menu from a generic cuisine stand-in.
    struct MenuResponse: Decodable { var real: Bool?; var items: [Dish] }

    func menu(for restaurant: Restaurant) async throws -> [MenuItem] {
        let cuisine = restaurant.primaryCuisine
        let locationParts = [restaurant.address, restaurant.city, restaurant.country]
            .filter { !$0.isEmpty }
            .joined(separator: ", ")
        let prompt = """
        You are a restaurant menu database. Reconstruct the menu for this specific restaurant:
        Name: "\(restaurant.name)"
        Location: \(locationParts.isEmpty ? "unknown" : locationParts)
        Cuisine: \(cuisine)

        If you actually know THIS specific restaurant (a chain or a well-known place), \
        list its real, recognizable menu items exactly as it serves them. If you do NOT \
        know this exact restaurant, instead list the typical menu of a \(cuisine) restaurant.

        Respond with ONLY minified JSON, no prose or code fences:
        {"real": <true|false>, "items": [{"name": "...", "description": "...", "category": "..."}]}

        Rules:
        - "real": true ONLY if these are this exact restaurant's actual menu items; false if generic/typical.
        - List 12 to 20 items spanning the categories this place actually serves.
        - "category": one of breakfast, mains, sides, salads, soups, drinks, desserts.
        - "description": the dish's main ingredients, cooking method, and approximate portion \
        size — detailed enough to estimate calories and macros. Do NOT include any nutrition numbers.
        """
        let body: [String: Any] = [
            "messages": [["role": "user", "content": prompt]],
            "temperature": 0.3,
            "max_tokens": 1500
        ]
        let result = try await AIGatewayClient.send(body: body, modelOverride: nil)
        let parsed = parseResponse(result.content)
        let dishes = parsed.items
        guard !dishes.isEmpty else { return [] }

        // A recognised real menu is more trustworthy than a generic stand-in;
        // reflect that in confidence (the numbers are still on-device estimates).
        let confidence: NutritionConfidence = (parsed.real == true) ? .medium : .low
        let tag = (parsed.real == true) ? "real" : "generic"

        var seen = Set<String>()
        return dishes.prefix(24).enumerated().compactMap { index, dish in
            let trimmedName = dish.name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmedName.isEmpty, seen.insert(trimmedName.lowercased()).inserted else { return nil }
            let itemID = restaurant.id + ":ai:\(tag):" + SampleMenuData.slug(trimmedName) + "\(index)"
            let est = MenuNutritionEstimator.estimate(name: trimmedName, description: dish.description ?? "")
            var components = est.components
            for i in components.indices { components[i].id = "\(itemID)#\(i)" }
            return MenuItem(
                id: itemID,
                restaurantID: restaurant.id,
                name: trimmedName,
                itemDescription: dish.description ?? "",
                category: dish.category.map { MenuCategory.from($0) } ?? .mains,
                price: nil,
                currencyCode: restaurant.currencyCode,
                components: components,
                modifications: MenuModificationFactory.standard(for: components),
                dietaryTags: est.dietaryTags,
                ingredientHints: est.uncertainTerms,
                defaultOilLevel: est.defaultOilLevel,
                // AI-reconstructed menu → never official; nutrition is a local estimate.
                sourceKind: .estimatedFromIngredients,
                baseConfidence: confidence)
        }
    }

    /// Tolerant of the `{real, items}` wrapper, a bare array, and code fences /
    /// stray prose around the JSON.
    private func parseResponse(_ content: String) -> (real: Bool?, items: [Dish]) {
        // Preferred shape: an object with "real" + "items".
        if let start = content.firstIndex(of: "{"), let end = content.lastIndex(of: "}"), start < end,
           let data = String(content[start...end]).data(using: .utf8),
           let response = try? JSONDecoder().decode(MenuResponse.self, from: data) {
            return (response.real, response.items)
        }
        // Fallback shape: a bare array of dishes (treat as generic).
        if let start = content.firstIndex(of: "["), let end = content.lastIndex(of: "]"), start < end,
           let data = String(content[start...end]).data(using: .utf8),
           let items = try? JSONDecoder().decode([Dish].self, from: data) {
            return (false, items)
        }
        return (nil, [])
    }
}
