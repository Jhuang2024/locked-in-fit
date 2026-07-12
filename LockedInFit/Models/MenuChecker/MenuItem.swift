import Foundation

/// Menu grouping. Free-form categories from providers are mapped onto these so
/// the menu screen can present a consistent set of sections.
enum MenuCategory: String, Codable, CaseIterable, Identifiable {
    case breakfast, mains, sides, salads, soups, drinks, desserts, sauces, kids, other

    var id: String { rawValue }
    var label: String {
        switch self {
        case .mains: return "Mains"
        case .kids: return "Kids"
        default: return rawValue.capitalized
        }
    }
    var systemImage: String {
        switch self {
        case .breakfast: return "sunrise"
        case .mains: return "fork.knife"
        case .sides: return "takeoutbag.and.cup.and.straw"
        case .salads: return "leaf"
        case .soups: return "bowl.fill"
        case .drinks: return "cup.and.saucer"
        case .desserts: return "birthday.cake"
        case .sauces: return "drop.triangle"
        case .kids: return "figure.child"
        case .other: return "square.grid.2x2"
        }
    }

    /// Map a free-form provider category name onto our fixed set.
    static func from(_ raw: String) -> MenuCategory {
        let l = raw.lowercased()
        if l.contains("breakfast") || l.contains("brunch") { return .breakfast }
        if l.contains("side") { return .sides }
        if l.contains("salad") { return .salads }
        if l.contains("soup") { return .soups }
        if l.contains("drink") || l.contains("beverage") || l.contains("cola") { return .drinks }
        if l.contains("dessert") || l.contains("sweet") { return .desserts }
        if l.contains("sauce") || l.contains("dip") || l.contains("dressing") { return .sauces }
        if l.contains("kid") { return .kids }
        if l.contains("main") || l.contains("entree") || l.contains("burger") || l.contains("plate") { return .mains }
        return .other
    }
}

/// How much added oil to assume for an item, overridable by the user. `.custom`
/// carries an explicit gram amount.
enum OilLevel: String, Codable, CaseIterable, Identifiable {
    case none, light, standard, heavy, custom

    var id: String { rawValue }
    var label: String {
        switch self {
        case .none: return "None"
        case .light: return "Light"
        case .standard: return "Standard"
        case .heavy: return "Heavy"
        case .custom: return "Custom"
        }
    }
    /// Multiplier applied to the method's standard oil estimate. `.custom` is
    /// handled separately via an explicit gram amount.
    var multiplier: Double {
        switch self {
        case .none: return 0
        case .light: return 0.5
        case .standard: return 1.0
        case .heavy: return 1.6
        case .custom: return 1.0
        }
    }
}

/// The internal kind of a dish component. Sauces, dressings, cheese, and sides
/// are tracked separately even when a menu visually groups them under one item,
/// so modifications and oil logic can address each independently.
enum ComponentKind: String, Codable, CaseIterable {
    case main, protein, carbBase = "carb_base", vegetable, cheese
    case sauce, dressing, dip, side, topping, breading, drinkBase = "drink_base", sweetener

    /// Whether this component already carries its own fat/oil (so cooking-oil
    /// estimation must NOT be applied on top of it).
    var carriesOwnFat: Bool {
        switch self {
        case .sauce, .dressing, .dip, .cheese, .sweetener: return true
        default: return false
        }
    }
}

/// One internal component of a menu item, with its own macros and cooking
/// method. The item's total nutrition is the sum of its components plus
/// estimated cooking oil.
struct MenuItemComponent: Identifiable, Codable, Equatable, Hashable {
    var id: String
    var name: String
    var kind: ComponentKind
    var grams: Double
    /// Base macros for this component *excluding* any cooking oil (which the oil
    /// estimator adds by method). Components that carry their own fat (sauces,
    /// cheese, dressings) include that fat here.
    var base: ResolvedNutrition
    var cookingMethod: CookingMethod
    /// Removable via a "no X" / "remove ingredient" modification.
    var removable: Bool = true

    init(id: String = UUID().uuidString,
         name: String,
         kind: ComponentKind,
         grams: Double,
         base: ResolvedNutrition,
         cookingMethod: CookingMethod = .unknown,
         removable: Bool = true) {
        self.id = id
        self.name = name
        self.kind = kind
        self.grams = grams
        self.base = base
        self.cookingMethod = cookingMethod
        self.removable = removable
    }
}

/// The effect a modification has on the item, resolved at estimate time.
enum ModificationEffect: Codable, Equatable, Hashable {
    /// Scale a specific component's macros (light sauce = 0.5, extra = 2.0).
    case scaleComponent(componentID: String, factor: Double)
    /// Drop a component entirely (no cheese, no sauce, remove ingredient).
    case removeComponent(componentID: String)
    /// Add a new component (add protein, extra cheese as a distinct add, add ingredient).
    case addComponent(MenuItemComponent)
    /// Multiply the whole item's portion (half = 0.5, double = 2.0).
    case scalePortion(factor: Double)
    /// Override the oil assumption for the whole item.
    case setOil(OilLevel)
    /// Purely informational (e.g. "sauce on the side") — no nutrition change.
    case none
}

/// A user-selectable modification on a menu item.
struct MenuModification: Identifiable, Codable, Equatable, Hashable {
    var id: String
    var label: String
    var effect: ModificationEffect
    /// Modifications in the same group are mutually exclusive (e.g. sauce level).
    var group: String?

    init(id: String = UUID().uuidString, label: String, effect: ModificationEffect, group: String? = nil) {
        self.id = id
        self.label = label
        self.effect = effect
        self.group = group
    }
}

/// A single menu item with everything needed to estimate, score, modify, and
/// log it. Value type produced by a `MenuProvider`.
struct MenuItem: Identifiable, Codable, Equatable, Hashable {
    var id: String
    var restaurantID: String
    var name: String
    var itemDescription: String
    var category: MenuCategory
    var price: Double?
    var currencyCode: String
    var photoAssetName: String?
    var components: [MenuItemComponent]
    var modifications: [MenuModification]
    var dietaryTags: [DietaryTag]
    /// Free-text ingredient hints when the provider gives them.
    var ingredientHints: [String]
    var defaultOilLevel: OilLevel
    var sourceKind: NutritionSourceKind
    var baseConfidence: NutritionConfidence
    /// Official macros for one serving, present only when `sourceKind == .official`.
    /// When set, these are used verbatim and never adjusted by our estimators.
    var officialNutrition: ResolvedNutrition?
    /// Whether stated nutrition is for the whole dish, per serving, or per item.
    var servingBasis: ServingBasis

    enum ServingBasis: String, Codable {
        case perItem = "per_item"
        case perServing = "per_serving"
        case wholeDish = "whole_dish"
        var label: String {
            switch self {
            case .perItem: return "per item"
            case .perServing: return "per serving"
            case .wholeDish: return "whole dish"
            }
        }
    }

    init(id: String = UUID().uuidString,
         restaurantID: String,
         name: String,
         itemDescription: String = "",
         category: MenuCategory,
         price: Double? = nil,
         currencyCode: String = "USD",
         photoAssetName: String? = nil,
         components: [MenuItemComponent] = [],
         modifications: [MenuModification] = [],
         dietaryTags: [DietaryTag] = [],
         ingredientHints: [String] = [],
         defaultOilLevel: OilLevel = .standard,
         sourceKind: NutritionSourceKind = .estimatedFromIngredients,
         baseConfidence: NutritionConfidence = .medium,
         officialNutrition: ResolvedNutrition? = nil,
         servingBasis: ServingBasis = .perItem) {
        self.id = id
        self.restaurantID = restaurantID
        self.name = name
        self.itemDescription = itemDescription
        self.category = category
        self.price = price
        self.currencyCode = currencyCode
        self.photoAssetName = photoAssetName
        self.components = components
        self.modifications = modifications
        self.dietaryTags = dietaryTags
        self.ingredientHints = ingredientHints
        self.defaultOilLevel = defaultOilLevel
        self.sourceKind = sourceKind
        self.baseConfidence = baseConfidence
        self.officialNutrition = officialNutrition
        self.servingBasis = servingBasis
    }
}
