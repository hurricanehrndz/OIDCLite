# Resource owner password grant

Call `requestTokenWithROPG(username:password:endpoints:basicAuth:overrideErrors:)` to request tokens with a username and password. It returns `OIDCLite.TokenResponse` on success and requires the discovered token endpoint.

## HTTP Basic authentication

By default, ROPG sends the client ID and any client secret in the form body. Pass `basicAuth: true` to send the client credentials in the HTTP `Authorization: Basic` header instead; the client ID and secret are omitted from the form body.

## Override errors

For HTTP 400–403 responses, each `overrideErrors` value is matched as a substring of the raw response body:

- A match returns `nil`: credentials were accepted for the caller's policy, but no token is available, such as an MFA-gated response.
- No match throws `OIDCLiteError.oauthError` when the body contains OAuth error JSON, or `OIDCLiteError.authFailure` for a non-JSON body.

Other non-success responses throw the same typed error forms without override matching. Omitting `overrideErrors` therefore makes every non-success response throw.

## Entra and Okta form encoding

Entra and Okta ROPG requests use the same standards-based `application/x-www-form-urlencoded` codec as the other token flows.

Codec reference: https://theproductguy.in/blogs/url-encoding-for-forms/
