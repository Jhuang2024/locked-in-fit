import Foundation

/// Generates the standard set of modifications for an item from its components:
/// sauce level, cheese, butter, add-protein, and portion controls. Sauces,
/// dressings, cheese, and sides are addressed individually because they're
/// tracked as separate components even when grouped under one menu item.
enum MenuModificationFactory {
    static func standard(for components: [MenuItemComponent]) -> [MenuModification] {
        var mods: [MenuModification] = []

        // Sauce / dressing level.
        if let sauce = components.first(where: { $0.kind == .sauce || $0.kind == .dressing || $0.kind == .dip }) {
            mods.append(MenuModification(id: "mod.sauce.side", label: "Sauce on the side", effect: .none, group: "sauce"))
            mods.append(MenuModification(id: "mod.sauce.none", label: "No \(sauce.name.lowercased())", effect: .removeComponent(componentID: sauce.id), group: "sauce"))
            mods.append(MenuModification(id: "mod.sauce.light", label: "Light \(sauce.name.lowercased())", effect: .scaleComponent(componentID: sauce.id, factor: 0.5), group: "sauce"))
            mods.append(MenuModification(id: "mod.sauce.extra", label: "Extra \(sauce.name.lowercased())", effect: .scaleComponent(componentID: sauce.id, factor: 2.0), group: "sauce"))
        }

        // Cheese.
        if let cheese = components.first(where: { $0.kind == .cheese }) {
            mods.append(MenuModification(id: "mod.cheese.none", label: "No cheese", effect: .removeComponent(componentID: cheese.id), group: "cheese"))
            var extra = cheese
            extra.id = cheese.id + ".extra"
            extra.name = "Extra " + cheese.name.lowercased()
            mods.append(MenuModification(id: "mod.cheese.extra", label: "Extra cheese", effect: .addComponent(extra), group: "cheese"))
        }

        // Butter.
        if let butter = components.first(where: { $0.name.lowercased().contains("butter") }) {
            mods.append(MenuModification(id: "mod.butter.none", label: "No butter", effect: .removeComponent(componentID: butter.id)))
        }

        // Add a protein (data-driven from the table so it's not hardcoded).
        if let chicken = FoodNutritionTable.all.first(where: { $0.canonicalName == "Chicken breast" }) {
            let grams = 120.0
            let add = MenuItemComponent(id: "add.protein.chicken", name: "Added grilled chicken", kind: .protein,
                                        grams: grams, base: chicken.per100g * (grams / 100), cookingMethod: .grilled)
            mods.append(MenuModification(id: "mod.add.chicken", label: "Add grilled chicken", effect: .addComponent(add)))
        }

        // Portion size.
        mods.append(MenuModification(id: "mod.portion.half", label: "Half portion", effect: .scalePortion(factor: 0.5), group: "portion"))
        mods.append(MenuModification(id: "mod.portion.double", label: "Double portion", effect: .scalePortion(factor: 2.0), group: "portion"))

        return mods
    }
}
