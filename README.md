# OIDCLite

While there are a few good Swift packages for OpenID Connect out there, most are very heavyweight and can get quite complex. For projects with modest needs—confirming a user is valid and perhaps acquiring an OIDC token set for a subsequent operation—OIDCLite may be what you're looking for.

OIDCLite implements the basics of getting tokens with Apple's `ASWebAuthenticationSession`, so you have very little web plumbing to deal with. It supports PKCE and client secrets.

`ASWebAuthenticationSession` works really well on iOS and blends in with your app. On the Mac, it is a bit of a different story, so try it out a few times.

OIDCLite takes a discovery URL, returns the provider's endpoints, and creates a login request for `ASWebAuthenticationSession`. After authorization, pass the callback URL, login request, and endpoints back to OIDCLite to validate state and exchange the code for tokens.

By default OIDCLite uses `oidclite://openID` as the redirect URI and `openid`, `profile`, `email`, and `offline_access` as scopes. You can override both in the initializer.

OIDCLite supports macOS 15+ and iOS 14+.

## Usage

The source of truth for this example is [`Tests/OIDCLiteTests/ExampleUsage.swift`](Tests/OIDCLiteTests/ExampleUsage.swift), which is compiled with the test target.

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

## API notes

### Discovery endpoints

`try await oidc.getEndpoints()` returns `OIDCLite.Endpoints`. Pass this value to login and token operations rather than storing endpoint state in OIDCLite:

- `authorization: URL?` — authorization endpoint
- `token: URL?` — token endpoint
- `issuer: String?` — discovered issuer
- `jwksURI: URL?` — discovered JSON Web Key Set URI

Operations that require a missing authorization or token endpoint throw `OIDCLiteError.missingEndpoint`.

### Typed OAuth errors

Non-success token responses containing OAuth error JSON throw:

```swift
OIDCLiteError.oauthError(code: String, description: String?, httpStatus: Int)
```

This lets callers make decisions using the OAuth error code and HTTP status instead of parsing an error message. Non-JSON error bodies use `OIDCLiteError.authFailure`; discovery, callback parsing, state validation, and missing endpoints have their own `OIDCLiteError` cases.

### Resource owner password grant

`requestTokenWithROPG(username:password:endpoints:basicAuth:overrideErrors:)` returns a token response on success. For HTTP 400–403 responses, each `overrideErrors` value is matched as a substring of the raw response body. A match returns `nil`, meaning credentials were accepted for the caller's policy but no token is available, such as an MFA-gated response. A non-match throws a typed OAuth error when the body is OAuth error JSON, or `authFailure` otherwise.

Entra and Okta ROPG use the same standards-based `application/x-www-form-urlencoded` codec. Codec reference: https://theproductguy.in/blogs/url-encoding-for-forms/

### Refresh tokens and HTTP Basic authentication

Refresh a token with:

```swift
let tokens = try await oidc.refreshTokens(refreshToken, endpoints: endpoints)
```

Pass `basicAuth: true` when the provider requires client credentials in the HTTP `Authorization: Basic` header. When a client secret is configured, it is omitted from the form body in this mode:

```swift
let tokens = try await oidc.refreshTokens(
    refreshToken,
    endpoints: endpoints,
    basicAuth: true
)
```

## Notes

- OIDCLite does not manage the token lifecycle; callers store, refresh, and discard tokens according to their application's needs.
- PKCE is always used for authorization-code login requests.
- Authorization-code and resource owner password grant token requests are supported.
- OIDCLite has been tested with Okta, Entra ID, OneLogin, ORY Hydra, and dex.

## Development

Dev tooling is managed with [mise](https://mise.jdx.dev). Run `mise install` to get SwiftLint, SwiftFormat, prek, and (on macOS) Tuist, then `prek install` to enable the pre-commit hooks. With [direnv](https://direnv.net), `direnv allow` puts the tools on your `PATH` automatically.

Run offline unit tests with `just test`. Integration tests require Go to build the pinned dex server; run them with `just itest`. Run all lint and formatting checks with `just lint`.
