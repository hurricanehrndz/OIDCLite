# Agent notes

## Repo facts

- Fork of jamf/OIDCLite (`origin` = github.com/hurricanehrndz/OIDCLite). Do not open PRs against upstream.
- Swift package. Library for OIDC auth on macOS 10.15+ / iOS 14+. `Package.swift` is the SPM source of truth for consumers; Tuist (`Project.swift`, `Tuist.swift`) is for local development only — keep both in sync when targets change.
- Networking is Apple `URLSession`/`AuthenticationServices` — the library builds and tests fully only on Darwin. Linux hosts are fine for editing, linting, and formatting, not for `swift build`/`swift test`.

## Branch & PR workflow

- `develop` is the working branch; feature/chore branches come off `develop`.
- **When the user asks for a PR, open it against this fork's `main` branch** (base `main`, on `hurricanehrndz/OIDCLite`), not upstream and not `develop`, unless they say otherwise.

## Dev tooling

- Tools are pinned in `mise.toml` (prek, swiftlint, swiftformat; tuist is macOS-only via an `os` gate). `direnv allow` activates them via `.envrc`.
- Pre-commit hooks run through `prek` (`prek install` once per clone; `prek run --all-files` to check everything). Config: `.pre-commit-config.yaml`.
- `.swiftformat` / `.swiftlint.yml` enforce the full default rulesets. The swiftformat hook lints bare (`swiftformat --lint .`, auto-discovering `.swiftformat`); the old `--config` workaround for the rule-restricting-config crash is no longer needed now that no rules are restricted.
- Xcode project generation (macOS only): `tuist generate --no-open`. Generated output (`*.xcodeproj`, `*.xcworkspace`, `Derived/`) is git-ignored — never commit it.

## Testing

- `swift test` (SPM) or `tuist test` (generates + runs via xcodebuild) on a macOS host. There is no CI in this fork.
- User's global commits are GPG-signed; agent environments may lack the key — commit with `-c commit.gpgsign=false` and tell the user to re-sign if needed.
