import CryptoKit
import Foundation
@testable import OIDCLite
import Testing

@Suite(.serialized)
// swiftlint:disable:next type_body_length
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

    @Test func formEncodingFollowsURLStandard() {
        let vectors = [
            ("key", "AZaz09*-._", "key=AZaz09*-._"),
            ("key", " ", "key=+"),
            ("key", "\r", "key=%0D%0A"),
            ("key", "\n", "key=%0D%0A"),
            ("key", "\r\n", "key=%0D%0A"),
            ("key", "+&=%", "key=%2B%26%3D%25"),
            ("key", "é", "key=%C3%A9"),
            ("hostile+&=% name", "value", "hostile%2B%26%3D%25+name=value")
        ]

        for (name, value, expected) in vectors {
            let body = OIDCLite.formEncodedBody([(name, value)])
            #expect(String(data: body, encoding: .utf8) == expected)
        }
    }

    @Test func tokenRequestsEncodeHostileValuesExactlyOnce() async throws {
        let success = Data("{}".utf8)
        let session = try StubURLProtocol.session(responses: [
            (response(status: 201), success),
            (response(status: 202), success),
            (response(status: 299), success)
        ])
        let oidc = OIDCLite(
            discoveryURL: discoveryURL,
            clientID: "client",
            clientSecret: "p+s&s=w%rd",
            scopes: ["openid", "custom scope"],
            session: session
        )

        _ = try await oidc.getToken(
            code: "code+&=%",
            codeVerifier: "verify value+",
            endpoints: endpoints()
        )
        _ = try await oidc.refreshTokens("refresh+&=%", endpoints: endpoints())
        _ = try await oidc.requestTokenWithROPG(
            username: "user@example.com",
            password: "pass word+1",
            endpoints: endpoints()
        )

        let authorizationCodeBody = [
            "grant_type=authorization_code",
            "client_id=client",
            "client_secret=p%2Bs%26s%3Dw%25rd",
            "redirect_uri=oidclite%3A%2F%2FopenID",
            "code=code%2B%26%3D%25",
            "code_verifier=verify+value%2B"
        ].joined(separator: "&")
        let refreshBody = [
            "grant_type=refresh_token",
            "refresh_token=refresh%2B%26%3D%25",
            "client_id=client",
            "client_secret=p%2Bs%26s%3Dw%25rd"
        ].joined(separator: "&")
        let passwordBody = [
            "grant_type=password",
            "scope=openid+custom+scope",
            "username=user%40example.com",
            "password=pass+word%2B1",
            "client_id=client",
            "client_secret=p%2Bs%26s%3Dw%25rd"
        ].joined(separator: "&")

        #expect(requestBody(at: 0) == authorizationCodeBody)
        #expect(requestBody(at: 1) == refreshBody)
        #expect(requestBody(at: 2) == passwordBody)
    }

    @Test func basicAuthOmitsSecretFromTokenRequestBodies() async throws {
        let success = Data("{}".utf8)
        let session = try StubURLProtocol.session(responses: [
            (response(status: 200), success),
            (response(status: 200), success)
        ])
        let oidc = OIDCLite(
            discoveryURL: discoveryURL,
            clientID: "client",
            clientSecret: "p+s&s=w%rd",
            session: session
        )

        _ = try await oidc.getToken(
            code: "code",
            codeVerifier: nil,
            endpoints: endpoints(),
            basicAuth: true
        )
        _ = try await oidc.refreshTokens("refresh", endpoints: endpoints(), basicAuth: true)

        let authorization = "Basic " + Data("client:p+s&s=w%rd".utf8).base64EncodedString()
        #expect(StubURLProtocol.requests[0].value(forHTTPHeaderField: "Authorization") == authorization)
        #expect(StubURLProtocol.requests[1].value(forHTTPHeaderField: "Authorization") == authorization)
        #expect(requestBody(at: 0) == [
            "grant_type=authorization_code",
            "client_id=client",
            "redirect_uri=oidclite%3A%2F%2FopenID",
            "code=code"
        ].joined(separator: "&"))
        #expect(requestBody(at: 1) == "grant_type=refresh_token&refresh_token=refresh&client_id=client")
    }

    @Test func refreshThrowsTypedOAuthError() async throws {
        let body = Data(#"{"error":"invalid_grant"}"#.utf8)
        let session = try StubURLProtocol.session(responses: [(response(status: 400), body)])
        let oidc = OIDCLite(discoveryURL: discoveryURL, clientID: clientID, session: session)

        await #expect(throws: OIDCLiteError.oauthError(
            code: "invalid_grant",
            description: nil,
            httpStatus: 400
        )) {
            try await oidc.refreshTokens("garbage", endpoints: endpoints())
        }
    }

    @Test func ropgPreservesRawBodyOverrideMatching() async throws {
        let body = Data(
            #"{"error":"invalid_grant","error_description":"AADSTS50076: multi-factor authentication required"}"#.utf8
        )
        let session = try StubURLProtocol.session(responses: [
            (response(status: 400), body),
            (response(status: 400), body)
        ])
        let oidc = OIDCLite(discoveryURL: discoveryURL, clientID: clientID, session: session)

        let overridden = try await oidc.requestTokenWithROPG(
            username: "user",
            password: "password",
            endpoints: endpoints(),
            overrideErrors: ["AADSTS50076"]
        )
        #expect(overridden == nil)

        await #expect(throws: OIDCLiteError.oauthError(
            code: "invalid_grant",
            description: "AADSTS50076: multi-factor authentication required",
            httpStatus: 400
        )) {
            try await oidc.requestTokenWithROPG(
                username: "user",
                password: "password",
                endpoints: endpoints(),
                overrideErrors: ["AADSTS50079"]
            )
        }
    }

    private func requestBody(at index: Int) -> String? {
        StubURLProtocol.requests[index].httpBody.flatMap { String(data: $0, encoding: .utf8) }
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
