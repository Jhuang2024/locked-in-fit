# Locked In Fit: Patch Notes

## v1.1: Menu Checker

A major new feature that turns eating out into first-class, honestly-estimated
food logging. Menu Checker is a native extension of the existing meal system:
everything it logs flows through the same `MealLog` / `FoodItem`, calorie, macro,
daily-summary, score, goal, and history systems as manually logged food, and
stays fully editable afterwards. Nothing existing was removed or simplified.

### Restaurant discovery
- New **Menu Checker** entry point from the Food Log.
- Nearby restaurants from your current location, plus **worldwide** search.
- **List and map** views with distance, cuisine, open/closed, price level,
  average menu Health Score, and whether official nutrition is available.
- Search by restaurant name, cuisine, dish, address, city, or country.
- **Manual location**: browse another city without changing your device location.
- **Saved restaurants, saved menu items, and recently viewed.**
- Filters: distance, cuisine, open now, calories, protein, Health Score,
  Satiety Score, vegetarian/vegan, dietary restrictions, price, and
  official-nutrition-available.
- Location permission is requested only when location is first used; the whole
  feature still works via manual search if it's denied.

### Restaurant menu screen
- Header with name, address, distance, cuisine, hours, and nutrition-data source.
- Menu categories (breakfast, mains, sides, salads, soups, drinks, desserts,
  sauces…), in-menu search, and sort/filter.
- A card per item with name, description, photo (when available), price,
  calories, protein, carbs, fat, fibre, sodium, **Health Score**, **Satiety
  Score**, nutrition confidence, and whether the nutrition is official or
  estimated. Cards stay uncluttered; the full reasoning is on the detail screen.

### Honest nutrition estimation
- A reusable estimator (not hardcoded per restaurant) builds nutrition from
  portion size, ingredient quantities, cooking method, oil/butter, sauces,
  dressings, cheese, added sugar, breading, restaurant serving sizes, and
  whether sides are included.
- We never present an estimate as official. Sources are clearly distinguished:
  **Official nutrition**, **Restaurant-provided ingredients**, **Estimated from
  ingredients and portion size**, and **Low-confidence estimate**.
- Estimates use sensible rounded values (calories to the nearest 5/10, macros to
  the nearest gram) and a high/medium/low confidence: no fake precision. The
  full breakdown is stored so you can inspect and correct how it was calculated.

### Oil logic
- Oil contributes to both **calories and fat**.
- **Absolute rule:** anything **steamed** or **raw** gets exactly **0** oil
  calories and **0 g** added oil fat: no range, no "restaurants might". Oil only
  enters such a dish through a separately listed oily sauce, dressing, marinade,
  or topping, which is estimated on its own.
- Other methods use method-specific assumptions: deep-fried (by food type,
  breading, surface area, portion), pan-fried, stir-fried, sautéed (retained
  oil, not all the oil in the pan), grilled and roasted (never auto-zero: they
  account for marinade/finishing fat), boiled/poached (zero unless fat is
  specified), and baked (depends on the recipe).
- You can override oil to **None / Light / Standard / Heavy / Custom**, which
  recalculates calories, fat, Health Score, and warnings immediately.
- Oil is never double-counted: components that carry their own fat (sauces,
  cheese, dressings) don't get cooking oil added, and **official nutrition that
  already includes oil is left untouched.**

### Modifications
- Sauce on the side, no/light/extra sauce, no/extra cheese, no butter, add
  protein, change side, half/double/custom portion, add/remove ingredient.
- Sauces, dips, dressings, and sides are tracked as **separate components**
  internally even when grouped under one item, so each modification updates the
  estimate precisely.

### Health Score (0–100)
- Personalized to your profile and goals. Considers protein and fibre density,
  fruit/veg content, degree of processing, added sugar, saturated fat, sodium,
  calorie density, portion size, dietary restrictions, your calorie/macro
  targets, and whether the item fits today's remaining macros.
- Not a "low-calorie = healthy" score; a big, balanced, high-protein meal can
  score strongly. Shows short reasons and recalculates on any change.

### Satiety Score (0–100)
- Estimates how filling an item is **relative to its calories**: protein,
  fibre, food volume, water content, calorie density, solid-vs-liquid calories,
  fat, and refined carbs. A large high-protein, high-fibre meal beats a sugary
  drink or a small dense dessert. Visually distinct from the Health Score.

### Meal cart
- A temporary, **persistent** list of what you ate or plan to eat, grouped by
  restaurant, with per-item and total calories/macros, combined Health and
  Satiety scores, dietary warnings, and overall confidence.
- Edit, change quantity, duplicate, remove, clear, mix items from multiple
  restaurants, and add a custom food alongside menu items. Survives leaving the
  screen or the app closing.

### Logging the cart
- **Log This Meal** classifies the cart as breakfast, lunch, dinner, or snack,
  with date/time (log past meals too), meal name, notes, "ate the full amount"
  / portion percentage, save-as-reusable-meal, and a meal photo.
- Logs every component into your normal food history as one grouped meal;
  updates daily calories/macros, remaining targets, and nutrition/consistency/
  goal scores; triggers existing warnings; and stays editable. The cart clears
  only after logging succeeds, and a double tap can't create two meals.

### Speech meal dictation
- The existing **Manually Add Meal** flow gains a microphone (additive: typing
  and all existing manual logging are unchanged).
- Describe a meal naturally; it transcribes on-device, parses foods, quantities,
  prep methods, brands, restaurants, sauces, and modifications into an editable
  preview, estimates nutrition, and flags uncertain interpretations. It
  understands phrases like "half", "a little", "light oil", "no oil", "about one
  cup", "a handful", "steamed", "raw", "fried", "grilled".
- Applies the same oil rules as Menu Checker (steamed/raw = zero added oil).
  Nothing is logged until you review and confirm.

### Live data sources
- **Restaurant discovery** uses **Apple Maps (`MKLocalSearch`)**: real nearby and
  worldwide restaurant search, no API key required. The offline sample catalogue
  is a fallback when Maps returns nothing (offline / unsupported region).
- **Real menus, not generic ones.** Opening a restaurant reconstructs **that
  specific restaurant's actual menu** (identified by name, address, city, and
  cuisine) in two tiers, cheapest first:
  1. A knowledge-based call (OpenRouter → BazaarLink) that recognises chains and
     well-known places for free/cheap, no web search.
  2. Only when the model doesn't recognise the place, an actual **web search** via
     OpenRouter's `:online` models, so obscure and local restaurants can still be
     looked up online (their own site, delivery platforms, listings).

  If both come up empty it falls back to a generic menu for that cuisine (flagged
  with lower confidence). The on-device estimator computes calories, macros,
  Health Score, and Satiety Score for every item: nothing is presented as
  official.
- **Credit-conscious by design:** the cheap tier runs first and the costlier web
  search fires only on a miss (and only when OpenRouter is configured). Results
  are cached in memory and **on disk permanently**, so re-opening a restaurant,
  even after relaunching the app, costs nothing. A **refresh** button on the menu
  screen forces a fresh fetch when you want one. Sample restaurants stay free and
  are never sent to the AI.

### Architecture
- Modular components behind protocols: location/restaurant search, restaurant
  provider, menu retrieval, nutrition-source selection, nutrition estimation,
  ingredient parsing, oil estimation, Health Score, Satiety Score, cart
  management, meal logging, speech transcription, and natural-language parsing.
- Restaurant search, menu data, and official nutrition can come from different
  providers. Results are cached with refresh timestamps so stale data is never
  presented as current. Handles missing/partial menus, duplicate listings,
  closed restaurants, unsupported regions, offline, denied permissions, provider
  failures, items without photos, other languages, and different unit/currency
  systems.

### Tests
- New unit-test target covering: steamed and raw = zero added oil; raw salad
  dressing and steamed-fish chilli oil counted separately; official nutrition
  unchanged by oil estimates; cart totals; quantity and portion-percentage
  changes; Health and Satiety recalculation; speech parsing; duplicate-log
  prevention; logging a mixed-restaurant cart; and editing a meal after logging.
