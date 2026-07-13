import CryptoKit
import Foundation
import os.log

// This library is intentionally a single-file implementation; suppress the file
// size limit rather than split the published API (the main type is likewise
// suppressed at its declaration).
// swiftlint:disable file_length

extension CharacterSet {
    static let urlQueryValueAllowed: CharacterSet = {
        // https://developer.mozilla.org/en-US/docs/Web/JavaScript/Reference/Global_Objects/encodeURIComponent
        // https://url.spec.whatwg.org/#concept-urlencoded
        // A-z0-9 and '*.-_' are allowed
        let generalDelimitersToEncode = ":#[]@?/"
        let subDelimitersToEncode = "!$&'()+,;=~"

        var allowed = CharacterSet.urlQueryAllowed
        allowed.remove(charactersIn: "\(generalDelimitersToEncode)\(subDelimitersToEncode)")
        // replace space with + afterwards
        allowed.insert(charactersIn: " ")
        return allowed
    }()
}

// Large by design: this is the library's single public type.
// swiftlint:disable:next type_body_length
public struct OIDCLite: Sendable {
    private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "OIDCLite",
        category: "oidc"
    )

    public struct Endpoints: Sendable {
        public let authorization: URL?
        public let token: URL?
        public let issuer: String?
        public let jwksURI: URL?
    }

    public struct LoginRequest: Sendable {
        public let url: URL
        public let state: String
        public let nonce: String
        public let codeVerifier: String
    }

    public struct TokenResponse: Sendable {
        public let accessToken: String?
        public let idToken: String?
        public let refreshToken: String?
        public let expiresIn: Int?
        public let tokenType: String
        public let scope: String?

        public init(
            accessToken: String? = nil,
            idToken: String? = nil,
            refreshToken: String? = nil,
            expiresIn: Int? = nil,
            tokenType: String = "bearer",
            scope: String? = nil
        ) {
            self.accessToken = accessToken
            self.idToken = idToken
            self.refreshToken = refreshToken
            self.expiresIn = expiresIn
            self.tokenType = tokenType
            self.scope = scope
        }
    }

    public let discoveryURL: String
    public let redirectURI: String
    public let clientID: String
    public let scopes: [String]
    public let clientSecret: String?
    public let resource: String?
    public let additionalParameters: [String: String]?
    let session: URLSession

    /// Create a new OIDCLite value.
    /// - Parameters:
    ///   - discoveryURL: the full well-known openid-configuration URL,
    ///     e.g. https://my.idp.com/.well-known/openid-configuration
    ///   - clientID: the OpenID Connect client ID to be used
    ///   - clientSecret: optional OpenID Connect client secret
    ///   - redirectURI: optional redirect URI, can not be http or https.
    ///     Defaults to "oidclite://openID" if nothing is supplied
    ///   - scopes: optional custom scopes to be used in the OpenID Connect request.
    ///     If nothing is supplied ["openid", "profile", "email", "offline_access"] will be used
    ///   - additionalParameters: optional additional parameters for the authorization request
    ///   - resource: optional resource for the resource owner password grant request
    ///   - session: URL session used for every network request
    public init(
        discoveryURL: String,
        clientID: String,
        clientSecret: String? = nil,
        redirectURI: String? = nil,
        scopes: [String]? = nil,
        additionalParameters: [String: String]? = nil,
        resource: String? = nil,
        session: URLSession = URLSession(configuration: .ephemeral)
    ) {
        self.discoveryURL = discoveryURL
        self.clientID = clientID
        self.clientSecret = clientSecret
        self.redirectURI = redirectURI ?? "oidclite://openID"
        self.scopes = scopes ?? ["openid", "profile", "email", "offline_access"]
        self.additionalParameters = additionalParameters
        self.resource = resource
        self.session = session
    }

    /// Generates the initial login URL which can be passed to ASWebAuthenticationSession.
    public func createLoginURL(endpoints: Endpoints) throws -> LoginRequest {
        guard let authorizationURL = endpoints.authorization else {
            throw OIDCLiteError.missingEndpoint("authorization_endpoint")
        }

        let state = UUID().uuidString
        let nonce = UUID().uuidString
        let codeVerifier = UUID().uuidString + UUID().uuidString
        let hash = SHA256.hash(data: Data(codeVerifier.utf8))
        let challenge = Data(hash).base64EncodedString().base64URLEncoded()

        var queryItems = [
            URLQueryItem(name: "client_id", value: clientID),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "scope", value: scopes.joined(separator: " "))
        ]

        if let additionalParameters {
            for (key, value) in additionalParameters {
                queryItems.append(URLQueryItem(name: key, value: value))
            }
        }

        queryItems.append(contentsOf: [
            URLQueryItem(name: "redirect_uri", value: redirectURI),
            URLQueryItem(name: "state", value: state),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
            URLQueryItem(name: "code_challenge", value: challenge),
            URLQueryItem(name: "nonce", value: nonce)
        ])

        var components = URLComponents(url: authorizationURL, resolvingAgainstBaseURL: false)
        components?.queryItems = queryItems
        guard let url = components?.url else {
            throw OIDCLiteError.missingEndpoint("authorization_endpoint")
        }
        return LoginRequest(url: url, state: state, nonce: nonce, codeVerifier: codeVerifier)
    }

    func processOIDCResponse(_ data: Data) throws -> TokenResponse {
        let jsonResult = try JSONSerialization.jsonObject(
            with: data,
            options: JSONSerialization.ReadingOptions.mutableContainers
        ) as? [String: Any]

        let expiresIn: Int?
        if let expires = jsonResult?["expires_in"] as? Int {
            expiresIn = expires
        } else if let expires = jsonResult?["expires_in"] as? String {
            expiresIn = Int(expires)
        } else {
            expiresIn = nil
        }

        return TokenResponse(
            accessToken: jsonResult?["access_token"] as? String,
            idToken: jsonResult?["id_token"] as? String,
            refreshToken: jsonResult?["refresh_token"] as? String,
            expiresIn: expiresIn,
            tokenType: jsonResult?["token_type"] as? String ?? "bearer",
            scope: jsonResult?["scope"] as? String
        )
    }

    /// Turn a code, returned from a successful ASWebAuthenticationSession, into a token set.
    public func getToken(
        code: String,
        codeVerifier: String?,
        endpoints: Endpoints,
        basicAuth: Bool = false
    ) async throws -> TokenResponse {
        guard let tokenURL = endpoints.token else {
            throw OIDCLiteError.missingEndpoint("token_endpoint")
        }
        var body = "grant_type=authorization_code"
        var headers = [
            "Accept": "application/json",
            "Content-Type": "application/x-www-form-urlencoded"
        ]

        body.append("&client_id=" + clientID)

        if let secret = clientSecret {
            if basicAuth {
                headers["Authorization"] = "Basic "
                    + ((clientID + ":" + secret).data(using: .utf8)?.base64EncodedString() ?? "")
            } else {
                body.append("&client_secret=" + secret)
            }
        }

        let encodedRedirectURI = redirectURI
            .addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? redirectURI
        body.append("&redirect_uri=" + encodedRedirectURI)
        body.append("&code=" + code)
        if let codeVerifier {
            body.append("&code_verifier=" + codeVerifier)
        }

        var req = URLRequest(url: tokenURL)
        req.httpMethod = "POST"
        req.httpBody = body.data(using: .utf8)
        req.allHTTPHeaderFields = headers

        let (data, response) = try await session.data(for: req)

        if let response = response as? HTTPURLResponse,
           response.statusCode == 200 {
            return try processOIDCResponse(data)
        } else {
            do {
                if let jsonResult = try JSONSerialization.jsonObject(
                    with: data,
                    options: JSONSerialization.ReadingOptions.mutableContainers
                ) as? [String: Any] {
                    throw OIDCLiteError.authFailure(prettyPrintInfo(dict: jsonResult))
                }
                throw OIDCLiteError.authFailure(response.debugDescription)
            }
        }
    }

    /// Parse the openid-configuration document into endpoints.
    public func getEndpoints() async throws -> Endpoints {
        guard let host = URL(string: discoveryURL) else {
            throw OIDCLiteError.unableToLoadEndpoint
        }
        var req = URLRequest(url: host)
        req.allHTTPHeaderFields = [
            "Accept": "application/json",
            "Cache-Control": "no-cache"
        ]
        req.httpMethod = "GET"

        let (data, response) = try await session.data(for: req)
        guard let response = response as? HTTPURLResponse,
              (200 ..< 300).contains(response.statusCode) else {
            throw OIDCLiteError.unableToLoadEndpoint
        }
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw OIDCLiteError.unableToParseEndpoint
        }

        return Endpoints(
            authorization: (json["authorization_endpoint"] as? String).flatMap(URL.init(string:)),
            token: (json["token_endpoint"] as? String).flatMap(URL.init(string:)),
            issuer: json["issuer"] as? String,
            jwksURI: (json["jwks_uri"] as? String).flatMap(URL.init(string:))
        )
    }

    /// Parse an authorization redirect and exchange its code for tokens.
    public func processResponseURL(
        url: URL,
        login: LoginRequest,
        endpoints: Endpoints,
        basicAuth: Bool = false
    ) async throws -> TokenResponse {
        let queryItems = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems
        guard queryItems?.first(where: { $0.name == "state" })?.value == login.state else {
            throw OIDCLiteError.stateMismatch
        }
        guard let code = queryItems?.first(where: { $0.name == "code" })?.value else {
            throw OIDCLiteError.unableToFindCode
        }
        return try await getToken(
            code: code,
            codeVerifier: login.codeVerifier,
            endpoints: endpoints,
            basicAuth: basicAuth
        )
    }

    public func refreshTokens(_ refreshToken: String, endpoints: Endpoints) async throws -> TokenResponse {
        var parameters = "grant_type=refresh_token&refresh_token=\(refreshToken)&client_id=\(clientID)"
        if let clientSecret {
            parameters.append("&client_secret=\(clientSecret)")
        }

        guard let tokenURL = endpoints.token else {
            throw OIDCLiteError.missingEndpoint("token_endpoint")
        }

        var req = URLRequest(url: tokenURL)
        req.addValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        req.httpMethod = "POST"
        req.httpBody = parameters.data(using: .utf8)

        let (data, _) = try await session.data(for: req)
        return try processOIDCResponse(data)
    }

    // ROPG intentionally handles many auth/error branches in one place; the size
    // and complexity limits are relaxed for this single method rather than split
    // the flow across helpers.
    // swiftlint:disable:next cyclomatic_complexity function_body_length
    public func requestTokenWithROPG(
        username: String,
        password: String,
        endpoints: Endpoints,
        basicAuth: Bool = false,
        overrideErrors: [String]? = nil
    ) async throws -> TokenResponse? {
        guard let url = endpoints.token else {
            throw OIDCLiteError.missingEndpoint("token_endpoint")
        }
        var req = URLRequest(url: url)

        var headers = [
            "Accept": "application/json",
            "Cache-Control": "no-cache",
            "Content-Type": "application/x-www-form-urlencoded"
        ]

        let scopesURLString = scopes.joined(separator: " ")
            .addingPercentEncoding(withAllowedCharacters: .urlQueryValueAllowed)?
            .replacingOccurrences(of: " ", with: "+")
        let encodedUsername = username
            .addingPercentEncoding(withAllowedCharacters: .urlQueryValueAllowed)?
            .replacingOccurrences(of: " ", with: "+")
        let encodedPassword = password
            .addingPercentEncoding(withAllowedCharacters: .urlQueryValueAllowed)?
            .replacingOccurrences(of: " ", with: "+")

        var reqComponents = URLComponents()
        var queryItems = [
            URLQueryItem(name: "grant_type", value: "password"),
            URLQueryItem(name: "scope", value: scopesURLString),
            URLQueryItem(name: "username", value: encodedUsername),
            URLQueryItem(name: "password", value: encodedPassword)
        ]

        let encodedResource = resource?
            .addingPercentEncoding(withAllowedCharacters: .urlQueryValueAllowed)?
            .replacingOccurrences(of: " ", with: "+")
        if let encodedResource {
            queryItems.append(URLQueryItem(name: "resource", value: encodedResource))
        }
        if !basicAuth {
            queryItems.append(URLQueryItem(name: "client_id", value: clientID))
            if let clientSecret {
                queryItems.append(URLQueryItem(name: "client_secret", value: clientSecret))
            }
        } else {
            var loginString = clientID
            if let clientSecret {
                loginString.append(":" + clientSecret)
            }
            if let data = loginString.data(using: .utf8) {
                headers["Authorization"] = "Basic " + data.base64EncodedString()
            } else {
                throw OIDCLiteError.authFailure("bad login info")
            }
        }

        reqComponents.queryItems = queryItems
        req.allHTTPHeaderFields = headers
        req.httpMethod = "POST"
        req.httpBody = reqComponents.query?.data(using: .utf8)

        let (data, response) = try await session.data(for: req)

        var responseCode = 0
        if let response = response as? HTTPURLResponse {
            responseCode = response.statusCode
        }
        if let response = response as? HTTPURLResponse,
           (200 ... 228).contains(response.statusCode) {
            return try processOIDCResponse(data)
        } else if let response = response as? HTTPURLResponse,
                  (400 ... 403).contains(response.statusCode),
                  let overrideErrors,
                  let errorMessage = String(data: data, encoding: .utf8) {
            var success = false
            for overrideError in overrideErrors where errorMessage.contains(overrideError) {
                success = true
                break
            }
            if success {
                // no token to to give back but it isn't an error
                // because we got a 400 response with a match that says
                // it is ok. This is because ROPG can require MFA but
                // we don't care about anything except that the username/password
                // was good. So returning nil means no tokens but not an error
                // (we would throw if there was an error)
                return nil
            } else {
                throw OIDCLiteError.authFailure(
                    "Status code:\(responseCode), Did not match override:"
                        + (String(data: data, encoding: .utf8) ?? "Unknown error")
                )
            }
        } else {
            throw OIDCLiteError.authFailure(
                "Status code:\(responseCode), Not 400, no override, or bad error message:"
                    + (String(data: data, encoding: .utf8) ?? "Unknown error")
            )
        }
    }

    private func prettyPrintInfo(dict: [String: Any]) -> String {
        var result = ""

        for item in dict {
            result.append("\(item.key):  ")
            result.append(String(describing: item.value))
            result.append("\n")
        }

        return result
    }
}
