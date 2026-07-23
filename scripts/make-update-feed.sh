#!/usr/bin/env bash
# Package one platform's auto-update artifact + manifest into target/update-feed/.
# usage: make-update-feed.sh macos <path-to-dmg>
#        make-update-feed.sh linux [path-to-binary]
#        make-update-feed.sh windows [path-to-exe]
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

VERSION="${VERSION:-$(grep -m1 '^version' Cargo.toml | sed -E 's/.*"(.*)".*/\1/')}"
FEED="${ROOT}/target/update-feed"
mkdir -p "$FEED"

platform="${1:?usage: make-update-feed.sh <macos|linux|windows> [artifact]}"

case "$platform" in
  macos)
    dmg="${2:?usage: make-update-feed.sh macos <path-to-dmg>}"
    [[ -f "$dmg" ]] || { echo "dmg not found: $dmg" >&2; exit 1; }
    artifact="${FEED}/Mezon-${VERSION}-universal.dmg"
    cp "$dmg" "$artifact"
    bash scripts/make-update-manifest.sh "$artifact" "$VERSION" "${FEED}/latest-native-mac.yml"
    ;;
  linux)
    arch="$(uname -m)"
    bin="${2:-target/release/mezon}"
    [[ -f "$bin" ]] || { echo "binary not found: $bin (run: cargo build --release -p mezon-app)" >&2; exit 1; }
    artifact="${FEED}/mezon-${VERSION}-linux-${arch}.tar.gz"
    stage="$(mktemp -d)"
    trap 'rm -rf "$stage"' EXIT
    cp "$bin" "${stage}/mezon"
    chmod 755 "${stage}/mezon"
    cp packaging/linux/mezon.png "${stage}/mezon.png"
    cp packaging/linux/mezon.desktop "${stage}/mezon.desktop"
    tar -czf "$artifact" -C "$stage" mezon mezon.png mezon.desktop
    bash scripts/make-update-manifest.sh "$artifact" "$VERSION" "${FEED}/latest-native-linux-${arch}.yml"
    ;;
  windows)
    bin="${2:-target/release/mezon.exe}"
    [[ -f "$bin" ]] || { echo "binary not found: $bin (run: cargo build --release -p mezon-app)" >&2; exit 1; }
    artifact="${FEED}/mezon-${VERSION}-windows-x86_64.zip"
    rm -f "$artifact"
    if command -v 7z >/dev/null 2>&1; then
      (cd "$(dirname "$bin")" && 7z a -tzip "$artifact" "$(basename "$bin")" >/dev/null)
    else
      powershell.exe -NoProfile -Command \
        "Compress-Archive -Force -Path '$(cygpath -w "$bin")' -DestinationPath '$(cygpath -w "$artifact")'"
    fi
    bash scripts/make-update-manifest.sh "$artifact" "$VERSION" "${FEED}/latest-native-windows-x86_64.yml"
    ;;
  *)
    echo "unknown platform: $platform (want macos|linux|windows)" >&2
    exit 1
    ;;
esac

echo ""
echo "update feed ready in ${FEED}:"
ls -la "$FEED"
