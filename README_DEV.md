# CarCare Log — developer notes

Personal car-maintenance tracker for iOS 17+. SwiftUI, SwiftData (+ optional CloudKit), WidgetKit,
UserNotifications, LocalAuthentication. No third-party packages, no network calls.

## Layout

| Path | What |
|---|---|
| `Packages/CarCareCore` | Pure Swift (Foundation only): models as values, forecast, reminders planner, odometer rules, part numbers, offline assistant, backup JSON, widget summary. All unit-tested. |
| `App/` | SwiftUI app. `Data/` SwiftData models + persistence, `Services/` reminders + widget output, `Support/` settings, localization, Face ID, `Views/` screens. |
| `Widget/` | WidgetKit extension (small + medium). Reads `widget-snapshot.json` from the App Group. |
| `AppTests/` | Tests that need the app target (SwiftData mapping, backup restore, localization bundles). |
| `Localization/strings.tsv` | Source of all UI texts (key, Ukrainian, English). |
| `App/Resources/Localizable.xcstrings` | String Catalog generated from the TSV. |
| `project.yml` | XcodeGen spec. The `.xcodeproj` is never committed. |
| `.github/workflows/ci.yml` | On every push: strings check → `swift test` → XcodeGen → simulator build + app tests (unsigned). |
| `.github/workflows/release.yml` | Manual: archive, automatic signing with an App Store Connect API key, upload to TestFlight. |
| `codemagic.yaml` | Alternative release path (not the primary one). |

## Build locally (on a Mac)

```bash
brew install xcodegen
xcodegen generate
open CarCareLog.xcodeproj
swift test --package-path Packages/CarCareCore
```

On Windows nothing can be compiled; push and read the CI result:
`gh run list`, `gh run view --log-failed`.

## Localization

All texts go through `L10n.t("key")` / `L10n.f("key", args…)`. That reads the chosen language's `.lproj`
bundle, so the in-app language switch also covers notification texts. To add or change a text:

1. Edit `Localization/strings.tsv` (tab-separated: `key<TAB>uk<TAB>en`; `\n` = line break).
2. Run `powershell -ExecutionPolicy Bypass -File scripts/gen-strings.ps1` (Windows) to regenerate the catalog.
3. CI (`scripts/check-strings.sh`) fails if a key used in code is missing or the catalog is stale.

The assistant replies in the language of the question (uk/ru/en). Its texts live in
`CarCareCore/Assistant/AssistantFormat.swift`, not in the catalog, because Russian is not an app UI language.

## iCloud switch

`CC_ICLOUD` build setting (`NO` by default) selects `App/Entitlements/CarCareLog-iCloud-$(CC_ICLOUD).entitlements`
and the Swift flag `ICLOUD_YES`. With `NO`, the app uses a local SwiftData store only and CI needs no Apple account.
With `YES` (release workflow input "icloud"), the store syncs to the CloudKit private database
`iCloud.com.carcarelog.app`. If the CloudKit store can't be opened, the app falls back to the local store and shows a banner.
Sync errors (`NSPersistentCloudKitContainer` events) and a full iCloud quota show a banner on Home.

CloudKit model rules are followed in `App/Data/Models.swift`: defaults or optionals everywhere, no unique
attributes, optional relationships with inverses, no stored enums.

Before the first iCloud build: in the Apple Developer portal, create the iCloud container `iCloud.com.carcarelog.app`
and enable iCloud (CloudKit) for the App ID `com.carcarelog.app`, then deploy the CloudKit schema to Production
from CloudKit Console after a first development run (see Apple's docs on "Deploy schema changes").

## Reminders

`ReminderService` rebuilds all pending notifications on launch, on every foreground and after every data change:
the soonest 50 due days (items due on the same day are grouped into one notification, 09:00 local, minus the lead time)
plus 3 odometer nudges (every 14 days after the last reading). If the lead time has already passed but the due day
hasn't, the reminder fires at 09:00 on the due day.

## Release

See `SETUP_GUIDE_RU.md` for the owner's steps. Secrets for `release.yml`:
`APPLE_TEAM_ID`, `ASC_KEY_ID`, `ASC_ISSUER_ID`, `ASC_KEY_P8` (full text of the `.p8` file).
The API key needs the **Admin** role so automatic signing can create certificates and profiles in the cloud.
Build number: `YYYY.MDD.HMM` (UTC), always increasing. Marketing version: `MARKETING_VERSION` in `project.yml`.
