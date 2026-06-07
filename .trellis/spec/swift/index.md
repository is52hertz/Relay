# Swift Layer Guidelines

Language-level conventions for all Swift code in Relay.

| Guide | Covers |
|-------|--------|
| [concurrency.md](concurrency.md) | Default `MainActor` isolation, `nonisolated` data models, `@Observable`, event-monitor isolation, early-init pitfalls |
| [quality.md](quality.md) | File layout, naming, comments, Swift Testing, the verify-before-commit commands, dependency policy |

Build settings that shape everything (from `Relay.xcodeproj`): `SWIFT_VERSION = 5.0`,
`SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`, `SWIFT_APPROACHABLE_CONCURRENCY = YES`,
`SWIFT_UPCOMING_FEATURE_MEMBER_IMPORT_VISIBILITY = YES`.
