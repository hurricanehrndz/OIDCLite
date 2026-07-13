import OIDCLite
import XCTest

final class OIDCLiteTests: XCTestCase {
    // mock data

    let discoveryURL = "https://example.com/.well-known/openid-configuration"
    let clientID = "BC76BE32-289C-4A56-B5F2-ACAB2B695EDB"
    let clientSecret = "BBA8C549-49BB-49D6-A835-C9372C36C32F"
    let authEndpoint = "https://example.com/oauth/v2/auth"

    func testInitWithoutClientSecret() {
        let oidc = OIDCLite(
            discoveryURL: discoveryURL,
            clientID: clientID,
            clientSecret: nil,
            redirectURI: nil,
            scopes: nil
        )

        XCTAssert(oidc.discoveryURL == discoveryURL, "Failure to set DiscoveryURL")

        XCTAssert(oidc.clientID == clientID, "Failure to set ClientID")
    }

    func testInitWithClientSecret() {
        let oidc = OIDCLite(
            discoveryURL: discoveryURL,
            clientID: clientID,
            clientSecret: clientSecret,
            redirectURI: nil,
            scopes: nil
        )

        XCTAssert(oidc.discoveryURL == discoveryURL, "Failure to set DiscoveryURL")

        XCTAssert(oidc.clientID == clientID, "Failure to set ClientID")

        XCTAssert(oidc.clientSecret == clientSecret, "Failure to set ClientSecret")
    }

    func testInitAndGenerateLoginURL() {
        let oidc = OIDCLite(
            discoveryURL: discoveryURL,
            clientID: clientID,
            clientSecret: nil,
            redirectURI: nil,
            scopes: nil
        )

        // set a mock endpoint for the auth endpoint

        oidc.OIDCAuthEndpoint = authEndpoint

        if let url = oidc.createLoginURL() {
            let queryItems = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems

            XCTAssertEqual(queryItems?.first { $0.name == "state" }?.value, oidc.state)
            XCTAssertEqual(queryItems?.first { $0.name == "nonce" }?.value, oidc.nonce)
            XCTAssertNotNil(oidc.state)
            XCTAssertNotNil(oidc.nonce)

            XCTAssert(url.isFileURL == false, "Login URL is File URL")

            XCTAssert({
                if url.host != "example.com" {
                    return false
                }
                if !url.pathComponents.contains("v2") {
                    return false
                }
                return true
            }(), "Unable to use LoginURL")

        } else {
            XCTFail("createLoginURL() returned nil")
        }
    }
}
