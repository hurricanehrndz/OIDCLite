#!/bin/bash
set -euo pipefail

root="$(cd "$(dirname "$0")/../.." && pwd)"
version=v2.41.1
dex_source="$root/.build/dex-$version"
dex_binary="$root/.build/dex"
dex_log="$root/.build/dex.log"
issuer=http://127.0.0.1:5556/dex

if [[ ! -d "$dex_source/.git" ]]; then
    rm -rf "$dex_source"
    git clone --branch "$version" --depth 1 https://github.com/dexidp/dex.git "$dex_source"
fi

(cd "$dex_source" && go build -o "$dex_binary" ./cmd/dex)
"$dex_binary" serve "$root/scripts/integration/dex-config.yaml" >"$dex_log" 2>&1 &
dex_pid=$!
trap 'kill "$dex_pid" 2>/dev/null || true; wait "$dex_pid" 2>/dev/null || true' EXIT INT TERM

for _ in {1..60}; do
    if curl --fail --silent "$issuer/.well-known/openid-configuration" >/dev/null; then
        DEX_ISSUER="$issuer" swift test --filter OIDCLiteIntegrationTests
        exit
    fi
    if ! kill -0 "$dex_pid" 2>/dev/null; then
        cat "$dex_log" >&2
        exit 1
    fi
    sleep 1
done

cat "$dex_log" >&2
echo "dex did not become ready within 60 seconds" >&2
exit 1
