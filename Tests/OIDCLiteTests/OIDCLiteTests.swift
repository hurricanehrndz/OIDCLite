import CryptoKit
import Foundation
@testable import OIDCLite
import Testing

@Suite(.serialized)
struct OIDCLiteTests {
    let discoveryURL = "https://example.com/.well-known/openid-configuration"
    let clientID = "BC76BE32-289C-4A56-B5F2-ACAB2B695EDB"
    let clientSecret = "BBA8C549-49BB-49D6-A835-C9372C36C32F"
    let authEndpoint = URL(string: "https://example.com/oauth/v2/auth")!
    let tokenEndpoint = URL(string: "https://example.com/oauth/v2/token")!

    @Test func initWithoutClientSecret() {
        let oidc = OIDCLite(discoveryURL: discoveryURL, clientID: clientID)

        #expect(oidc.discoveryURL == discoveryURL, "Failure to set DiscoveryURL")
        #expect(oidc.clientID == clientID, "Failure to set ClientID")
    }

    @Test func initWithClientSecret() {
        let oidc = OIDCLite(
            discoveryURL: discoveryURL,
            clientID: clientID,
            clientSecret: clientSecret
        )

        #expect(oidc.discoveryURL == discoveryURL, "Failure to set DiscoveryURL")
        #expect(oidc.clientID == clientID, "Failure to set ClientID")
        #expect(oidc.clientSecret == clientSecret, "Failure to set ClientSecret")
    }

    @Test func initAndGenerateLoginURL() throws {
        let oidc = OIDCLite(discoveryURL: discoveryURL, clientID: clientID)
        let login = try oidc.createLoginURL(endpoints: endpoints())

        #expect(login.url.isFileURL == false, "Login URL is File URL")
        #expect(login.url.host == "example.com")
        #expect(login.url.pathComponents.contains("v2"))
    }

    @Test func discoveryReturnsAllEndpoints() async throws {
        let body = try JSONSerialization.data(withJSONObject: [
            "authorization_endpoint": authEndpoint.absoluteString,
            "token_endpoint": tokenEndpoint.absoluteString,
            "issuer": "https://example.com",
            "jwks_uri": "https://example.com/keys"
        ])
        let session = try StubURLProtocol.session(responses: [(response(status: 200), body)])
        let oidc = OIDCLite(discoveryURL: discoveryURL, clientID: clientID, session: session)

        let result = try await oidc.getEndpoints()

        #expect(result.authorization == authEndpoint)
        #expect(result.token == tokenEndpoint)
        #expect(result.issuer == "https://example.com")
        #expect(result.jwksURI == URL(string: "https://example.com/keys"))
    }

    @Test func discoveryRejectsHTTPFailure() async throws {
        let session = try StubURLProtocol.session(responses: [(response(status: 404), Data())])
        let oidc = OIDCLite(discoveryURL: discoveryURL, clientID: clientID, session: session)

        await #expect(throws: OIDCLiteError.unableToLoadEndpoint) {
            try await oidc.getEndpoints()
        }
    }

    @Test func discoveryRejectsInvalidJSON() async throws {
        let session = try StubURLProtocol.session(responses: [
            (response(status: 200), Data("not json".utf8))
        ])
        let oidc = OIDCLite(discoveryURL: discoveryURL, clientID: clientID, session: session)

        await #expect(throws: OIDCLiteError.unableToParseEndpoint) {
            try await oidc.getEndpoints()
        }
    }

    @Test func discoveryRejectsInvalidURL() async {
        let oidc = OIDCLite(discoveryURL: "http://[invalid", clientID: clientID)

        await #expect(throws: OIDCLiteError.unableToLoadEndpoint) {
            try await oidc.getEndpoints()
        }
    }

    @Test func loginURLContainsOIDCAndPKCEParameters() throws {
        let oidc = OIDCLite(discoveryURL: discoveryURL, clientID: clientID)
        let login = try oidc.createLoginURL(endpoints: endpoints())
        let items = try #require(URLComponents(url: login.url, resolvingAgainstBaseURL: false)?.queryItems)
        let query = Dictionary(uniqueKeysWithValues: items.compactMap { item in
            item.value.map { (item.name, $0) }
        })
        let expectedChallenge = Data(SHA256.hash(data: Data(login.codeVerifier.utf8)))
            .base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")

        #expect(query["client_id"] == clientID)
        #expect(query["response_type"] == "code")
        #expect(query["scope"] == "openid profile email offline_access")
        #expect(query["redirect_uri"] == "oidclite://openID")
        #expect(query["state"] == login.state)
        #expect(query["nonce"] == login.nonce)
        #expect(query["code_challenge_method"] == "S256")
        #expect(query["code_challenge"] == expectedChallenge)
    }

    @Test func loginValuesAreFreshPerRequest() throws {
        let oidc = OIDCLite(discoveryURL: discoveryURL, clientID: clientID)
        let first = try oidc.createLoginURL(endpoints: endpoints())
        let second = try oidc.createLoginURL(endpoints: endpoints())

        #expect(first.state != second.state)
        #expect(first.nonce != second.nonce)
        #expect(first.codeVerifier != second.codeVerifier)
    }

    @Test func responseRejectsMismatchedState() async throws {
        let oidc = OIDCLite(discoveryURL: discoveryURL, clientID: clientID)
        let login = try oidc.createLoginURL(endpoints: endpoints())
        let callback = try #require(URL(string: "oidclite://openID?code=code&state=wrong"))

        await #expect(throws: OIDCLiteError.stateMismatch) {
            try await oidc.processResponseURL(url: callback, login: login, endpoints: endpoints())
        }
    }

    @Test func responseExchangesCodeAndExtractsTokens() async throws {
        let body = try JSONSerialization.data(withJSONObject: [
            "access_token": "access",
            "id_token": "id",
            "refresh_token": "refresh",
            "expires_in": "3599",
            "token_type": "Bearer",
            "scope": "openid profile"
        ])
        let session = try StubURLProtocol.session(responses: [(response(status: 200), body)])
        let oidc = OIDCLite(discoveryURL: discoveryURL, clientID: clientID, session: session)
        let endpoints = endpoints()
        let login = try oidc.createLoginURL(endpoints: endpoints)
        var callback = URLComponents(string: "oidclite://openID")
        callback?.queryItems = [
            URLQueryItem(name: "code", value: "code"),
            URLQueryItem(name: "state", value: login.state)
        ]

        let tokens = try await oidc.processResponseURL(
            url: #require(callback?.url),
            login: login,
            endpoints: endpoints
        )

        #expect(tokens.accessToken == "access")
        #expect(tokens.idToken == "id")
        #expect(tokens.refreshToken == "refresh")
        #expect(tokens.expiresIn == 3599)
        #expect(tokens.tokenType == "Bearer")
        #expect(tokens.scope == "openid profile")
        #expect(StubURLProtocol.requests.count == 1)
    }

    private func endpoints() -> OIDCLite.Endpoints {
        OIDCLite.Endpoints(
            authorization: authEndpoint,
            token: tokenEndpoint,
            issuer: "https://example.com",
            jwksURI: URL(string: "https://example.com/keys")
        )
    }

    private func response(status: Int) throws -> HTTPURLResponse {
        try #require(HTTPURLResponse(
            url: URL(string: discoveryURL)!,
            statusCode: status,
            httpVersion: nil,
            headerFields: nil
        ))
    }
}
