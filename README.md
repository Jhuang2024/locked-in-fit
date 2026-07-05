# Locked In Fit

Private, local-first iPhone tracker for calories, bodyweight, body fat, measurements, steps, workouts, and gamified strength progress. One user, no accounts, no backend, no cloud.

## What's inside

- **SwiftUI + SwiftData**, iPhone-only, iOS 17+, dark/light mode.
- **Photo meal analysis** with two modes:
  - **Mock Mode** (default) — offline, realistic fake estimates.
  - **OpenRouter Mode** — paste your OpenRouter API key in *Settings → AI Meal Analysis* (stored in Keychain, never in the DB), pick a model (default `openai/gpt-4o-mini`), Test Connection, and analyze real meal photos. Falls back to Mock automatically if no valid key.
- **Honest uncertainty**: every estimate shows a calorie range plus hidden-oil uncertainty by cooking method (stir-fried eggplant is treated as the oil sponge it is). Save your own frequent meals as reusable food presets.
- **Goals**: cut / maintain / lean bulk / aggressive bulk / custom, with trend weight (exponential smoothing), adaptive maintenance (formula blended with observed intake vs. weight trend), TEF, projected finish date, pace warnings, adherence score.
- **Workouts**: generator (phase, equipment, time, fatigue, focus muscles), set-by-set logging (weight/reps/duration/RPE), templates, repeat workout, exercise history charts.
- **Strength scores**: 0–1000 per movement pattern (squat, hinge, pushes, pulls, core, conditioning) from bodyweight-relative e1RM + progress + volume + consistency. Levels, badges, PR celebrations, weekly streaks, and a daily "Locked In" score.
- **HealthKit** (optional): reads steps, body mass, body fat %, active energy — Renpho data flows in via Apple Health. The app works fully without the permission. Auto-syncs every second while the app is open, and instantly in the background via HKObserverQuery whenever new Health data lands (HealthKit has no true background polling interval — this is the event-driven equivalent).
- **Home screen widget**: small/medium widget showing today's Locked In Score, calories remaining, and steps, backed by an App Group so it updates the moment the app syncs.
- **Export/import**: JSON and CSV export via share sheet, JSON import. All data stays on device.

## Install on your iPhone (free Apple ID is fine)

1. Open `LockedInFit.xcodeproj` in **Xcode 16+** on a Mac.
2. Select the **LockedInFit** target → *Signing & Capabilities* → set **Team** to your personal team (add your Apple ID under Xcode → Settings → Accounts if needed). Change the bundle ID if Xcode complains it's taken (e.g. `com.yourname.LockedInFit`).
3. Do the same on the **LockedInFitWidgetExtension** target (same Team). Xcode's automatic signing will register the `group.com.jerryhuang.LockedInFit` App Group for you the first time it builds — if it errors instead, open the App Groups capability on both targets and re-add/rename the group so it's unique to your account, then build again.
4. Plug in your iPhone, enable **Developer Mode** on the phone (Settings → Privacy & Security → Developer Mode), and pick the phone as the run destination.
5. Press **Run** (⌘R) on the **LockedInFit** scheme (not the widget scheme). First time: on the phone, trust the developer cert under Settings → General → VPN & Device Management.
6. With a free Apple ID the app expires after 7 days — just press Run again to reinstall. Data survives reinstalls.
7. To add the widget: long-press the home screen → **+** → search "Locked In Fit" → choose small or medium.

## OpenRouter setup (optional)

1. Get a key at [openrouter.ai](https://openrouter.ai) (free-tier models work).
2. In the app: **Settings → AI Meal Analysis** → paste key → **Save API Key** → **Test Connection**.
3. Model is a free-form string; use any vision-capable model (`openai/gpt-4o-mini`, `anthropic/claude-sonnet-4.5`, `google/gemini-2.5-flash`, …).
4. **Clear API Key** removes it from the Keychain and reverts to Mock Mode.

No real API key is anywhere in this repo — the placeholder is `ENTER_OPENROUTER_API_KEY_HERE`.

## Project layout

```
LockedInFit/
  Models/        SwiftData models + AI JSON contract
  Views/         Screens (Meals, Trends, Goals, Body, Workouts, Settings)
  ViewModels/    Photo-analysis flow state
  Services/      FoodAIService (mock + OpenRouter), Keychain, HealthKit,
                 calculators (nutrition, trend weight, goal projection,
                 strength score), workout generator, export/import, seeding
  Components/    Reusable cards, rows, rings, pickers
  Support/       Formatters, analytics helpers, widget snapshot/App Group bridge
LockedInFitWidget/
  Home screen widget target (WidgetKit). Reads the snapshot the app writes
  to the shared App Group — no HealthKit/SwiftData access of its own.
```

Sample data (meals, weights, workouts, goal, presets) is seeded on first launch so every screen has content immediately.
