# Contributing

Thanks for helping. This document covers machine setup, the conventions CI
enforces, and what a good pull request looks like.

## Initial setup

You need macOS with Xcode 16.0 or newer for the full matrix (iOS, tvOS,
watchOS, visionOS simulators, DocC); CI uses Xcode 26.x, plus Xcode 16.0 to
prove the Swift 6.0 floor. On Linux, a Swift 6 toolchain is enough to build
and run the unit tests.

```sh
git clone https://github.com/onetimesecret/onetimesecret-ios.git
cd onetimesecret-ios
make setup     # brew bundle (SwiftLint, SwiftFormat, pre-commit, xcbeautify, actionlint, gh)
               # + installs the git hooks from .pre-commit-config.yaml
make test      # unit tests, ~1s
```

`make help` lists the rest. The ones you will use:

| Command | What it does |
| --- | --- |
| `make check` | Lint and test exactly as CI does. Run before pushing. |
| `make format` | Apply SwiftFormat and SwiftLint autocorrect. |
| `make test-ios` | Run the suite on an iOS simulator through `xcodebuild`. |
| `make example` | Run `Examples/Roundtrip` against the EU region as a guest; `ONETIME_BASE_URL` points it elsewhere. |
| `make test-live` | End-to-end against the hosted US region as a guest. Creates throwaway five-minute secrets. |
| `make docs-preview` | Build the DocC archive and serve it on localhost. |

Open the package in Xcode with `xed .`.

### Hook versions

The pre-commit hooks pin SwiftFormat and SwiftLint revisions. The Homebrew
versions on your machine and on CI runners may be newer; when the two
disagree, CI wins. Bump the pins with `pre-commit autoupdate` in a PR of
their own so formatting churn stays separate from code changes.

## Conventions

- **Swift 6 language mode, strict concurrency.** Everything public is
  `Sendable`. Prefer structs; reach for a class only when identity matters
  (see `MockTransport` for the pattern when you do).
- **No logging in `Sources/`.** SwiftLint fails the build on `print`, `NSLog`,
  `os_log` and `Logger`. Secrets must never be able to reach a log.
- **`description` never includes secret material.** If you add a type that
  can carry a value, passphrase or token, give it a `description` and
  `debugDescription` that omit it and add a case to
  `DecodingTests.descriptions`. Responses that can carry a secret are decoded
  with `sensitivity: .mayContainSecret` so decoding errors are redacted.
- **Lenient decoding.** The API's published schema allows strings where the
  live service sends booleans and numbers. Decode through the helpers in
  `Internal/LenientDecoding.swift`; do not use synthesized `Decodable` for
  API records.
- **Forward-compatible enums.** States, kinds and display types are
  `RawRepresentable` structs with static members, so a new value from the
  API decodes instead of throwing.
- **Public API gets a doc comment** and an entry under `Unreleased` in
  `CHANGELOG.md`. Keep a Changelog headings: Added, Changed, Deprecated,
  Removed, Fixed, Security.
- **Semantic versioning** is for the public Swift API. Removing or renaming
  anything public is a major bump once we reach 1.0.

### Tests

- Unit tests use [Swift Testing](https://developer.apple.com/documentation/testing)
  and `MockTransport`. Assert on the request the SDK built (method, path,
  headers, JSON body) as well as on the decoded result.
- Fixtures in `Tests/OnetimeSecretTests/Fixtures` are real responses captured
  from the live service with identifiers replaced. When the API changes
  shape, capture a new fixture rather than hand-editing the old one, and say
  so in the PR.
- The `Live` suite is skipped unless `ONETIME_LIVE=1`. Add a
  live test when you add an operation; it is what catches API drift.
- CI builds with `-warnings-as-errors`. Fix warnings, do not suppress them.

### Targeting the API

The SDK targets v2, the stable API. v3 is not stable and is not a target
until it is. If an endpoint you need exists only in v3, open an issue first.

When the API returns something the SDK does not model, the fix is usually a
field on `Secret` or `Receipt` plus a fixture update, not a new type.

## Pull requests

1. Branch from `main`. Direct pushes to `main` are blocked by branch
   protection.
2. Keep PRs focused. Formatting-only changes go in their own PR.
3. Fill in the template. The checklist is short on purpose.
4. CI must be green: `CI OK` fans in lint, macOS (three Xcode versions), iOS
   simulator tests, tvOS/watchOS/visionOS/Catalyst builds, Linux (three
   Swift versions) and DocC with warnings as errors.
5. One approving review from a code owner, then squash-merge. The squash
   commit title becomes the line people see in `git log`, so make it a
   sentence.

## Reporting problems

- Bugs and feature requests: GitHub issues, using the templates.
- Security: `security@onetimesecret.com`, see [SECURITY.md](SECURITY.md).
- Problems with the service rather than this client: the main
  [onetimesecret](https://github.com/onetimesecret/onetimesecret) repository.
