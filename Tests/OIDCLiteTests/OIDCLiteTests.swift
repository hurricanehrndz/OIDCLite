import Foundation
import OIDCLite
import Testing

struct OIDCLiteTests {
    // mock data

    let discoveryURL = "https://example.com/.well-known/openid-configuration"
    let clientID = "BC76BE32-289C-4A56-B5F2-ACAB2B695EDB"
    let clientSecret = "BBA8C549-49BB-49D6-A835-C9372C36C32F"
    let authEndpoint = "https://example.com/oauth/v2/auth"

    @Test func initWithoutClientSecret() {
        let oidc = OIDCLite(
            discoveryURL: discoveryURL,
            clientID: clientID,
            clientSecret: nil,
            redirectURI: nil,
            scopes: nil
        )

        #expect(oidc.discoveryURL == discoveryURL, "Failure to set DiscoveryURL")

        #expect(oidc.clientID == clientID, "Failure to set ClientID")
    }

    @Test func initWithClientSecret() {
        let oidc = OIDCLite(
            discoveryURL: discoveryURL,
            clientID: clientID,
            clientSecret: clientSecret,
            redirectURI: nil,
            scopes: nil
        )

        #expect(oidc.discoveryURL == discoveryURL, "Failure to set DiscoveryURL")

        #expect(oidc.clientID == clientID, "Failure to set ClientID")

        #expect(oidc.clientSecret == clientSecret, "Failure to set ClientSecret")
    }

    @Test func initAndGenerateLoginURL() throws {
        let oidc = OIDCLite(
            discoveryURL: discoveryURL,
            clientID: clientID,
            clientSecret: nil,
            redirectURI: nil,
            scopes: nil
        )

        // set a mock endpoint for the auth endpoint

        oidc.OIDCAuthEndpoint = authEndpoint

        let url = try #require(oidc.createLoginURL(), "createLoginURL() returned nil")
        let queryItems = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems

        #expect(queryItems?.first { $0.name == "state" }?.value == oidc.state)
        #expect(queryItems?.first { $0.name == "nonce" }?.value == oidc.nonce)
        #expect(oidc.state != nil)
        #expect(oidc.nonce != nil)

        #expect(url.isFileURL == false, "Login URL is File URL")

        #expect({
            if url.host != "example.com" {
                return false
            }
            if !url.pathComponents.contains("v2") {
                return false
            }
            return true
        }(), "Unable to use LoginURL")
    }
}
