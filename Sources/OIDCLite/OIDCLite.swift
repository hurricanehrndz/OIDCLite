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
public class OIDCLite {
    private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier!,
        category: "oidc"
    )

    public struct TokenResponse {
        public var accessToken: String?
        public var idToken: String?
        public var refreshToken: String?
        public var expiresIn: Int?
        public var tokenType: String
        public var scope: String?
        public var jsonDict: [String: Any]?

        public init(
            accessToken: String? = nil,
            idToken: String? = nil,
            refreshToken: String? = nil,
            expiresIn: Int? = nil,
            tokenType: String = "bearer",
            scope: String? = nil,
            jsonDict: [String: Any]? = nil
        ) {
            self.accessToken = accessToken
            self.idToken = idToken
            self.refreshToken = refreshToken
            self.expiresIn = expiresIn
            self.tokenType = tokenType
            self.scope = scope
            self.jsonDict = jsonDict
        }
    }

    // OpenID settings, supplied on init()

    public let discoveryURL: String
    public let redirectURI: String
    public let clientID: String
    public let scopes: [String]
    public let clientSecret: String?
    public let resource: String?
    public let additionalParameters: [String: String]?

    // OpenID endpoints, gathered from the discoveryURL

    public var OIDCAuthEndpoint: String?
    public var OIDCTokenEndpoint: String?

    // Used for PKCE, no need to be public

    var codeVerifier = (UUID().uuidString + UUID().uuidString)

    // URL Session bits, we make a new ephemeral session every time the class
    // is invoked to ensure no lingering cookies

    var session = URLSession(configuration: URLSessionConfiguration.ephemeral, delegate: nil, delegateQueue: nil)

    public private(set) var state: String?
    public private(set) var nonce: String?

    /// Create a new OIDCLite object
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
    public init(
        discoveryURL: String,
        clientID: String,
        clientSecret: String?,
        redirectURI: String?,
        scopes: [String]?,
        additionalParameters: [String: String]? = nil,
        resource: String? = nil
    ) {
        self.discoveryURL = discoveryURL
        self.clientID = clientID
        self.clientSecret = clientSecret
        self.redirectURI = redirectURI ?? "oidclite://openID"
        self.scopes = scopes ?? ["openid", "profile", "email", "offline_access"]
        self.additionalParameters = additionalParameters
        self.resource = resource
    }

    /// Generates the inital login URL which can be passed to ASWebAuthenticationSession
    /// - Returns: A URL to be used with ASWebAuthenticationSession
    public func createLoginURL() -> URL? {
        state = UUID().uuidString

        var queryItems: [URLQueryItem] = []

        let clientIdItem = URLQueryItem(name: "client_id", value: clientID)
        queryItems.append(clientIdItem)

        let responseTypeItem: URLQueryItem
        let scopeItem: URLQueryItem

        responseTypeItem = URLQueryItem(name: "response_type", value: "code")
        scopeItem = URLQueryItem(name: "scope", value: scopes.joined(separator: " "))

        queryItems.append(contentsOf: [responseTypeItem, scopeItem])

        if let additionalParameters = additionalParameters {
            for (key, value) in additionalParameters {
                let parameterItem = URLQueryItem(name: key, value: value)
                queryItems.append(contentsOf: [parameterItem])
            }
        }

        let redirectUriItem = URLQueryItem(name: "redirect_uri", value: redirectURI)
        queryItems.append(redirectUriItem)
        let stateItem = URLQueryItem(name: "state", value: state)
        queryItems.append(stateItem)

        if let challengeData = codeVerifier.data(using: String.Encoding.ascii) {
            let codeChallengeMethodItem = URLQueryItem(name: "code_challenge_method", value: "S256")
            let hash = SHA256.hash(data: challengeData)
            let challengeData = Data(hash)
            let challengeString = challengeData.base64EncodedString().base64URLEncoded()
            let codeChallengeItem = URLQueryItem(name: "code_challenge", value: challengeString)
            queryItems.append(contentsOf: [codeChallengeMethodItem, codeChallengeItem])
        }

        nonce = UUID().uuidString
        let nonceItem = URLQueryItem(name: "nonce", value: nonce)
        queryItems.append(nonceItem)

        guard let url = URL(string: OIDCAuthEndpoint ?? "") else {
            return nil
        }

        var urlComponents = URLComponents(url: url, resolvingAgainstBaseURL: false)
        urlComponents?.queryItems = queryItems
        return urlComponents?.url
    }

    func processOIDCResponse(_ data: Data) throws -> TokenResponse {
        var tokenResponse = TokenResponse()

        let jsonResult = try JSONSerialization.jsonObject(
            with: data,
            options: JSONSerialization.ReadingOptions.mutableContainers
        ) as? [String: Any]

        if let tokenType = jsonResult?["token_type"] as? String {
            tokenResponse.tokenType = tokenType
        }

        if let expires = jsonResult?["expires_in"] as? Int {
            tokenResponse.expiresIn = expires
        }

        if let expires = jsonResult?["expires_in"] as? String {
            tokenResponse.expiresIn = Int(expires)!
        }

        if let scope = jsonResult?["scope"] as? String {
            tokenResponse.scope = scope
        }

        if let accessToken = jsonResult?["access_token"] as? String {
            tokenResponse.accessToken = accessToken
        }

        if let refreshToken = jsonResult?["refresh_token"] as? String {
            tokenResponse.refreshToken = refreshToken
        }

        if let idToken = jsonResult?["id_token"] as? String {
            tokenResponse.idToken = idToken
        }
        tokenResponse.jsonDict = jsonResult

        return tokenResponse
    }

    /// Turn a code, returned from a successful ASWebAuthenticationSession, into a token set
    /// - Parameter code: the code generated by a successful authentication
    public func getToken(code: String, basicAuth: Bool = false) async throws -> TokenResponse {
        guard let path = OIDCTokenEndpoint else {
            throw OIDCLiteError.authFailure("No token endpoint found")
        }

        guard let tokenURL = URL(string: path) else {
            throw OIDCLiteError.authFailure("Unable to make the token endpoint into a URL")
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

        body.append("&redirect_uri=" + redirectURI.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed)!)
        let codeParam = "&code=" + code

        body.append(codeParam)
        body.append("&code_verifier=" + codeVerifier)

        var req = URLRequest(url: tokenURL)
        req.httpMethod = "POST"
        req.httpBody = body.data(using: .utf8)

        req.allHTTPHeaderFields = headers

        let (data, response) = try await URLSession.shared.data(for: req)

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

    /// Function to parse the openid-configuration file into all of the requisite endpoints
    /// Function to async parse the openid-configuration file into all of the requisite endpoints
    public func getEndpoints() async throws {
        // make sure we can actually make a URL from the discoveryURL that we have
        guard let host = URL(string: discoveryURL) else { return }
        var req = URLRequest(url: host)

        let headers = [
            "Accept": "application/json",
            "Cache-Control": "no-cache"
        ]

        req.allHTTPHeaderFields = headers
        req.httpMethod = "GET"
        let (data, response) = try await session.data(for: req)
        if let response = response as? HTTPURLResponse,
           (200 ... 228).contains(response.statusCode) {
            if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] {
                OIDCAuthEndpoint = json["authorization_endpoint"] as? String ?? ""
                OIDCTokenEndpoint = json["token_endpoint"] as? String ?? ""
            } else {
                throw OIDCLiteError.unableToParseEndpoint
            }
        } else {
            throw OIDCLiteError.unableToLoadEndpoint
        }
    }

    /// Parse the response  from a redirect with a possible code in it.
    /// - Parameter url: redirect URL
    public func processResponseURL(url: URL) throws {
        if let query = url.query {
            let items = query.components(separatedBy: "&")
            for item in items where item.starts(with: "code=") {
                Task {
                    try await getToken(code: item.replacingOccurrences(of: "code=", with: ""))
                }
                return
            }
        }
        throw OIDCLiteError.unableToFindCode
    }

    public func refreshTokens(_ refreshToken: String) async throws -> TokenResponse {
        var parameters = "grant_type=refresh_token&refresh_token=\(refreshToken)&client_id=\(clientID)"
        if let clientSecret = clientSecret {
            parameters.append("&client_secret=\(clientSecret)")
        }

        let postData = parameters.data(using: .utf8)

        guard let path = OIDCTokenEndpoint else {
            throw OIDCLiteError.authFailure("No token endpoint found")
        }

        guard let tokenURL = URL(string: path) else {
            throw OIDCLiteError.authFailure("Unable to make the token endpoint into a URL")
        }

        var req = URLRequest(url: tokenURL)

        req.addValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")

        req.httpMethod = "POST"
        req.httpBody = postData

        let (data, _) = try await URLSession.shared.data(for: req)

        return try processOIDCResponse(data)
    }

    // ROPG intentionally handles many auth/error branches in one place; the size
    // and complexity limits are relaxed for this single method rather than split
    // the flow across helpers.
    // swiftlint:disable:next cyclomatic_complexity function_body_length
    public func requestTokenWithROPG(
        username: String,
        password: String,
        basicAuth: Bool,
        overrideErrors: [String]?
    ) async throws -> TokenResponse? {
        guard let urlString = OIDCTokenEndpoint, let url = URL(string: urlString) else {
            throw OIDCLiteError.unableToLoadEndpoint
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
        if let encodedResource = encodedResource {
            queryItems.append(URLQueryItem(name: "resource", value: encodedResource))
        }
        if !basicAuth {
            queryItems.append(URLQueryItem(name: "client_id", value: clientID))
            if let clientSecret = clientSecret {
                queryItems.append(URLQueryItem(name: "client_secret", value: clientSecret))
            }
        } else {
            var loginString = clientID
            if let clientSecret = clientSecret {
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

        let (data, response) = try await URLSession.shared.data(for: req)

        var responseCode = 0
        if let response = response as? HTTPURLResponse {
            responseCode = response.statusCode
        }
        if let response = response as? HTTPURLResponse,
           (200 ... 228).contains(response.statusCode) {
            return try processOIDCResponse(data)
        } else if let response = response as? HTTPURLResponse,
                  (400 ... 403).contains(response.statusCode),
                  let overrideErrors = overrideErrors,
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
