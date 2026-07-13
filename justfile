# list recipes
default:
    @just --list

# run unit tests (macOS only)
test:
    swift test

# run all pre-commit hooks
lint:
    prek run --all-files

# generate Xcode project (macOS only)
generate:
    tuist generate --no-open
