#!/usr/bin/env bash
# Build image tags for both demo versions from git refs, without switching branches.
#
#   agency-api:develop / agency-web:develop   ← branch develop   (old: polling, no /api/v1/health)
#   agency-api:sse     / agency-web:sse       ← branch feature/sse (SSE + /api/v1/health)
#
# Usage: scripts/build-versions.sh [ref:tag ...]
#   default: develop:develop feature/sse:sse

set -euo pipefail

DOCKER_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ROOT="$(cd "$DOCKER_DIR/../.." && pwd)"

if [ "$#" -eq 0 ]; then
  pairs=("develop:develop" "feature/sse:sse")
else
  pairs=("$@")
fi

build_one() {
  local repo="$1" ref="$2" tag="$3"
  local tmp
  tmp="$(mktemp -d)"
  echo "==> ${repo}:${tag}  (from ${ref})"
  git -C "$ROOT/$repo" archive "$ref" | tar -x -C "$tmp"
  docker build --tag "${repo}:${tag}" "$tmp"
  rm -rf "$tmp"
}

for pair in "${pairs[@]}"; do
  ref="${pair%%:*}"
  tag="${pair##*:}"
  build_one agency-api "$ref" "$tag"
  build_one agency-web "$ref" "$tag"
done

echo
echo "Built images:"
docker images --format '  {{.Repository}}:{{.Tag}}  ({{.Size}})' | grep -E '^  agency-(api|web):(develop|sse)' || true
