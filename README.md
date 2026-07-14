# OIDCLite

OIDCLite is a lightweight Swift package for OpenID Connect. It supports authorization-code login with PKCE through Apple's `ASWebAuthenticationSession`, token refresh, and the resource owner password grant.

Requires macOS 15+ or iOS 14+.

## Documentation

- [Authorization-code login](docs/usage.md#authorization-code-login)
- [Discovery endpoints](docs/usage.md#discovery-endpoints)
- [Refresh tokens and HTTP Basic authentication](docs/usage.md#refresh-tokens-and-http-basic-authentication)
- [Typed OAuth errors](docs/usage.md#typed-oauth-errors)
- [Resource owner password grant](docs/ropg.md#resource-owner-password-grant)
- [ROPG HTTP Basic authentication](docs/ropg.md#http-basic-authentication)
- [ROPG override errors](docs/ropg.md#override-errors)
- [Entra and Okta form encoding](docs/ropg.md#entra-and-okta-form-encoding)

## Development

Dev tooling is managed with [mise](https://mise.jdx.dev). Run `mise install` to get SwiftLint, SwiftFormat, prek, and (on macOS) Tuist, then `prek install` to enable the pre-commit hooks. With [direnv](https://direnv.net), `direnv allow` puts the tools on your `PATH` automatically.

Run offline unit tests with `just test`. Integration tests require Go to build the pinned dex server; run them with `just itest`. Run all lint and formatting checks with `just lint`.
