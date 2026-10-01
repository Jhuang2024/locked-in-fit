# Locked In Fit review — September 30, 2026

Changes are based on `main`, not the repository's older default Claude branch.
The existing five tabs and their tools are retained. Persisted changes are
additive; schema version 6 triggers the existing pre-migration store snapshot.

## Findings addressed

| Area | Problem | Result |
| --- | --- | --- |
| HealthKit | Observer acknowledged delivery before its asynchronous import finished | Completion follows import; unavailable/error path still acknowledges |
| HealthKit | Imported changes relied on autosave; zero totals could never correct old values | Explicit save before reporting success; zero step/energy totals update existing records |
| Steps | Different sources for one day could skew the average or select an arbitrary entry | Daily maximum consistently chosen; sources are not added together |
| Weight | Two weigh-ins on one day produced an extreme weekly change | Rate compares averages on distinct calendar days |
| Weight | EWMA treated DST day length as 23/25-hour observation spacing | Uses calendar day gaps |
| Maintenance | Intake window and trend-weight interval were different; short/sparse histories pretended to span 21 days | Uses actual matching interval and requires at least 80% logged coverage |
| Food history | Today's sick allowance changed past-day food targets | Allowance belongs to the selected date |
| Aggregations | Future workouts and meals could enter current weekly totals; weekly intake counted eight calendar days | Future records bounded; intake window counts seven calendar days |
| Meal parsing | Drinks inherited unknown or neighboring cooking methods and gained phantom oil calories | Drink profiles use raw preparation and ignore nearby food cooking words |
| Menu Checker | Editing a meal or running oil backfill charged oil already included in menu nutrition | Persistent oil provenance plus recognition of older Menu Checker meals |
| Menu Checker | Save errors were swallowed and the caller cleared the cart anyway | Failed save is surfaced; cart is retained; duplicate guard marks only successful saves |
| Backups | Meal photos' references, analysis results and oil provenance were omitted | Optional additive DTO fields retain those values |
| Backups | Workout calorie overrides vanished on restore | Override is included in JSON snapshots |
| Backups | A malformed category silently decoded as empty | Missing legacy keys remain supported; malformed present keys fail before import |
| Keychain | Updating a credential deleted the working value before replacement succeeded | Update in place; add only when missing |
| Numbers | Extremely long decimal input could parse as infinity | Non-finite parsed values rejected |
| Sleep | Bedtimes around midnight averaged to a midday consistency baseline | Circular median; duplicate nights do not weight history twice |
| Sleep | Last night's log did not count as a sleep check-in on its wake day | Sleep completion checks the wake date |
| Schedules | A one-day request produced two sessions; duplicate weekday preferences survived | Exact one-day split and unique weekdays |
| Google Calendar | Concurrent sign-in could replace an existing browser session; OAuth lacked explicit state binding | Guard concurrent sign-in and validate callback state/scheme |
| UI | Shared surfaces lacked a consistent hierarchy | Charcoal/orange design, larger card spacing/radii, unified backgrounds and typography; Reduce Motion respected for card entrances |

## WHOOP implementation

API v2 recovery, cycles, sleep/naps, workouts and body profile are synchronized
with pagination, stable-ID upserts, score-state handling and kJ-to-kcal conversion.
Raw response payloads preserve all provider fields in SwiftData and JSON backups.
Recovery is joined to its physiological cycle; sleep displays the wake date.
Missing measurements remain missing rather than becoming artificial zeroes.

Today has a WHOOP summary; Train, Sleep and Trends have contextual navigation.
The detail screen includes selectable trend charts, sleep need/stages, vitals,
workout zones/distance/elevation and body profile. Cycle total energy and imported
workouts cannot inflate Apple Health calorie credits or manual workout counts.

OAuth uses a minimal Node connector: secrets remain server-side, consent uses
expiring state and one-use exchange tickets, refresh tokens rotate, and tokens
remain in the phone's Keychain. Setup is documented in `WHOOPBroker/README.md`.
No server, WHOOP credentials or real account data are provisioned by this commit.

## Validation and limits

GitHub Actions builds/tests Debug on an iOS simulator, builds Release, captures
the dashboard and runs the Node connector tests. Regression tests cover daily
step selection, weight rates, legacy/malformed snapshots, WHOOP missing/scored
values, units/ID upserts, sleep clock wraparound, sick-day dates, schedule counts,
Menu Checker oil provenance and workout calorie snapshot coding.

Actual HealthKit background delivery and live WHOOP authorization require a
physical device and account consent; simulator tests cannot establish those.
The public WHOOP API has no Stress Monitor, Healthspan/WHOOP Age, Pace of Aging
or journal insight endpoints. The app identifies these as unavailable.

Existing photo backups hold file references, not image bytes; exporting JSON to
a different device does not transfer the source image files. WHOOP data is fully
contained in its snapshot records. WHOOP remote deletions are not propagated
silently; imported history has a separate explicit delete action. Personal
connector deployment is single-instance unless sticky routing/shared sessions
are added. See its README for the deployment requirements.

Activity/maintenance, photo nutrition, strength and appearance scores remain
estimates with the app's existing formulas; this review does not establish
medical accuracy or guarantee that every possible device-specific defect is gone.
