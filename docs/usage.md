# Usage

## Authorization-code login

The source of truth for this example is
[`Tests/OIDCLiteTests/ExampleUsage.swift`](../Tests/OIDCLiteTests/ExampleUsage.swift), which is
compiled with the test target.

```swift
// This example is compiled as part of the test target but never executed.

import AuthenticationServices
import Foundation
import OIDCLite

@MainActor
func authenticate(
    presentationContextProvider: any ASWebAuthenticationPresentationContextProviding
) async throws -> OIDCLite.TokenResponse {
    let oidc = OIDCLite(
        discoveryURL: "https://oidc.example.com/.well-known/openid-configuration",
        clientID: "clientid"
    )
    let endpoints = try await oidc.getEndpoints()
    let login = try oidc.createLoginURL(endpoints: endpoints)

    var authenticationSession: ASWebAuthenticationSession?
    defer { withExtendedLifetime(authenticationSession) {} }

    let callbackURL: URL = try await withCheckedThrowingContinuation { continuation in
        let session = ASWebAuthenticationSession(
            url: login.url,
            callbackURLScheme: "oidclite"
        ) { callbackURL, error in
            if let callbackURL {
                continuation.resume(returning: callbackURL)
            } else {
                continuation.resume(throwing: error ?? OIDCLiteError.authFailure(
                    "Authentication session returned no callback URL"
                ))
            }
        }
        session.presentationContextProvider = presentationContextProvider
        authenticationSession = session

        guard session.start() else {
            continuation.resume(throwing: OIDCLiteError.authFailure(
                "Unable to start authentication session"
            ))
            return
        }
    }

    return try await oidc.processResponseURL(
        url: callbackURL,
        login: login,
        endpoints: endpoints
    )
}
```

`createLoginURL` generates fresh state, nonce, and PKCE verifier values. `processResponseURL`
validates the returned state before exchanging the authorization code. The default redirect URI is
`oidclite://openID`; the default scopes are `openid`, `profile`, `email`, and `offline_access`. Both
can be overridden in the initializer.

## Discovery endpoints

`try await oidc.getEndpoints()` returns `OIDCLite.Endpoints` with these discovered values:

- `authorization: URL?`
- `token: URL?`
- `issuer: String?`
- `jwksURI: URL?`

Pass the returned endpoints to login and token operations. An operation requiring an absent
authorization or token endpoint throws `OIDCLiteError.missingEndpoint`.

## Refresh tokens and HTTP Basic authentication

Refresh a token with `try await oidc.refreshTokens(refreshToken, endpoints: endpoints)`. OIDCLite
does not manage the token lifecycle; callers store, refresh, and discard tokens for their
application.

Pass `basicAuth: true` when the provider requires client credentials in the HTTP
`Authorization: Basic` header. When configured, the client secret is then omitted from the form
body:

```swift
let tokens = try await oidc.refreshTokens(
    refreshToken,
    endpoints: endpoints,
    basicAuth: true
)
```

## Typed OAuth errors

Non-success token responses containing OAuth error JSON throw:

```swift
OIDCLiteError.oauthError(code: String, description: String?, httpStatus: Int)
```

Callers can use the OAuth code and HTTP status directly. Non-JSON error bodies throw
`OIDCLiteError.authFailure`; discovery, callback parsing, state validation, and missing endpoints
use their dedicated `OIDCLiteError` cases.
