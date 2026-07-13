import Foundation
import OIDCLite
import Testing

@Suite(.serialized, .enabled(if: ProcessInfo.processInfo.environment["DEX_ISSUER"] != nil))
struct OIDCLiteIntegrationTests {
    private let clientID = "oidclite-test"
    private let clientSecret = "oidclite-secret"
    private let username = "admin@example.com"
    private let password = "password"

    @Test func discoveryPopulatesAuthorizationAndTokenEndpoints() async throws {
        let (_, endpoints) = try await configuredOIDC()

        #expect(endpoints.authorization != nil)
        #expect(endpoints.token != nil)
    }

    @Test func ropgReturnsAccessAndRefreshTokens() async throws {
        let (oidc, endpoints) = try await configuredOIDC()
        let tokens = try await passwordTokens(from: oidc, endpoints: endpoints)

        #expect(tokens.accessToken != nil)
        #expect(tokens.refreshToken != nil)
    }

    @Test func ropgRejectsWrongPassword() async throws {
        let (oidc, endpoints) = try await configuredOIDC()
        var rejected = false

        do {
            _ = try await oidc.requestTokenWithROPG(
                username: username,
                password: "wrong-password",
                endpoints: endpoints
            )
        } catch {
            rejected = true
        }

        #expect(rejected, "dex accepted an invalid password")
    }

    @Test func refreshTokenRefreshesSuccessfully() async throws {
        let (oidc, endpoints) = try await configuredOIDC()
        let initialTokens = try await passwordTokens(from: oidc, endpoints: endpoints)
        let refreshToken = try #require(initialTokens.refreshToken)
        let refreshedTokens = try await oidc.refreshTokens(refreshToken, endpoints: endpoints)

        #expect(refreshedTokens.accessToken != nil)
        #expect(refreshedTokens.refreshToken != nil)
    }

    @Test func authorizationCodeFlowExchangesCodeWithPKCE() async throws {
        let (oidc, endpoints) = try await configuredOIDC()
        let login = try oidc.createLoginURL(endpoints: endpoints)
        let delegate = CallbackDelegate()
        let session = URLSession(configuration: .ephemeral, delegate: delegate, delegateQueue: nil)
        defer { session.invalidateAndCancel() }

        let (loginPage, response) = try await session.data(for: URLRequest(url: login.url))
        let html = try #require(String(data: loginPage, encoding: .utf8))
        let action = try #require(
            html.components(separatedBy: "action=\"").dropFirst().first?.components(separatedBy: "\"").first
        )
        let loginEndpoint = try #require(
            URL(string: action.replacingOccurrences(of: "&amp;", with: "&"), relativeTo: response.url)
        )

        var form = URLComponents()
        form.queryItems = [
            URLQueryItem(name: "login", value: username),
            URLQueryItem(name: "password", value: password)
        ]
        var request = URLRequest(url: loginEndpoint)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = try #require(form.percentEncodedQuery?.data(using: .utf8))
        delegate.captureNextRedirect = true
        _ = try await session.data(for: request)

        let callback = try #require(delegate.callbackURL)
        let tokens = try await oidc.processResponseURL(url: callback, login: login, endpoints: endpoints)

        #expect(tokens.accessToken != nil)
        #expect(tokens.refreshToken != nil)
    }

    private func configuredOIDC() async throws -> (OIDCLite, OIDCLite.Endpoints) {
        let issuer = try #require(ProcessInfo.processInfo.environment["DEX_ISSUER"])
        let oidc = OIDCLite(
            discoveryURL: "\(issuer)/.well-known/openid-configuration",
            clientID: clientID,
            clientSecret: clientSecret
        )
        return try await (oidc, oidc.getEndpoints())
    }

    private func passwordTokens(
        from oidc: OIDCLite,
        endpoints: OIDCLite.Endpoints
    ) async throws -> OIDCLite.TokenResponse {
        let tokens = try await oidc.requestTokenWithROPG(
            username: username,
            password: password,
            endpoints: endpoints
        )
        return try #require(tokens)
    }
}

private final class CallbackDelegate: NSObject, URLSessionTaskDelegate {
    var captureNextRedirect = false
    private(set) var callbackURL: URL?

    func urlSession(
        _: URLSession,
        task _: URLSessionTask,
        willPerformHTTPRedirection _: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping (URLRequest?) -> Void
    ) {
        if captureNextRedirect {
            callbackURL = request.url
            completionHandler(nil)
            return
        }
        completionHandler(request)
    }
}
