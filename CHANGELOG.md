# Changelog

All notable changes to the SLNK iOS SDK are documented in this file.

The format is loosely based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

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
