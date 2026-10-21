# Onetime Secret for Swift

[![CI](https://github.com/onetimesecret/onetimesecret-ios/actions/workflows/ci.yml/badge.svg)](https://github.com/onetimesecret/onetimesecret-ios/actions/workflows/ci.yml)
[![Swift 6](https://img.shields.io/badge/Swift-6.0%2B-F05138?logo=swift&logoColor=white)](Package.swift)
[![Platforms](https://img.shields.io/badge/platforms-iOS%20%7C%20macOS%20%7C%20tvOS%20%7C%20watchOS%20%7C%20visionOS%20%7C%20Linux-blue)](Package.swift)
[![License: MIT](https://img.shields.io/badge/license-MIT-green.svg)](LICENSE)

The official Swift client for [Onetime Secret](https://onetimesecret.com):
share passwords and other sensitive text through links that work exactly
once. Built on the [v2 REST API](https://api.onetimesecret.com/doc/api-v2).

- `async`/`await` throughout, Swift 6 language mode, every type `Sendable`
- Guest or authenticated use; hosted regions or self-hosted installations
- Typed errors with request IDs, `Retry-After`, and a clear
  `passphraseRejected` case
- No dependencies, no logging, no disk writes, privacy manifest included;
  every `description` redacts secret material
- Pluggable transport for tests, logging, pinning or retries

## Installation

Add the package in Xcode (File → Add Package Dependencies) with the URL
`https://github.com/onetimesecret/onetimesecret-ios`, or in `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/onetimesecret/onetimesecret-ios.git", from: "0.1.0"),
],
targets: [
    .target(name: "YourApp", dependencies: [
        .product(name: "OnetimeSecret", package: "onetimesecret-ios"),
    ]),
]
```

Requires a Swift 6.0 or newer toolchain (Xcode 16.0 or newer). Deployment
targets: iOS 15, macOS 12, tvOS 15, watchOS 8, visionOS 1. Linux is supported
for server-side and CLI use. See [Platform support](#platform-support) for
what CI verifies on each.

## Usage

### Share a secret

```swift
import OnetimeSecret

let client = OnetimeSecretClient(region: .europe)

let link = try await client.secrets.conceal(
    "wifi: correct-horse-battery-staple",
    options: ConcealOptions(timeToLive: 3600, passphrase: "ask me")
)

link.shareURL     // give this to the recipient
link.receiptURL   // keep this to check on, or burn, the secret
```

### Receive one

```swift
// Metadata only; nothing is consumed yet.
let status = try await client.secrets.status(identifierOrLink)
guard status.isAvailable else { /* expired, burned or already read */ }

// The one-time read.
let revealed = try await client.secrets.reveal(identifierOrLink, passphrase: "ask me")
revealed.value
```

`status`, `preview` and `reveal` accept either the bare identifier or the
full share URL.

### Generate a password

```swift
let generated = try await client.secrets.generate(
    options: GenerateOptions(length: 24, characterSets: CharacterSets(symbols: false), timeToLive: 900)
)
generated.value      // the password, disclosed to you exactly once
generated.shareURL
```

The service shows a generated value to its creator a single time. The SDK
claims that disclosure for you by fetching the receipt right after creation;
pass `claimValue: false` to do it yourself through `receipts.get`. If that
second request fails, the secret still exists: you get it back with `value`
`nil` and the reason in `claimFailure`.

### Burn it

```swift
try await client.receipts.burn(link.receipt.identifier)
```

### With an account

Credentials unlock listing and annotating receipts, emailing recipients,
custom share domains and higher rate limits. The token comes from the API
settings page of your account; keep it in the Keychain.

```swift
let client = OnetimeSecretClient(
    region: .unitedStates,
    credentials: Credentials(username: "you@example.com", apiToken: token)
)

let recent = try await client.receipts.list()
try await client.receipts.updateMemo(recent[0].identifier, memo: "rotated 2026-10")
```

### Self-hosted

```swift
let client = OnetimeSecretClient(baseURL: URL(string: "https://secrets.example.com")!)
```

### Errors

Everything throws `OnetimeSecretError`:

```swift
do {
    _ = try await client.secrets.reveal(id, passphrase: guess)
} catch OnetimeSecretError.passphraseRejected {
    // wrong passphrase; the secret is still there
} catch OnetimeSecretError.notFound {
    // gone: expired, burned or already read
} catch let OnetimeSecretError.rateLimited(_, retryAfter) {
    // back off for retryAfter seconds
} catch let error as OnetimeSecretError where error.isRetryable {
    // 5xx or a network blip; see the note below before retrying
}
```

`error.requestID` is what to quote to support.

`isRetryable` means a retry *could* succeed, not that it is safe. A reveal
that timed out may already have consumed the secret, so check
`secrets.status(_:)` before revealing again; a repeated conceal creates a
second secret. Only `status`, `preview`, `receipts.get`, `receipts.list` and
the `system` calls are idempotent.

### Testing your own code

Inject a transport instead of hitting the network:

```swift
struct CannedTransport: HTTPTransport {
    func send(_ request: TransportRequest) async throws -> TransportResponse {
        TransportResponse(statusCode: 200, body: Data(fixtureJSON.utf8))
    }
}
let client = OnetimeSecretClient(region: .europe, transport: CannedTransport())
```

The SDK's own tests use the same seam; see `Tests/OnetimeSecretTests/Support`.

## Example

`Examples/Roundtrip` is a small executable package that conceals a secret,
reads its receipt, reveals it once and shows the receipt change state. It
talks to the EU region as a guest unless told otherwise:

```sh
make example                                            # https://eu.onetimesecret.com, guest
ONETIME_BASE_URL=https://us.onetimesecret.com make example
ONETIME_CUSTOMER_EXTID=ur... ONETIME_API_TOKEN=... make example   # as your account
```

`make example` is `swift run --package-path Examples/Roundtrip`. The same
`ONETIME_*` variables configure the other official SDKs and the live test
suite, and `ONETIME_BASE_URL` can point at a self-hosted or local server.

## Platform support

| Platform | Minimum | What CI runs |
| --- | --- | --- |
| macOS | 12 | Unit tests on Xcode 26.6, 26.0.1 and 16.0 |
| iOS | 15 | Unit tests on an iPhone simulator (Xcode 26) |
| Linux | Swift 6.0 | Unit tests on Swift 6.0, 6.2 and 6.4 |
| tvOS | 15 | Build only |
| watchOS | 8 | Build only |
| visionOS | 1 | Build only |
| Mac Catalyst | macOS 12 | Build only |

The Swift 6.0 floor is verified on macOS (Xcode 16.0) and on Linux. Build-only
platforms compile the package with warnings as errors but do not run the
tests; they share the `URLSession` transport with iOS and macOS, where it is
tested. The live suite runs weekly on macOS and Linux against the hosted
service.

## Documentation

API reference: https://onetimesecret.github.io/onetimesecret-ios/ (built from
the DocC catalog in `Sources/OnetimeSecret/Documentation.docc`). Run
`make docs-preview` to browse it locally.

## Project layout

```
Sources/OnetimeSecret/
  Client/      OnetimeSecretClient, Configuration, Credentials, Region, Version
  Resources/   secrets, receipts, system          (the public operations)
  Models/      Secret, Receipt, options, results   (public value types)
  Transport/   HTTPTransport protocol + URLSession default
  Errors/      OnetimeSecretError, APIErrorDetails
  Internal/    request building, envelopes, lenient decoding
Tests/OnetimeSecretTests/
  Fixtures/    JSON captured from the live API (identifiers scrubbed)
  Support/     MockTransport
  LiveTests    opt-in end-to-end suite (ONETIME_LIVE=1)
Examples/Roundtrip/
  Sources/     runnable conceal → receipt → reveal walkthrough (make example)
```

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md) for setup, conventions and the PR
checklist, and [RELEASING.md](RELEASING.md) for how versions ship.

## License

MIT. See [LICENSE](LICENSE).
