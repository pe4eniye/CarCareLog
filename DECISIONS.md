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
- On this repo, a `git push` did not start the CI workflow automatically (cause unknown). Runs are started with
  `gh workflow run ci.yml` (or "Run workflow" on GitHub), which works.

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
- Ukrainian is the default UI language, English is the second one. Russian is understood by the assistant only.
- Light theme by default. The language switch rebuilds the UI, so on the first onboarding page pick the language before
  filling in the car fields.
- Face ID uses `deviceOwnerAuthentication` (biometrics with passcode fallback). Turning it on asks for
  authentication first. The app locks when it goes to the background.
- The app icon is a simple generated speedometer (1024×1024, no alpha channel).
