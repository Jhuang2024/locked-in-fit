import Foundation

/// Quantity/portion words → numeric multipliers. Shared by menu estimation and
/// speech meal parsing so "half", "a little", "one large piece", "two bites"
/// mean the same thing everywhere.
enum QuantityParser {
    /// Words that scale a portion, checked as whole tokens.
    static let wordMultipliers: [String: Double] = [
        "a": 1, "an": 1, "one": 1, "single": 1,
        "two": 2, "three": 3, "four": 4, "five": 5, "six": 6,
        "seven": 7, "eight": 8, "nine": 9, "ten": 10, "twelve": 12,
        "half": 0.5, "quarter": 0.25, "third": 0.33,
        "double": 2, "triple": 3,
        "couple": 2, "few": 3, "several": 3,
        "handful": 0.5, "some": 1, "little": 0.5, "bit": 0.4,
        "large": 1.4, "big": 1.3, "small": 0.7, "medium": 1, "regular": 1,
    ]

    /// Multi-word phrases → multiplier of a normal portion.
    static let phraseMultipliers: [(String, Double)] = [
        ("a little", 0.5), ("a bit of", 0.4), ("a handful", 0.5),
        ("a couple", 2), ("a few", 3),
        ("half the plate", 0.5), ("half a plate", 0.5),
        ("half of", 0.5), ("one large", 1.4), ("one small", 0.7),
        ("two bites", 0.15), ("a bite", 0.1), ("one bite", 0.1),
        ("about one cup", 1), ("one cup", 1), ("a cup", 1),
        ("one bowl", 1.4), ("a bowl", 1.4), ("large portion", 1.4), ("small portion", 0.7),
    ]

    /// Extract a leading portion multiplier from the words appearing just before
    /// `keyword` in `text`. Defaults to 1 when nothing quantity-like is found.
    static func leadingMultiplier(before keyword: String, in text: String) -> Double {
        let l = text.lowercased()
        guard let range = l.range(of: keyword.lowercased()) else { return 1 }
        let prefix = String(l[l.startIndex..<range.lowerBound])
        // Look at the last ~5 words before the keyword.
        let words = prefix.split { !$0.isLetter && !$0.isNumber && $0 != "/" }.map(String.init)
        let window = Array(words.suffix(5))
        let windowText = window.joined(separator: " ")

        // Phrase matches take precedence.
        for (phrase, mult) in phraseMultipliers where windowText.hasSuffix(phrase) || windowText.contains(phrase) {
            return mult
        }
        // Then the nearest recognizable token, scanning right-to-left.
        for token in window.reversed() {
            if let n = Double(token) { return max(0.05, n) }
            if token == "1/2" { return 0.5 }
            if token == "1/4" { return 0.25 }
            if let m = wordMultipliers[token] { return m }
        }
        return 1
    }

    /// Detect an explicit oil instruction anywhere in the text.
    static func oilLevel(in text: String) -> OilLevel? {
        let l = text.lowercased()
        if l.contains("no oil") || l.contains("without oil") || l.contains("oil free") || l.contains("oil-free") { return OilLevel.none }
        if l.contains("light oil") || l.contains("little oil") || l.contains("less oil") { return .light }
        if l.contains("extra oil") || l.contains("heavy oil") || l.contains("lots of oil") { return .heavy }
        return nil
    }
}

/// A single parsed component of a dish with its estimated portion and method.
struct ParsedComponent {
    var profile: FoodProfile
    var grams: Double
    var method: CookingMethod
    /// The exact text fragment matched, surfaced for user review.
    var matchedText: String
}

/// The result of interpreting a dish name / free-text meal description.
struct ParsedDish {
    var components: [ParsedComponent]
    /// Dish-wide cooking method when one is stated (e.g. "steamed fish").
    var overallMethod: CookingMethod?
    /// Whole-dish size multiplier from words like "large"/"small".
    var portionMultiplier: Double
    /// Explicit oil instruction, if any ("no oil", "light oil").
    var oilLevel: OilLevel?
    var confidence: NutritionConfidence
    var matchedKeywords: [String]
    /// Terms we couldn't confidently interpret — surfaced so the user can fix them.
    var uncertainTerms: [String]

    var isEmpty: Bool { components.isEmpty }
}

/// Turns a dish name / plain-language description into structured components.
/// Deliberately data-driven off `FoodNutritionTable` rather than hardcoding
/// per-restaurant items. Applies the same cooking-method detection everywhere so
/// oil handling is consistent between Menu Checker and speech dictation.
enum IngredientParser {

    static func parse(name: String, description: String = "") -> ParsedDish {
        let text = (name + " " + description).trimmingCharacters(in: .whitespaces)
        let lower = text.lowercased()

        let overallMethod = CookingMethod.detect(in: lower)
        let oilLevel = QuantityParser.oilLevel(in: lower)
        let portionMultiplier = wholeDishPortionMultiplier(in: lower)

        let matched = FoodNutritionTable.matches(in: text)
        var components: [ParsedComponent] = []
        var matchedKeywords: [String] = []

        for (profile, keyword) in matched {
            let qty = QuantityParser.leadingMultiplier(before: keyword, in: text)
            // A component keeps its own method unless the dish states one that
            // clearly applies to the protein/carb (e.g. "steamed fish").
            var method = profile.defaultMethod
            if let overall = overallMethod, profile.kind == .protein || profile.kind == .carbBase || profile.kind == .vegetable || profile.kind == .main {
                // Component-local method words win over the dish-wide one.
                if let local = componentLocalMethod(for: keyword, in: text) {
                    method = local
                } else {
                    method = overall
                }
            } else if let local = componentLocalMethod(for: keyword, in: text) {
                method = local
            }
            let grams = profile.typicalGrams * qty
            components.append(ParsedComponent(profile: profile, grams: grams, method: method, matchedText: keyword))
            matchedKeywords.append(keyword)
        }

        let uncertain = uncertainTerms(in: text, matchedKeywords: matchedKeywords)
        let confidence = confidenceFor(componentCount: components.count, uncertainCount: uncertain.count)

        return ParsedDish(components: components,
                          overallMethod: overallMethod,
                          portionMultiplier: portionMultiplier,
                          oilLevel: oilLevel,
                          confidence: confidence,
                          matchedKeywords: matchedKeywords,
                          uncertainTerms: uncertain)
    }

    /// Look for a cooking method word within a few tokens of the keyword, so
    /// "grilled chicken with steamed rice" gives chicken=grilled, rice=steamed.
    private static func componentLocalMethod(for keyword: String, in text: String) -> CookingMethod? {
        let l = text.lowercased()
        guard let range = l.range(of: keyword.lowercased()) else { return nil }
        let start = l.index(range.lowerBound, offsetBy: -24, limitedBy: l.startIndex) ?? l.startIndex
        let end = l.index(range.upperBound, offsetBy: 12, limitedBy: l.endIndex) ?? l.endIndex
        let window = String(l[start..<end])
        return CookingMethod.detect(in: window)
    }

    private static func wholeDishPortionMultiplier(in text: String) -> Double {
        if text.contains("large") || text.contains("big") { return 1.3 }
        if text.contains("small") { return 0.75 }
        if text.contains("half the plate") || text.contains("half plate") { return 0.5 }
        return 1
    }

    /// Descriptive words that suggest food we couldn't map to a profile, so the
    /// preview can flag "we weren't sure about X".
    private static func uncertainTerms(in text: String, matchedKeywords: [String]) -> [String] {
        let stop: Set<String> = ["with", "and", "a", "an", "the", "of", "some", "little", "in", "on",
                                 "side", "no", "extra", "light", "half", "one", "two", "three", "for",
                                 "my", "i", "ate", "had", "drank", "plus", "plate", "bowl", "cup",
                                 "medium", "large", "small", "fresh", "hot", "cold", "served", "topped",
                                 "oil", "sauce", "grilled", "fried", "steamed", "raw", "baked", "roasted"]
        let words = text.lowercased().split { !$0.isLetter }.map(String.init)
        let matchedWords = Set(matchedKeywords.flatMap { $0.split(separator: " ").map(String.init) })
        var uncertain: [String] = []
        for w in words where w.count > 3 && !stop.contains(w) && !matchedWords.contains(w) {
            if !uncertain.contains(w) { uncertain.append(w) }
        }
        return Array(uncertain.prefix(4))
    }

    private static func confidenceFor(componentCount: Int, uncertainCount: Int) -> NutritionConfidence {
        if componentCount == 0 { return .low }
        if uncertainCount >= 2 { return .low }
        if componentCount >= 1 && uncertainCount == 0 { return .medium }
        return .medium
    }
}
