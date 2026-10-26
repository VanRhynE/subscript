# SubScript

A premium, local-first subscription tracker built with Flutter. All data stays on the device: no account, no backend, no tracking.

Published under **PL Productions**.

## Features

- Track subscriptions with name, cost, billing cycle (weekly / monthly / yearly), next billing date, category and colour
- Monthly overhead card, with every cycle normalised to a monthly cost
- Timezone-aware renewal reminders at 9:00 local time, scheduled with exact alarms where permitted
- Overdue billing dates roll forward automatically on app start
- Swipe to delete
- Dark-mode UI

## Tech stack

| Concern | Package |
|---|---|
| State management | `flutter_riverpod` 2.x |
| Local database | `isar_community` (maintained fork of Isar 3) |
| Notifications | `flutter_local_notifications` 19.x, `timezone`, `flutter_timezone` |
| Utilities | `path_provider`, `uuid`, `intl` |

## Project structure

```
lib/
├── main.dart                         # Service initialisation, theme, app shell
├── core/services/
│   └── notification_service.dart     # Exact, timezone-aware reminders
├── data/
│   ├── models/subscription_local.dart   # Isar collection + billing-cycle logic
│   └── services/database_service.dart   # Isar init + CRUD + watch stream
├── state/
│   └── subscription_provider.dart    # Providers + SubscriptionController
└── ui/
    └── dashboard_screen.dart         # Dashboard + add-subscription sheet
```

## Getting started

Requires Flutter 3.35 or newer.

```bash
flutter pub get
dart run build_runner build --delete-conflicting-outputs
flutter run
```

`build_runner` generates `subscription_local.g.dart`, which is not committed.

### Android

The manifest in `android/app/src/main/AndroidManifest.xml` already declares the notification, exact-alarm and boot-receiver entries. `android/app/build.gradle.kts` enables core library desugaring, which the notifications plugin requires.

On Android 13 and newer, the app asks for notification permission on first launch. For exact reminder timing, also allow **Alarms & reminders** for SubScript in system settings.

## Roadmap

- Edit / detail screen and "mark as paid"
- Unit tests for billing-date and cost logic
- Optional sync layer (records already carry an `isSynced` flag)
- Spending breakdown by category

## License

All rights reserved. © PL Productions.
