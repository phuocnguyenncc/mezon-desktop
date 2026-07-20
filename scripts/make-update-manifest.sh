#!/usr/bin/env bash
# Generate an update manifest (electron-builder style yml) for one artifact.
# usage: make-update-manifest.sh <artifact> <version> <out-yml>
set -euo pipefail

artifact="${1:?usage: make-update-manifest.sh <artifact> <version> <out-yml>}"
version="${2:?missing version}"
out="${3:?missing output path}"

[[ -f "$artifact" ]] || { echo "artifact not found: $artifact" >&2; exit 1; }

sha512="$(openssl dgst -sha512 -binary "$artifact" | openssl base64 -A)"
size="$(wc -c < "$artifact" | tr -d '[:space:]')"

cat > "$out" <<EOF
version: ${version}
path: $(basename "$artifact")
sha512: ${sha512}
size: ${size}
releaseDate: '$(date -u +%Y-%m-%dT%H:%M:%S.000Z)'
EOF
echo "wrote ${out}"
