# Changelog

All notable changes to this project are documented in this file.

The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/)
and the project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).
Entries under **Unreleased** are promoted by `scripts/release.sh prepare`.

## [Unreleased]

### Added

- Initial Swift client for the Onetime Secret v2 API: conceal, generate,
  status, preview, reveal; receipts (get, list, burn, memo); system status,
  version and locales.
- Hosted regions (`Region`) and self-hosted base URLs.
- Guest and authenticated (HTTP Basic) modes with automatic endpoint selection.
- Pluggable `HTTPTransport` with a `URLSession` default that disables caching
  and cookies.
- Typed errors (`OnetimeSecretError`) with request IDs, `Retry-After`, and
  redaction of secret material in descriptions and decoding failures.
- `generate` claims the generated value, which the service discloses once,
  and returns it in `value`. A failed claim keeps the created secret and
  reports a `ClaimFailure` with the status and error type only, never the
  API's message or the response body.
- Lenient decoding of legacy string-typed fields.
- Privacy manifest, DocC catalog, Linux support.
- `Examples/Roundtrip`: a runnable conceal, inspect, reveal walkthrough
  (`make example`), configured by the `ONETIME_*` variables the other SDKs use.

[Unreleased]: https://github.com/onetimesecret/onetimesecret-ios/commits/main
