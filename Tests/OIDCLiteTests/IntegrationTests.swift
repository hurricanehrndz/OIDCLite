import Foundation
import OIDCLite
import XCTest

@available(macOS 11.0, *)
final class OIDCLiteIntegrationTests: XCTestCase {
    private let clientID = "oidclite-test"
    private let clientSecret = "oidclite-secret"
    private let username = "admin@example.com"
    private let password = "password"

    func testDiscoveryPopulatesAuthorizationAndTokenEndpoints() async throws {
        let oidc = try await configuredOIDC()

        XCTAssertNotNil(oidc.OIDCAuthEndpoint)
        XCTAssertNotNil(oidc.OIDCTokenEndpoint)
    }

    func testROPGReturnsAccessAndRefreshTokens() async throws {
        let oidc = try await configuredOIDC()
        let tokens = try await passwordTokens(from: oidc)

        XCTAssertNotNil(tokens.accessToken)
        XCTAssertNotNil(tokens.refreshToken)
    }

    func testROPGRejectsWrongPassword() async throws {
        let oidc = try await configuredOIDC()

        do {
            _ = try await oidc.requestTokenWithROPG(
                username: username,
                password: "wrong-password",
                basicAuth: false,
                overrideErrors: nil
            )
            XCTFail("dex accepted an invalid password")
        } catch {
            // Any thrown error is the current API's rejection contract.
        }
    }

    func testRefreshTokenRefreshesSuccessfully() async throws {
        let oidc = try await configuredOIDC()
        let initialTokens = try await passwordTokens(from: oidc)
        let refreshToken = try XCTUnwrap(initialTokens.refreshToken)
        let refreshedTokens = try await oidc.refreshTokens(refreshToken)

        XCTAssertNotNil(refreshedTokens.accessToken)
        XCTAssertNotNil(refreshedTokens.refreshToken)
    }

    func testAuthorizationCodeFlowExchangesCodeWithPKCE() async throws {
        let oidc = try await configuredOIDC()
        let loginURL = try XCTUnwrap(oidc.createLoginURL())
        let delegate = CallbackDelegate()
        let session = URLSession(configuration: .ephemeral, delegate: delegate, delegateQueue: nil)
        defer { session.invalidateAndCancel() }

        let (loginPage, response) = try await session.data(for: URLRequest(url: loginURL))
        let html = try XCTUnwrap(String(data: loginPage, encoding: .utf8))
        let action = try XCTUnwrap(
            html.components(separatedBy: "action=\"").dropFirst().first?.components(separatedBy: "\"").first
        )
        let loginEndpoint = try XCTUnwrap(
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
        request.httpBody = try XCTUnwrap(form.percentEncodedQuery?.data(using: .utf8))
        delegate.captureNextRedirect = true
        _ = try await session.data(for: request)

        let callback = try XCTUnwrap(delegate.callbackURL)
        let code = try XCTUnwrap(
            URLComponents(url: callback, resolvingAgainstBaseURL: false)?
                .queryItems?.first { $0.name == "code" }?.value
        )
        let tokens = try await oidc.getToken(code: code)

        XCTAssertNotNil(tokens.accessToken)
        XCTAssertNotNil(tokens.refreshToken)
    }

    private func configuredOIDC() async throws -> OIDCLite {
        guard let issuer = ProcessInfo.processInfo.environment["DEX_ISSUER"] else {
            throw XCTSkip("DEX_ISSUER is not set")
        }

        let oidc = OIDCLite(
            discoveryURL: "\(issuer)/.well-known/openid-configuration",
            clientID: clientID,
            clientSecret: clientSecret,
            redirectURI: nil,
            scopes: nil
        )
        try await oidc.getEndpoints()
        return oidc
    }

    private func passwordTokens(from oidc: OIDCLite) async throws -> OIDCLite.TokenResponse {
        let tokens = try await oidc.requestTokenWithROPG(
            username: username,
            password: password,
            basicAuth: false,
            overrideErrors: nil
        )
        return try XCTUnwrap(tokens)
    }
}

@available(macOS 11.0, *)
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
