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
