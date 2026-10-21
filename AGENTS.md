# AGENTS.md

Orientation for coding agents and new contributors. Humans: CONTRIBUTING.md
has the same material with more context.

## What this is

The official Swift SDK for the Onetime Secret v2 REST API
(https://api.onetimesecret.com/doc/api-v2). One library product,
`OnetimeSecret`, no dependencies, Swift 6 language mode, Apple platforms and
Linux.

## Commands

```sh
make test        # unit tests (Swift Testing), fixtures + MockTransport, ~1s
make lint        # swiftformat --lint --strict . && swiftlint lint --strict
make format      # apply both
make test-live   # opt-in end-to-end against the hosted US region (creates 5-minute secrets)
make docs        # DocC via xcodebuild docbuild (macOS only)
make example     # Examples/Roundtrip against ONETIME_BASE_URL (default: EU region, guest)
```

CI runs lint, macOS (Xcode 26.6, 26.0.1 and 16.0 for the Swift 6.0 floor),
iOS simulator tests, tvOS/watchOS/visionOS/Catalyst builds, Linux (Swift
6.0, 6.2, 6.4) and DocC with warnings as errors. The weekly live suite runs
on macOS and Linux. `-warnings-as-errors` is on; do not add suppressions.

## Layout

- `Sources/OnetimeSecret/Client` — `OnetimeSecretClient`, `Configuration`,
  `Credentials`, `Region`, `Version` (the version constant the release
  workflow checks against the tag).
- `Sources/OnetimeSecret/Resources` — the public operations, grouped as
  `client.secrets`, `client.receipts`, `client.system`.
- `Sources/OnetimeSecret/Models` — public value types. States are
  `RawRepresentable` structs, not enums, so unknown API values decode.
- `Sources/OnetimeSecret/Internal` — request building, response envelopes,
  lenient decoding helpers. Status-code → error mapping lives in
  `RequestExecution.swift`.
- `Tests/OnetimeSecretTests/Fixtures` — real API responses with identifiers
  scrubbed. Capture new ones from the live service; do not hand-write.
- `Examples/Roundtrip` — a separate executable package that depends on the
  SDK by relative path. It is the one place `print` is allowed; CI builds it.

## Rules that are easy to miss

- Nothing in `Sources/` may log. SwiftLint custom rules fail on `print`,
  `NSLog`, `os_log`, `Logger`.
- `description`/`debugDescription` on any type that can hold a secret,
  passphrase or token must omit it; `DecodingTests.descriptions` asserts
  this. Decode secret-bearing responses with `sensitivity: .mayContainSecret`.
- `passphraseGated: true` is passed only by reveal and burn; it is what turns
  a 422 about the passphrase into `.passphraseRejected`.
- Guest vs authenticated endpoints are chosen by `client.path(_:guest:)`
  from whether credentials exist. Never ask the caller to pick.
- The service also serves the authenticated endpoints under
  `/api/v2/private/*` aliases. They are deliberately not exposed: the SDK
  uses `/api/v2/...` with credentials and `/api/v2/guest/...` without, and
  nothing should introduce a third path family.
- `generate()` fetches the receipt once after creation to claim the single
  disclosure of the generated value. Removing that changes a documented
  behaviour (`GenerateOptions.claimValue`).
- Public API changes need a doc comment and a CHANGELOG entry under
  Unreleased. Releases go through `scripts/release.sh`; see RELEASING.md.
- Target v2 only. v3 is unstable and off limits until it is declared stable.
