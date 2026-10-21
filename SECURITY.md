# Security Policy

This SDK is a thin client: it holds your API token in memory for the lifetime
of a `Credentials` value, sends it over HTTPS as HTTP Basic authentication,
and hands secret values back to your code. It stores nothing on disk, writes
nothing to logs, and the default transport disables caching and cookies.

## Supported versions

The most recent minor release receives fixes. Older releases are updated only
for security issues, and only when upgrading is not a drop-in change.

## Reporting a vulnerability

Email `security@onetimesecret.com` with the subject
"Vulnerability Report: onetimesecret-ios". Include steps to reproduce and the
SDK version (`OnetimeSecretClient.version`). Do not open a public issue.

You will get an acknowledgment within 5 business days. The full disclosure
process is the same as for the service itself:
https://github.com/onetimesecret/onetimesecret/blob/main/SECURITY.md

## Guidance for integrators

- Keep the API token in the Keychain. Never in source, `UserDefaults`, or a
  plist that ships with the app.
- Treat `RevealedSecret.value` and `GeneratedSecret.value` as sensitive from
  the moment they are returned: do not log them, do not put them in analytics
  breadcrumbs, and clear them from your own state when they are no longer
  needed. Swift does not guarantee that a `String` is zeroed when it is freed.
- `description` and `debugDescription` on every SDK type that can hold
  secret material (`Credentials`, `RevealedSecret`, `GeneratedSecret`,
  `Secret`, `Receipt`, `ConcealOptions`, `GenerateOptions`,
  `TransportRequest`, `TransportResponse`) omit it, so interpolating a value
  into a log line is safe. Interpolating the properties themselves is not,
  and `dump()` or `Mirror` reflection bypasses `description` and prints
  every field.
- `OnetimeSecretError.decoding` keeps the response body for diagnostics;
  for responses that can carry a secret (reveal, receipt fetch) the SDK
  redacts `secret_value` and passphrase fields before attaching it.
- With credentials set, the SDK refuses to send requests over plain
  `http://` to anything other than a loopback host.
- Issues in the service rather than this client belong in the main
  repository's process above.
