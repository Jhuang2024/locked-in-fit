import SwiftUI

/// In-app patch notes. The latest release headlines Menu Checker.
struct PatchNotesView: View {
    var body: some View {
        List {
            Section {
                releaseHeader("Food Ratings", version: "1.2")
                note("star.fill", "Rate your food",
                     "Give anything you eat a 1–5 star rating: logged meals (in the meal's detail screen), food presets, and restaurant dishes in Menu Checker. Tap a star again to clear a rating.")
                note("arrow.up.arrow.down", "Sort by your ratings",
                     "Food Presets and every Menu Checker menu can now sort by highest rating, so your proven favorites float to the top when you're deciding what to eat or log again.")
                note("link", "Ratings flow through the app",
                     "Rating a logged meal also rates the matching food presets for the foods in it. Menu Checker ratings are saved per restaurant and dish, survive menu refreshes, and are included in backups and JSON export/import like the rest of your data.")
            }
            Section {
                releaseHeader("Menu Checker", version: "1.1")
                note("menucard.fill", "Menu Checker",
                     "Discover restaurants near you or anywhere in the world, browse their menus, and see estimated nutrition, a Health Score, and a Satiety Score for every item. List and map views, distance, cuisine, open-now, price, average menu health, and whether official nutrition is available. Search by name, cuisine, dish, address, city, or country, set a manual city, and keep saved restaurants, saved items, and recently viewed.")
                note("slider.horizontal.3", "Honest nutrition estimation",
                     "When a restaurant doesn't publish nutrition, we estimate it from the dish description, likely ingredients, cooking method, and a real restaurant portion, with sensible rounded numbers and a high/medium/low confidence. Official nutrition is always shown as-is and never quietly adjusted. Every estimate stores a breakdown you can inspect.")
                note("drop.fill", "Consistent oil handling",
                     "Oil contributes to both calories and fat. Steamed and raw items get exactly zero added oil, always. Deep-fried, pan-fried, stir-fried, grilled, roasted, sautéed, and baked each use their own assumptions, and you can override oil to none / light / standard / heavy / custom, recalculating instantly. Sauces, dressings, and cheese carry their own fat, so oil is never double-counted, and official nutrition that already includes oil is left untouched.")
            }
            Section {
                note("heart.fill", "Health Score",
                     "Every item gets a personalized 0–100 Health Score using your profile and goals: protein and fibre density, vegetables, processing, added sugar, saturated fat, sodium, calorie density, and how it fits your remaining macros. A big, balanced, high-protein meal can still score well.")
                note("gauge.with.dots.needle.bottom.50percent", "Satiety Score",
                     "A separate 0–100 Satiety Score estimates how filling an item is for its calories: protein, fibre, food volume, water content, and solid-vs-liquid calories. The two scores are deliberately different shapes and colours so they're never confused.")
                note("cart.fill", "Meal cart",
                     "Build a temporary cart of everything you ate: mix items from multiple restaurants, add custom foods, tweak modifications, quantities, and portions, and see live totals, combined scores, warnings, and confidence. The cart persists if you leave the screen or the app closes.")
                note("checkmark.circle.fill", "Log the whole meal",
                     "Log the cart as breakfast, lunch, dinner, or a snack in one tap. Set the date/time (log past meals too), a name, notes, portion eaten, save it as a reusable meal, and add a photo. It logs into your normal food history, updating daily calories, macros, remaining targets, and scores, and stays fully editable afterwards. Double taps can't create duplicate meals.")
                note("mic.fill", "Speak your meal",
                     "The manual Add Meal flow now has a microphone. Describe a meal naturally: “two scrambled eggs, toast with a little butter, and a banana”, and it transcribes, parses foods, quantities, prep, brands, sauces, and modifications into an editable preview with the same oil rules. Nothing is logged until you review and confirm.")
            } header: {
                Text("Scores, cart, logging & speech")
            } footer: {
                Text("All estimates are estimates; Menu Checker is honest about confidence and never presents a guess as official nutrition.")
            }
        }
        .navigationTitle("What's New")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func releaseHeader(_ title: String, version: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("v\(version)").font(.caption.weight(.bold)).foregroundStyle(.tint)
            Text(title).font(.title2.weight(.bold))
        }
        .padding(.vertical, 4)
    }

    private func note(_ icon: String, _ title: String, _ body: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon).font(.title3).foregroundStyle(.tint).frame(width: 28)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.subheadline.weight(.semibold))
                Text(body).font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }
}
