# Decisions and assumptions

## Identity and accounts
- App name **CarCare Log**, bundle ID **com.carcarelog.app** (widget: `com.carcarelog.app.widget`),
  App Group `group.com.carcarelog.app`, iCloud container `iCloud.com.carcarelog.app`. Confirmed by the owner.
- Team ID is not in the repo. The release workflow reads it from the `APPLE_TEAM_ID` secret.
- GitHub repository is **public** (owner's choice): GitHub Actions macOS minutes are unlimited for public repos.
  The repo contains only code; user data never leaves the phone except in backups the user exports.

## Build and release
- **GitHub Actions is both CI and the cloud build service.** It's free for public repos, already set up, and
  needs no third account. Codemagic (free plan: 500 macOS M2 minutes/month, 1 user) is documented as an
  alternative in `codemagic.yaml` but is not needed.
- No Swift toolchain was installed on the owner's Windows PC (it needs ~5 GB of Visual Studio components). All
  compiling and testing happens on CI.
- Signing: automatic signing via `xcodebuild -allowProvisioningUpdates` with an App Store Connect API key
  (Admin role). No certificates or profiles are stored in the repo or in secrets.
- Build number is `YYYY.MDD.HMM` in UTC (e.g. `2026.1007.1530`): it always increases, never collides and doesn't
  depend on the workflow's run counter.
- The bundle ID must be registered once in the developer portal before the App Store Connect record can be created
  (guide step 7). Automatic signing registers the widget ID itself.
- Screenshots: the "Screenshots" workflow runs the app in the iOS Simulator in demo mode (`-demo`, sample data in memory)
  and uploads PNGs of every screen in uk/ru/en, light and dark. See `scripts/take-screenshots.sh`.

## iCloud
- **Off by default** (`CC_ICLOUD=NO`). The app is fully functional with the local store. The JSON backup file
  is the guaranteed way to move or restore data.
- Turning iCloud on needs a one-time CloudKit schema setup, which requires running a Debug build from Xcode on a
  Mac once (launch argument `-initCloudKitSchema`), then "Deploy to Production" in CloudKit Console. TestFlight and
  App Store builds use the Production CloudKit environment, which doesn't create record types on the fly.
  This is the optional last part of the guide.
- If the CloudKit store can't be opened, the app silently uses a local store and shows a banner.
  Note: that local fallback store and the CloudKit store are the same SQLite file location, so data is not lost.
- MVP supports one car. If sync ever produces two Car records, the oldest one is used.

## Forecast
- `today` and dates are compared by calendar day. A month is 30.4 days for mileage projections.
- If no odometer reading exists, the odometer of the item's last service entry is used as current.
- A km-only item with avg km/month ≤ 0 gets no date. It's listed under "By mileage" on Home with its due km, and
  becomes overdue as soon as the odometer reaches it.
- The predicted odometer for a time-based due date = current + avg/30.4 × days. For mileage-based, it's the due km.

## Reminders
- If the lead-time moment has already passed but the due day hasn't, the reminder fires at 09:00 on the due day.
- Overdue items get no new notification (they're shown at the top of Home).
- The odometer nudge is scheduled as 3 notifications, 14/28/42 days after the last reading (next ones are scheduled
  on every launch). The Home banner shows when ≥ 14 days passed, or when there are no readings at all.
- Notification texts follow the in-app language chosen at the moment they're scheduled.

## Data rules
- A service entry whose odometer is higher than the current one adds an OdometerReading **with the entry's date**.
- Odometer lower than the previous one: warning with "Save anyway / Cancel", never blocked.
- Deleting a part removes it from history entries (after a confirmation that says how many entries use it).
  An entry can end up with zero parts that way. It stays in history and can be edited.
- Part-number duplicates are checked after normalization (uppercase, no spaces/hyphens/dots), against the OEM and
  analogs of **other** items only. Analog lists drop duplicates and empty values.

## Assistant
- Fully rule-based, in `CarCareCore`. No data is invented: every answer comes from the user's records.
- Language detection: Ukrainian letters (і ї є ґ) and typical words → uk; ы э ъ ё and typical Russian words → ru;
  Latin only → en. A Cyrillic text of 8+ letters without any Ukrainian letter leans Russian. For a tie, the app
  language is used.
- A bare number below 2000 is read as thousands of km ("на 250" → 250 000). Bare numbers count as mileage only
  with a mileage cue ("на", "до", "at", "км", …) or when ≥ 2000. Four-digit years next to "году/року/year" are periods.
- Typo tolerance: edit distance ≤ 2 for words of ≥ 5 letters whose stem has ≥ 6 letters, ≤ 1 for shorter stems
  (otherwise "масло" would match "мосты"). Light stemming strips one common ending, keeping ≥ 3 letters.
- Item matching ranks by the number of matched words, then by full-phrase matches. Ties → tappable choices.
  The built-in synonym table (АКП/ATF/масло коробки, салонний фільтр/cabin filter, ГБО/LPG, свічки/spark plugs,
  etc.) is in `Synonyms.swift`. Single-word translations (фільтр/filter, олива/масло/oil, …) are in `TextTools.canonical`.
- "Що я міняв?" without a period shows the last 12 months.
- Without history, "due at N km" lists the item names under "No records, not included" rather than guessing.

## UI
- UI languages: Ukrainian (default), Russian, English. The assistant understands all three and replies in the language of the question.
- Light theme by default. The language switch rebuilds the UI, so on the first onboarding page pick the language before
  filling in the car fields.
- Face ID uses `deviceOwnerAuthentication` (biometrics with passcode fallback). Turning it on asks for
  authentication first. The app locks when it goes to the background.
- The app icon is a simple generated speedometer (1024×1024, no alpha channel).

## Changes after the first review (2026-10-07)
- The "Parts" tab is now **Schedule** ("Регламент"). An item needs its last replacement (date + odometer) when
  created; it becomes the first History entry. "Don't know — count from today" fills today and the current odometer.
- **History is the single source of truth** for "last replacement". Item cards show it read-only with "Log service".
- **History entries store item names as recorded** (`ServiceEntry.snapshot`). Renaming an item with history asks:
  "Fix a typo" (renames past entries too) or "It's a different part" (old item → archive, new item starts fresh).
- Items with history are **archived** instead of deleted (swipe). Archived items: no forecast, no reminders, History
  kept, can be restored or deleted (History still keeps the names).
- **Item names are unique** (case, extra spaces and ё/е ignored). A name used by an archived item offers
  "Restore from archive" or "Create new".
- The **current odometer** = the newest point among odometer readings and service entries (same day → highest km).
  Service entries no longer create odometer readings, so editing or deleting an entry immediately gives the right
  value everywhere. A service entry dated today also resets the 14-day odometer reminder.
- "Log service": date and odometer start empty and are required; the date can't be in the future.
- Home: today's date and "odometer updated N days ago"; upcoming = due within 12 months or 15 000 km, the rest under
  "Later"; tap a row → item card, swipe right → "Log service" with the items due that day.
- "+" menu (Log service / Add item) on Home, History and Schedule.
- Notifications at **11:00 local time**: one "lead time" before the due day and one on the due day.
- Car: one required "name" field + optional VIN; "Km per month" is required (1–20 000).
- Input limits: car name 40, item name 60, part number 30, odometer 0–2 000 000, interval 100–500 000 km and
  1–240 months.
- Assistant keeps the last 50 questions while the app is open.
- Backup format version 2 (reads version 1 files).
- Appetize preview: `.github/workflows/appetize.yml` builds a demo simulator build (`DEMO_BUILD`), publishes the zip as
  the `appetize-preview` GitHub release asset (Appetize needs a public URL) and updates the same Appetize app.

## Round 2 (2026-10-08)
- **Built-in catalog** (`CarCareCore/Catalog.swift`, 58 items in 10 categories, uk/ru/en). Items added from it store
  `catalogKey`; their name always follows the app language (Schedule, Home, History, notifications, PDF) and can't
  be edited. Interval, part numbers and other names stay editable. Catalog items can be archived/deleted like any
  other. Typical intervals are shown only as gray hints in empty fields ("usually 10 000"), never saved.
  Custom items keep the typed name. A custom name equal to a catalog name ticks the catalog item instead.
- **Adding items** goes through one flow everywhere (+ menu, empty Schedule, onboarding step "What do you maintain?"):
  multi-select catalog + custom names → one form with intervals and last replacement, with "Same date and
  odometer for all" (one History entry for all) and "Don't know — count all from today".
- **Log service picker**: your schedule, the catalog (collapsed), and "Custom item «…»" for a search with no match.
  Catalog/custom picks become schedule items when the entry is saved (no interval yet → "No interval" block).
  A "Done · N selected" bar stays visible while searching; search closes after each pick.
- **Home**: one card per calendar month. Colors: red = overdue, yellow = due within 2 months, green = later; the
  card takes the most urgent color, every row has its own dot. Rows: "≈ 236 000 km · in 7 900 km". The stale
  odometer warning is now the orange odometer card itself (no separate banner).
- **Schedule order**: overdue first (most overdue on top), then by expected date (km limit converted to a date with
  the average km/month; earlier limit wins), km-only without a date, items without forecast last.
- **Average km/month** is computed from odometer updates and service entries of the last 6 months once they span
  ≥ 60 days (`MileageEstimator`); until then the manual value is used. Settings shows which one is active.
- **History**: "By date / By item" switch; "By item" shows each item's full replacement history with distance and
  months between replacements (also in the item card).
- **Multi-select** ("Select" button or long press) in History (delete) and Schedule (archive items with history,
  delete the rest). Settings → "Delete all data" with two confirmations.
- **Notifications**: buttons "Mark as done" (opens Log service with the items), "Remind me tomorrow" (copy tomorrow
  11:00) and "Enter odometer". Dismissing a notification changes nothing. App icon badge = number of overdue items.
- **Service book PDF** (Settings): cover, schedule table with status dots, full history, part numbers.
- **UI tests** (`UITests/`) run on CI in demo mode: picker select/deselect/search, custom item from Log service,
  odometer update → overdue on Home and Schedule, History multi-delete.


## Round 3 (2026-10-08)
- **Costs** live only in service entries: optional total, or "Split by item" (price per item; the total is their
  sum), plus an optional note. An item's "last price" is derived from History (split price, or the total of a
  single-item entry); nothing is stored on the item.
- **Currencies**: ₴ (default), $, €. Every entry remembers its currency. Totals never mix currencies: Expenses shows
  the app currency big and other currencies as a small line you can tap to switch. No exchange-rate conversion
  (that would need the internet).
- **Expenses tab** (Month / Year / All time): total, bars by month (or by year), donut by catalog category (custom
  items → "Other"; an unsplit multi-item total is shared equally between its items), list of paid services.
  Non-service costs (fuel, wash, fines) are out of scope.
- **Navigation**: Home · History · Schedule · Expenses · Assistant; Settings opens from the gear on Home (iOS shows
  at most 5 tabs).
- **Item kinds**: Interval (km and/or months, at least one required), Valid until (insurance, inspection: reminder
  before the end date, entered in the item or when logging the service), Season (months of the year, e.g. April and
  October: due on the 1st of the next season month after the last service; overdue once that month has passed).
  Catalog defaults: insurance and inspection → Valid until, seasonal tires → Season (Apr, Oct).
- **Texts**: time-based forecasts read "in ~5 mo." (days below 45 days), mileage-based ones "in 7 900 km · ≈ 236 000 km".
- **Home**: compact car card in the theme color (orange when the odometer is stale, which replaces the separate
  banner), summary chips "1 overdue · 2 soon · 6 fine" that filter the list, month cards with the month inside the
  card and a single status dot + word ("Soon"); no dots on items.
- **Schedule**: wear rings (share of the interval used: max of time share and km share; "!" when overdue).
- **Notifications** (Settings → Notifications): master switch, separate switches for service / odometer / backup,
  time picker with minutes, lead time, odometer reminder every 1–60 days or off (the same value turns the Home
  odometer card orange).
- **Theme color**: teal (default), blue, purple, coral, graphite.
- **Lock screen widgets**: round gauge of the most urgent item ("8.9k km" / "38 d"), rectangular nearest month.
- **Automatic backup**: weekly, last 5 files, to iCloud Drive → CarCare Log in the iCloud build, otherwise to Files →
  On My iPhone → CarCare Log (which does not protect against losing the phone; Settings says so). Home and a
  notification remind after 14 days without any backup (automatic or exported).
- **Import from notes**: one service per line; dates (12.03.2024, 15/07/23, 05.2023, "окт 2022", a year), odometer
  (185000, 185 000, 185к, 170 тыс; a bare 10–999 is read as thousands and flagged), items via the user's items
  (whole-phrase matches only) then the catalog (synonyms, typos, 3 languages), else a new custom item. Preview with
  ✓ / ⚠, fix date or odometer per row, nothing is imported without confirmation.
- **Assistant**: Apple's on-device model does not support Ukrainian or Russian (as of the sources checked), so the
  rule-based assistant stays and now answers "how much did I spend (this year)?" and "how much was the oil?".
- **Haptics**: success on saving a service or bulk add, selection ticks on chips and season months.
- Backup format version 3 (reads 1 and 2).
