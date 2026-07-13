# Agent notes

## Repo facts

- Fork of jamf/OIDCLite (`origin` = github.com/hurricanehrndz/OIDCLite). Do not open PRs against upstream.
- Swift package (SwiftPM only, no Xcode project). Library for OIDC auth on macOS 10.15+ / iOS 14+.
- Networking is Apple `URLSession`/`AuthenticationServices` — the library builds and tests fully only on Darwin. Linux hosts are fine for editing, linting, and formatting, not for `swift build`/`swift test`.

## Branch & PR workflow

- `develop` is the working branch; feature/chore branches come off `develop`.
- **When the user asks for a PR, open it against this fork's `main` branch** (base `main`, on `hurricanehrndz/OIDCLite`), not upstream and not `develop`, unless they say otherwise.

## Dev tooling

- Tools are pinned in `mise.toml` (prek, swiftlint, swiftformat; tuist is macOS-only via an `os` gate). `direnv allow` activates them via `.envrc`.
- Pre-commit hooks run through `prek` (`prek install` once per clone; `prek run --all-files` to check everything). Config: `.pre-commit-config.yaml`.
- The swiftformat hook must keep passing `--config .swiftformat` explicitly — bare directory lint crashes swiftformat with a rule-restricting config present.

## Testing

- `swift test` on a macOS host. There is no CI in this fork.
- User's global commits are GPG-signed; agent environments may lack the key — commit with `-c commit.gpgsign=false` and tell the user to re-sign if needed.
