import Foundation

/// Per-100 g nutrition profile for a common restaurant ingredient. Macros here
/// exclude added *cooking* oil (that's the oil estimator's job); `carriesOwnFat`
/// components (sauces, cheese, dressings, butter) include their intrinsic fat.
struct FoodProfile {
    var canonicalName: String
    var keywords: [String]
    var per100g: ResolvedNutrition
    var kind: ComponentKind
    var defaultMethod: CookingMethod
    /// Typical grams of this ingredient in a restaurant portion.
    var typicalGrams: Double
    var dietaryTags: [DietaryTag]
    var carriesOwnFat: Bool

    init(_ canonicalName: String,
         keywords: [String],
         kcal: Double, p: Double, c: Double, f: Double, fiber: Double = 0, sodium: Double = 0,
         kind: ComponentKind,
         method: CookingMethod = .unknown,
         grams: Double,
         diet: [DietaryTag] = [],
         ownFat: Bool = false) {
        self.canonicalName = canonicalName
        self.keywords = keywords
        self.per100g = ResolvedNutrition(calories: kcal, protein: p, carbs: c, fat: f, fiber: fiber, sodium: sodium)
        self.kind = kind
        self.defaultMethod = method
        self.typicalGrams = grams
        self.dietaryTags = diet
        self.carriesOwnFat = ownFat
    }
}

/// A small but broad nutrition table for menu / speech estimation. Not meant to
/// be exhaustive; it's a reusable base the estimator draws on, deliberately
/// data-driven rather than hardcoded per restaurant item.
enum FoodNutritionTable {
    static let veg: [DietaryTag] = [.vegetarian, .vegan]

    static let all: [FoodProfile] = [
        // MARK: Proteins
        FoodProfile("Chicken breast", keywords: ["chicken breast", "grilled chicken", "chicken"], kcal: 165, p: 31, c: 0, f: 3.6, sodium: 74, kind: .protein, method: .grilled, grams: 170),
        FoodProfile("Chicken thigh", keywords: ["chicken thigh", "dark meat chicken"], kcal: 209, p: 26, c: 0, f: 10.9, sodium: 86, kind: .protein, method: .grilled, grams: 160),
        FoodProfile("Fried chicken", keywords: ["fried chicken", "chicken tender", "chicken nugget", "popcorn chicken", "karaage"], kcal: 250, p: 22, c: 9, f: 14, sodium: 480, kind: .protein, method: .deepFried, grams: 160),
        FoodProfile("Beef / steak", keywords: ["steak", "beef", "sirloin", "ribeye", "brisket"], kcal: 250, p: 26, c: 0, f: 15, sodium: 60, kind: .protein, method: .grilled, grams: 180),
        FoodProfile("Ground beef", keywords: ["ground beef", "beef patty", "burger patty", "minced beef"], kcal: 254, p: 26, c: 0, f: 17, sodium: 75, kind: .protein, method: .grilled, grams: 150),
        FoodProfile("Pork", keywords: ["pork", "pork chop", "pulled pork", "char siu"], kcal: 242, p: 27, c: 0, f: 14, sodium: 62, kind: .protein, method: .grilled, grams: 170, diet: []),
        FoodProfile("Bacon", keywords: ["bacon", "pancetta"], kcal: 541, p: 37, c: 1.4, f: 42, sodium: 1717, kind: .protein, method: .panFried, grams: 40),
        FoodProfile("Sausage", keywords: ["sausage", "chorizo", "bratwurst"], kcal: 300, p: 15, c: 2, f: 26, sodium: 800, kind: .protein, method: .grilled, grams: 90),
        FoodProfile("Salmon", keywords: ["salmon"], kcal: 208, p: 20, c: 0, f: 13, sodium: 59, kind: .protein, method: .grilled, grams: 170),
        FoodProfile("White fish", keywords: ["cod", "white fish", "haddock", "tilapia", "sea bass", "fish"], kcal: 105, p: 23, c: 0, f: 0.9, sodium: 78, kind: .protein, method: .grilled, grams: 170),
        FoodProfile("Tuna", keywords: ["tuna", "ahi"], kcal: 130, p: 28, c: 0, f: 1, sodium: 45, kind: .protein, method: .raw, grams: 120),
        FoodProfile("Shrimp", keywords: ["shrimp", "prawn"], kcal: 99, p: 24, c: 0.2, f: 0.3, sodium: 111, kind: .protein, method: .grilled, grams: 120, diet: []),
        FoodProfile("Tofu", keywords: ["tofu", "bean curd"], kcal: 76, p: 8, c: 1.9, f: 4.8, fiber: 0.3, sodium: 12, kind: .protein, method: .unknown, grams: 150, diet: veg),
        FoodProfile("Egg", keywords: ["egg", "scrambled egg", "fried egg", "omelette", "omelet"], kcal: 155, p: 13, c: 1.1, f: 11, sodium: 124, kind: .protein, method: .unknown, grams: 100, diet: [.vegetarian]),
        FoodProfile("Turkey", keywords: ["turkey"], kcal: 189, p: 29, c: 0, f: 7, sodium: 103, kind: .protein, method: .roasted, grams: 150),
        FoodProfile("Lamb", keywords: ["lamb", "mutton"], kcal: 294, p: 25, c: 0, f: 21, sodium: 72, kind: .protein, method: .grilled, grams: 170),
        FoodProfile("Paneer", keywords: ["paneer"], kcal: 265, p: 18, c: 1.2, f: 20, sodium: 22, kind: .protein, method: .unknown, grams: 120, diet: [.vegetarian], ownFat: true),
        FoodProfile("Chickpeas", keywords: ["chickpea", "garbanzo", "falafel"], kcal: 164, p: 9, c: 27, f: 2.6, fiber: 7.6, sodium: 24, kind: .protein, method: .unknown, grams: 130, diet: veg),
        FoodProfile("Black beans", keywords: ["black bean", "pinto bean", "refried bean", "beans"], kcal: 132, p: 8.9, c: 24, f: 0.5, fiber: 8.7, sodium: 2, kind: .protein, method: .boiled, grams: 130, diet: veg),
        FoodProfile("Lentils", keywords: ["lentil", "dal", "dahl"], kcal: 116, p: 9, c: 20, f: 0.4, fiber: 7.9, sodium: 2, kind: .protein, method: .boiled, grams: 150, diet: veg),

        // MARK: Carb bases
        FoodProfile("White rice", keywords: ["white rice", "steamed rice", "jasmine rice", "rice"], kcal: 130, p: 2.7, c: 28, f: 0.3, fiber: 0.4, sodium: 1, kind: .carbBase, method: .steamed, grams: 200, diet: veg),
        FoodProfile("Brown rice", keywords: ["brown rice"], kcal: 123, p: 2.7, c: 26, f: 1, fiber: 1.8, sodium: 4, kind: .carbBase, method: .steamed, grams: 200, diet: veg),
        FoodProfile("Fried rice", keywords: ["fried rice"], kcal: 163, p: 4, c: 26, f: 4, fiber: 0.9, sodium: 380, kind: .carbBase, method: .stirFried, grams: 220, diet: [.vegetarian]),
        FoodProfile("Pasta / noodles", keywords: ["pasta", "spaghetti", "noodle", "ramen", "udon", "penne", "linguine"], kcal: 158, p: 5.8, c: 31, f: 0.9, fiber: 1.8, sodium: 5, kind: .carbBase, method: .boiled, grams: 220, diet: [.vegetarian]),
        FoodProfile("Bread / toast", keywords: ["bread", "toast", "sourdough", "baguette"], kcal: 265, p: 9, c: 49, f: 3.2, fiber: 2.7, sodium: 491, kind: .carbBase, method: .baked, grams: 60, diet: [.vegetarian]),
        FoodProfile("Burger bun", keywords: ["bun", "brioche"], kcal: 279, p: 9, c: 50, f: 4, fiber: 2, sodium: 460, kind: .carbBase, method: .baked, grams: 70, diet: [.vegetarian]),
        FoodProfile("Tortilla / wrap", keywords: ["tortilla", "wrap", "burrito"], kcal: 310, p: 8, c: 52, f: 8, fiber: 3, sodium: 590, kind: .carbBase, method: .baked, grams: 70, diet: veg),
        FoodProfile("Naan", keywords: ["naan"], kcal: 310, p: 9, c: 50, f: 8, fiber: 2, sodium: 450, kind: .carbBase, method: .baked, grams: 90, diet: [.vegetarian]),
        FoodProfile("Fries", keywords: ["fries", "chips", "french fries"], kcal: 90, p: 2, c: 20, f: 0.1, fiber: 2.2, sodium: 6, kind: .side, method: .deepFried, grams: 130, diet: veg),
        FoodProfile("Potato", keywords: ["potato", "mashed potato", "baked potato"], kcal: 87, p: 1.9, c: 20, f: 0.1, fiber: 1.8, sodium: 5, kind: .carbBase, method: .boiled, grams: 180, diet: veg),
        FoodProfile("Quinoa", keywords: ["quinoa"], kcal: 120, p: 4.4, c: 21, f: 1.9, fiber: 2.8, sodium: 7, kind: .carbBase, method: .boiled, grams: 180, diet: veg),

        // MARK: Vegetables
        FoodProfile("Broccoli", keywords: ["broccoli"], kcal: 34, p: 2.8, c: 7, f: 0.4, fiber: 2.6, sodium: 33, kind: .vegetable, method: .steamed, grams: 120, diet: veg),
        FoodProfile("Salad greens", keywords: ["salad", "lettuce", "greens", "leaves", "arugula", "rocket", "spinach"], kcal: 17, p: 1.4, c: 2.9, f: 0.2, fiber: 1.3, sodium: 20, kind: .vegetable, method: .raw, grams: 90, diet: veg),
        FoodProfile("Mixed vegetables", keywords: ["mixed veg", "vegetables", "veggies", "stir fry vegetables"], kcal: 65, p: 2.6, c: 13, f: 0.3, fiber: 4, sodium: 30, kind: .vegetable, method: .stirFried, grams: 140, diet: veg),
        FoodProfile("Cucumber", keywords: ["cucumber"], kcal: 15, p: 0.7, c: 3.6, f: 0.1, fiber: 0.5, sodium: 2, kind: .vegetable, method: .raw, grams: 80, diet: veg),
        FoodProfile("Tomato", keywords: ["tomato"], kcal: 18, p: 0.9, c: 3.9, f: 0.2, fiber: 1.2, sodium: 5, kind: .vegetable, method: .raw, grams: 60, diet: veg),
        FoodProfile("Avocado", keywords: ["avocado"], kcal: 160, p: 2, c: 9, f: 15, fiber: 6.7, sodium: 7, kind: .vegetable, method: .raw, grams: 70, diet: veg),
        FoodProfile("Mushroom", keywords: ["mushroom"], kcal: 22, p: 3.1, c: 3.3, f: 0.3, fiber: 1, sodium: 5, kind: .vegetable, method: .sauteed, grams: 80, diet: veg),
        FoodProfile("Onion", keywords: ["onion"], kcal: 40, p: 1.1, c: 9.3, f: 0.1, fiber: 1.7, sodium: 4, kind: .vegetable, method: .raw, grams: 40, diet: veg),

        // MARK: Cheese (own fat)
        FoodProfile("Cheddar cheese", keywords: ["cheddar", "cheese"], kcal: 403, p: 25, c: 1.3, f: 33, sodium: 621, kind: .cheese, grams: 30, diet: [.vegetarian], ownFat: true),
        FoodProfile("Mozzarella", keywords: ["mozzarella"], kcal: 280, p: 22, c: 2.2, f: 17, sodium: 627, kind: .cheese, grams: 40, diet: [.vegetarian], ownFat: true),
        FoodProfile("Parmesan", keywords: ["parmesan", "parmigiano"], kcal: 431, p: 38, c: 4, f: 29, sodium: 1529, kind: .cheese, grams: 15, diet: [.vegetarian], ownFat: true),
        FoodProfile("Feta", keywords: ["feta"], kcal: 264, p: 14, c: 4, f: 21, sodium: 917, kind: .cheese, grams: 30, diet: [.vegetarian], ownFat: true),

        // MARK: Sauces / dressings / dips (own fat)
        FoodProfile("Mayonnaise", keywords: ["mayo", "mayonnaise", "aioli"], kcal: 680, p: 1, c: 0.6, f: 75, sodium: 635, kind: .sauce, grams: 20, diet: [.vegetarian], ownFat: true),
        FoodProfile("Ranch dressing", keywords: ["ranch"], kcal: 430, p: 1, c: 6, f: 45, sodium: 950, kind: .dressing, grams: 40, diet: [.vegetarian], ownFat: true),
        FoodProfile("Vinaigrette", keywords: ["vinaigrette", "olive oil dressing", "italian dressing", "dressing"], kcal: 450, p: 0, c: 3, f: 48, sodium: 600, kind: .dressing, grams: 35, diet: veg, ownFat: true),
        FoodProfile("Caesar dressing", keywords: ["caesar"], kcal: 470, p: 3, c: 4, f: 49, sodium: 1050, kind: .dressing, grams: 40, diet: [.vegetarian], ownFat: true),
        FoodProfile("Ketchup", keywords: ["ketchup", "tomato sauce"], kcal: 100, p: 1, c: 26, f: 0, sodium: 900, kind: .sauce, grams: 20, diet: veg, ownFat: true),
        FoodProfile("Soy sauce", keywords: ["soy sauce"], kcal: 60, p: 8, c: 6, f: 0, sodium: 5500, kind: .sauce, grams: 15, diet: veg, ownFat: true),
        FoodProfile("BBQ sauce", keywords: ["bbq sauce", "barbecue sauce"], kcal: 170, p: 0.8, c: 41, f: 0.6, sodium: 800, kind: .sauce, grams: 30, diet: veg, ownFat: true),
        FoodProfile("Teriyaki", keywords: ["teriyaki"], kcal: 90, p: 3, c: 16, f: 0, sodium: 3800, kind: .sauce, grams: 30, diet: veg, ownFat: true),
        FoodProfile("Sweet chili", keywords: ["sweet chili", "sweet chilli"], kcal: 250, p: 0, c: 60, f: 0, sodium: 600, kind: .sauce, grams: 30, diet: veg, ownFat: true),
        FoodProfile("Chili oil", keywords: ["chili oil", "chilli oil", "chile oil"], kcal: 884, p: 0, c: 0, f: 100, sodium: 5, kind: .sauce, grams: 12, diet: veg, ownFat: true),
        FoodProfile("Sour cream", keywords: ["sour cream"], kcal: 198, p: 2, c: 4, f: 19, sodium: 50, kind: .sauce, grams: 30, diet: [.vegetarian], ownFat: true),
        FoodProfile("Guacamole", keywords: ["guacamole", "guac"], kcal: 160, p: 2, c: 9, f: 15, fiber: 6, sodium: 350, kind: .dip, grams: 45, diet: veg, ownFat: true),
        FoodProfile("Salsa", keywords: ["salsa", "pico de gallo"], kcal: 36, p: 1.5, c: 7, f: 0.2, fiber: 1.5, sodium: 430, kind: .sauce, grams: 40, diet: veg, ownFat: true),
        FoodProfile("Hummus", keywords: ["hummus"], kcal: 166, p: 8, c: 14, f: 10, fiber: 6, sodium: 379, kind: .dip, grams: 50, diet: veg, ownFat: true),
        FoodProfile("Gravy", keywords: ["gravy"], kcal: 60, p: 2, c: 5, f: 4, sodium: 700, kind: .sauce, grams: 50, diet: [.vegetarian], ownFat: true),
        FoodProfile("Pesto", keywords: ["pesto"], kcal: 450, p: 5, c: 6, f: 45, sodium: 700, kind: .sauce, grams: 30, diet: [.vegetarian], ownFat: true),
        FoodProfile("Butter", keywords: ["butter"], kcal: 717, p: 0.9, c: 0.1, f: 81, sodium: 11, kind: .sauce, grams: 12, diet: [.vegetarian], ownFat: true),
        FoodProfile("Curry sauce", keywords: ["curry", "tikka masala", "korma"], kcal: 150, p: 3, c: 8, f: 12, fiber: 1.5, sodium: 500, kind: .sauce, grams: 120, diet: [.vegetarian], ownFat: true),

        // MARK: Desserts / sweet
        FoodProfile("Ice cream", keywords: ["ice cream", "gelato"], kcal: 207, p: 3.5, c: 24, f: 11, sodium: 80, kind: .main, grams: 120, diet: [.vegetarian], ownFat: true),
        FoodProfile("Cake", keywords: ["cake", "brownie", "cheesecake"], kcal: 370, p: 5, c: 50, f: 16, fiber: 1.5, sodium: 300, kind: .main, method: .baked, grams: 110, diet: [.vegetarian]),
        FoodProfile("Cookie", keywords: ["cookie", "biscuit"], kcal: 480, p: 6, c: 64, f: 22, fiber: 2, sodium: 350, kind: .main, method: .baked, grams: 50, diet: [.vegetarian]),
        FoodProfile("Added sugar / syrup", keywords: ["syrup", "honey", "sugar", "caramel"], kcal: 300, p: 0, c: 78, f: 0, sodium: 5, kind: .sweetener, grams: 20, diet: veg, ownFat: true),

        // MARK: Drinks
        FoodProfile("Regular soda", keywords: ["coke", "cola", "soda", "pepsi", "sprite", "lemonade"], kcal: 42, p: 0, c: 10.6, f: 0, sodium: 5, kind: .drinkBase, grams: 330, diet: veg),
        FoodProfile("Diet soda", keywords: ["coke zero", "diet coke", "zero sugar", "diet soda", "sugar free"], kcal: 0.4, p: 0, c: 0.1, f: 0, sodium: 10, kind: .drinkBase, grams: 330, diet: veg),
        FoodProfile("Orange juice", keywords: ["orange juice", "juice"], kcal: 45, p: 0.7, c: 10, f: 0.2, sodium: 1, kind: .drinkBase, grams: 250, diet: veg),
        FoodProfile("Milk", keywords: ["milk", "latte", "cappuccino"], kcal: 60, p: 3.2, c: 5, f: 3.3, sodium: 43, kind: .drinkBase, grams: 250, diet: [.vegetarian]),
        FoodProfile("Beer", keywords: ["beer", "lager", "ale"], kcal: 43, p: 0.5, c: 3.6, f: 0, sodium: 4, kind: .drinkBase, grams: 350, diet: veg),
        FoodProfile("Smoothie", keywords: ["smoothie", "shake", "milkshake"], kcal: 90, p: 2, c: 18, f: 1, fiber: 1.5, sodium: 40, kind: .drinkBase, grams: 350, diet: [.vegetarian]),
    ]

    /// Find profiles whose keywords appear in `text`, longest keyword first so
    /// "chicken breast" wins over "chicken". Each profile matches at most once.
    static func matches(in text: String) -> [(FoodProfile, String)] {
        let l = " " + text.lowercased() + " "
        var results: [(FoodProfile, String)] = []
        var consumed = l
        // Sort keywords by length descending across all profiles.
        let candidates: [(FoodProfile, String)] = all.flatMap { p in p.keywords.map { (p, $0) } }
            .sorted { $0.1.count > $1.1.count }
        var used = Set<String>() // canonical names already added
        for (profile, keyword) in candidates {
            guard !used.contains(profile.canonicalName) else { continue }
            if consumed.contains(keyword) {
                results.append((profile, keyword))
                used.insert(profile.canonicalName)
                // Blank out the matched keyword so shorter overlapping keywords
                // (e.g. "cheese" after "cheddar cheese") don't double-count.
                consumed = consumed.replacingOccurrences(of: keyword, with: " ")
            }
        }
        return results
    }
}
