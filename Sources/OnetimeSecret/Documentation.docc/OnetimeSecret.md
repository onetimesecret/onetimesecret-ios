# ``OnetimeSecret``

Share passwords and other sensitive text with self-destructing links.

## Overview

Onetime Secret stores a secret once and hands back a link. Whoever opens the
link and confirms sees the value exactly once; after that the secret is gone.
This package is the official Swift client for the
[v2 REST API](https://api.onetimesecret.com/doc/api-v2).

```swift
import OnetimeSecret

let client = OnetimeSecretClient(region: .europe)

// Creator side
let link = try await client.secrets.conceal(
    "db password: hunter2",
    options: ConcealOptions(timeToLive: 3600, passphrase: "say the magic word")
)
print(link.shareURL)        // https://eu.onetimesecret.com/secret/…
print(link.receiptURL)      // bookmark this to check on or burn the secret

// Recipient side
let revealed = try await client.secrets.reveal(link.secret.identifier, passphrase: "say the magic word")
print(revealed.value)
```

Every call is `async` and throws ``OnetimeSecretError``. The client, its
resources, and every model are `Sendable` values.

### Guests and accounts

Without ``Credentials`` the client is a guest: it can create, check, reveal
and burn secrets at the guest rate limit. With credentials it also lists
receipts, annotates them, emails recipients and uses custom share domains.

```swift
let client = OnetimeSecretClient(
    region: .unitedStates,
    credentials: Credentials(username: "you@example.com", apiToken: token)
)
```

Keep the token in the Keychain, not in source or `UserDefaults`.

### Regions and self-hosting

Secrets never leave the region they were created in. Pick the ``Region``
your users expect, or point ``Configuration/baseURL`` at your own
installation.

## Topics

### Essentials

- ``OnetimeSecretClient``
- ``Configuration``
- ``Credentials``
- ``Region``

### Creating secrets

- ``OnetimeSecretClient/Secrets``
- ``ConcealOptions``
- ``GenerateOptions``
- ``CharacterSets``
- ``ConcealedSecret``
- ``GeneratedSecret``

### Reading secrets

- ``SecretStatus``
- ``RevealedSecret``
- ``Secret``
- ``SecretState``
- ``DisplayType``

### Receipts

- ``OnetimeSecretClient/Receipts``
- ``Receipt``
- ``ReceiptState``
- ``SecretKind``
- ``ReceiptSource``

### Service information

- ``OnetimeSecretClient/System``
- ``SystemStatus``
- ``SystemVersion``
- ``SupportedLocales``

### Errors

- ``OnetimeSecretError``
- ``APIErrorDetails``
- ``ClaimFailure``

### Customising transport

- ``HTTPTransport``
- ``URLSessionTransport``
- ``TransportRequest``
- ``TransportResponse``
