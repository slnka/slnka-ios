# Changelog

All notable changes to the SLNK iOS SDK are documented in this file.

The format is loosely based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [1.0.0-beta.7] - 2026-05-04

### Added — Mobile behavior tracking (US-833 / US-834 / US-835 / US-836)

Symetrie complete avec le SDK Android `1.0.0-beta.7`. Trois nouveaux SwiftUI
view modifiers, alimentes par une queue dediee separee de l'EventQueue
business :

- **`View.slnkaTrackTaps(_ composableId:)`** — capture des taps avec
  coordonnees normalisees `[0.0, 1.0]` via `simultaneousGesture(DragGesture)`
  qui ne bloque ni les `Button`, ni les `onTapGesture`, ni le scroll. Combine
  avec `SlnkaInstrumentedScreen("home_screen") { ... }` pour propager le nom
  de l'ecran via l'`Environment(\.slnkaScreenName)`.
- **`View.slnkaDetectRage(_ composableId:)`** — detection de rage taps via
  fenetre glissante de 2 s, rayon de cluster 50 pt et seuil minimum de 3
  taps. Algorithme centroide brute-force O(n²) (buffer borne par la fenetre).
  Debounce per-cluster pour ne pas double-fire. Buffer thread-safe via
  `NSLock`.
- **`View.slnkaTrackScroll(_ composableId:)`** — emission d'un evenement par
  seuil de profondeur (25 / 50 / 75 / 90 / 100 %) via `GeometryReader` +
  `coordinateSpace(name:)`. Une emission par seuil par instance de modifier
  (reset on disappear).

Infrastructure :

- **`BehaviorEventQueue`** — queue dediee, `DispatchQueue` serial, batch 50
  evenements / 30 s, drop-oldest sur overflow (max 1000), drop batch sur HTTP
  failure (signaux statistiques, on n'inflate pas le storage offline). Auto
  flush sur `UIApplication.didEnterBackgroundNotification`.
- **`Transport.sendMobileBehaviorBatch(_:)`** — `POST
  /api/v1/analytics/events/mobile/batch` avec enveloppe polymorphique
  (`eventType: "click" | "scroll" | "rage"`). Reutilise l'authentification
  Bearer existante.
- **`SlnkaConfig`** : nouveaux flags `enableHeatmaps`, `enableRageDetection`,
  `enableScrollDepth` (default `true`) + `behaviorBatchSize` (50),
  `behaviorFlushIntervalMs` (30 000), `behaviorMaxQueueSize` (1000).

Compatibilite : iOS 15+, macOS 13+, zero dependances externes. Si tous les
flags behavior sont desactives, la queue n'est meme pas allouee.

## [1.0.0-beta.5] - 2026-04-30

### Changed
- **Path migration to `/api/v1/sdk/**`**: all SDK ingestion and feedback calls now hit
  the new dedicated `/api/v1/sdk/**` endpoints on the SLNK backend. Internal-only
  admin endpoints under `/api/v1/analytics/**` and `/api/v1/feedback/**` remain
  reserved for the dashboard and are no longer called from the SDK.

  | Old path | New path |
  |---|---|
  | `POST /api/v1/analytics/events` | `POST /api/v1/sdk/events` |
  | `POST /api/v1/analytics/events/batch` | `POST /api/v1/sdk/events/batch` |
  | `POST /api/v1/analytics/attribution/touchpoint` | `POST /api/v1/sdk/attribution/touchpoint` |
  | `POST /api/v1/analytics/attribution/conversion` | `POST /api/v1/sdk/attribution/conversion` |
  | `POST /api/v1/feedback/responses` | `POST /api/v1/sdk/feedback/responses` |
  | `POST /api/v1/feedback/surveys/responses` | `POST /api/v1/sdk/feedback/surveys/responses` |
  | `PUT /api/v1/feedback/surveys/responses/{id}/complete` | `PUT /api/v1/sdk/feedback/surveys/responses/{id}/complete` |

  The `/api/v1/sdk/consent` endpoint is unchanged.

### Backwards compatibility
- The legacy paths under `/api/v1/analytics/**` and `/api/v1/feedback/**` are still
  served by the backend during a transition window and will respond with a
  `Deprecation: true` header. They are scheduled for removal on **2026-10-30**.
- Existing integrations on `1.0.0-beta.4` will keep working until that sunset
  date, but should upgrade to `1.0.0-beta.5` before then.

### Upgrading

#### Swift Package Manager
Bump the `from:` constraint in your `Package.swift` (or in Xcode under
**File > Package Dependencies**) to the new tag:

```swift
dependencies: [
    .package(url: "https://github.com/slnka/slnka-ios.git", from: "1.0.0-beta.5")
]
```

Then resolve packages (Xcode: **File > Packages > Update to Latest Package Versions**,
or `swift package update` from the command line).

No source-level API changes — this is a transport-only migration.

## [1.0.0-beta.4] - 2026-04-23

- Previous release. See git history for details.
