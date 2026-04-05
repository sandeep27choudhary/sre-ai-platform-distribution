#!/usr/bin/env bash
set -euo pipefail

# Build distributable Helm artifacts for publishing (run from distribution repo root).
# Outputs:
#   dist/sre-ai-platform-<version>.tgz
#   dist/index.yaml

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CHART_DIR="${ROOT_DIR}/helm/sre-agent"
DIST_DIR="${ROOT_DIR}/dist"
REPO_URL="${HELM_REPO_URL:-}"
SKIP_LINT="${SKIP_LINT:-false}"

usage() {
  cat <<EOF
Package Helm chart for distribution.

Usage:
  $0 [--repo-url URL] [--skip-lint]

Options:
  --repo-url URL   Public URL where dist/ will be hosted
                   (used in generated index.yaml)
  --skip-lint      Skip 'helm lint'

Environment:
  HELM_REPO_URL    Same as --repo-url
  SKIP_LINT=true   Skip lint

Examples:
  $0
  $0 --repo-url https://sandeep27choudhary.github.io/sre-ai-platform-distribution
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --repo-url) REPO_URL="$2"; shift 2 ;;
    --skip-lint) SKIP_LINT=true; shift ;;
    --help|-h) usage; exit 0 ;;
    *) echo "Unknown option: $1"; usage; exit 1 ;;
  esac
done

command -v helm >/dev/null 2>&1 || { echo "helm not found"; exit 1; }

mkdir -p "${DIST_DIR}"

if [[ "${SKIP_LINT}" != "true" ]]; then
  echo "[1/4] helm lint"
  helm lint "${CHART_DIR}"
fi

echo "[2/4] helm dependency update (if any)"
helm dependency update "${CHART_DIR}" >/dev/null

echo "[3/4] helm package -> dist/"
helm package "${CHART_DIR}" --destination "${DIST_DIR}" >/dev/null

echo "[4/4] helm repo index"
if [[ -n "${REPO_URL}" ]]; then
  helm repo index "${DIST_DIR}" --url "${REPO_URL}" >/dev/null
else
  helm repo index "${DIST_DIR}" >/dev/null
fi

echo ""
echo "Artifacts ready:"
ls -1 "${DIST_DIR}"/sre-ai-platform-*.tgz "${DIST_DIR}/index.yaml"
echo ""
echo "Next:"
echo "  helm repo index dist --url <public-url>"
echo "  publish dist/ to your static hosting (GitHub Pages/S3/Nginx)"
