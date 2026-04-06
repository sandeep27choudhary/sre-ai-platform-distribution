#!/usr/bin/env bash
set -euo pipefail

# SRE AI Platform — install from this repo only (Helm chart: helm/sre-agent).
# Run from repository root after cloning https://github.com/sandeep27choudhary/sre-ai-platform-distribution
# Usage: ./scripts/install.sh [--license-key KEY] [--namespace NS] [--values FILE] [--no-trial]

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CHART_DIR="${ROOT}/helm/sre-agent"
NAMESPACE="${SRE_NAMESPACE:-sre-ai}"
RELEASE_NAME="${SRE_RELEASE:-sre-ai-platform}"
LICENSE_KEY="${SRE_LICENSE_KEY:-}"
VALUES_FILE=""
DRY_RUN=""
ENABLE_TRIAL="${SRE_ENABLE_TRIAL:-1}"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m'

info()  { echo -e "${BLUE}[INFO]${NC}  $*"; }
ok()    { echo -e "${GREEN}[OK]${NC}    $*"; }
warn()  { echo -e "${YELLOW}[WARN]${NC}  $*"; }
err()   { echo -e "${RED}[ERROR]${NC} $*" >&2; }

usage() {
  cat <<EOF
SRE AI Platform Installer (distribution chart only)

Chart path: helm/sre-agent (bundled in this repository).

Usage: $0 [OPTIONS]

Options:
  --license-key KEY     License key for feature activation (RS256 JWT or legacy HMAC)
  --namespace   NS      Kubernetes namespace (default: sre-ai)
  --release     NAME    Helm release name (default: sre-ai-platform)
  --values      FILE    Additional values file (e.g. examples/values-production.yaml)
  --no-trial            Do not set install-time eval trial clock (license.trialStartEpoch)
  --dry-run             Print manifests without applying
  --help                Show this help

Examples:
  $0
  $0 --license-key "your-license-key-here"
  $0 --license-key "KEY" --values examples/values-production.yaml --namespace production

Environment variables:
  SRE_LICENSE_KEY     Same as --license-key
  SRE_NAMESPACE       Same as --namespace
  SRE_RELEASE         Same as --release
  SRE_ENABLE_TRIAL=0  Same as --no-trial
EOF
  exit 0
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --license-key) LICENSE_KEY="$2"; shift 2 ;;
    --namespace)   NAMESPACE="$2"; shift 2 ;;
    --release)     RELEASE_NAME="$2"; shift 2 ;;
    --values)      VALUES_FILE="$2"; shift 2 ;;
    --no-trial)    ENABLE_TRIAL=0; shift ;;
    --dry-run)     DRY_RUN="--dry-run"; shift ;;
    --help)        usage ;;
    *)             err "Unknown option: $1"; usage ;;
  esac
done

echo ""
echo "======================================"
echo "  SRE AI Platform Installer"
echo "======================================"
echo ""

info "Pre-flight checks..."

command -v kubectl >/dev/null 2>&1 || { err "kubectl not found. Install: https://kubernetes.io/docs/tasks/tools/"; exit 1; }
command -v helm >/dev/null 2>&1    || { err "helm not found. Install: https://helm.sh/docs/intro/install/"; exit 1; }

kubectl cluster-info >/dev/null 2>&1 || { err "Cannot reach Kubernetes cluster. Check kubeconfig."; exit 1; }
ok "Kubernetes cluster reachable"

HELM_VERSION=$(helm version --short 2>/dev/null | grep -oE 'v[0-9]+\.[0-9]+' | head -1)
info "Helm version: $HELM_VERSION"

if [ ! -d "$CHART_DIR" ]; then
  err "Chart directory not found: $CHART_DIR"
  err "Clone https://github.com/sandeep27choudhary/sre-ai-platform-distribution and run from repo root."
  exit 1
fi
ok "Chart found: $CHART_DIR"

info "Installing $RELEASE_NAME in namespace $NAMESPACE..."

HELM_ARGS=(
  upgrade --install "$RELEASE_NAME" "$CHART_DIR"
  --namespace "$NAMESPACE" --create-namespace
  --set createNamespace=false
)

if [ -n "$LICENSE_KEY" ]; then
  HELM_ARGS+=(--set-string "license.key=$LICENSE_KEY")
  info "License key provided"
else
  warn "No license key — community eval (use vendor LICENSE_KEY after trial if required)"
fi

if [[ "$ENABLE_TRIAL" == "1" ]] && [[ -z "$DRY_RUN" ]]; then
  TRIAL_START=$(date +%s)
  HELM_ARGS+=(--set-string "license.trialStartEpoch=$TRIAL_START")
  info "Eval trial clock started (license.trialStartEpoch=$TRIAL_START; see license.trialDays in values)"
elif [[ "$ENABLE_TRIAL" == "0" ]]; then
  info "Eval trial not set (--no-trial / SRE_ENABLE_TRIAL=0)"
fi

if [ -n "$VALUES_FILE" ]; then
  HELM_ARGS+=(-f "$VALUES_FILE")
  info "Using values file: $VALUES_FILE"
fi

if [ -n "$DRY_RUN" ]; then
  HELM_ARGS+=($DRY_RUN)
fi

helm "${HELM_ARGS[@]}" --wait --timeout 15m

echo ""
ok "Installation complete!"
echo ""

if [ -z "$DRY_RUN" ]; then
  info "Waiting for pods..."
  kubectl wait --for=condition=ready pod -l app=api -n "$NAMESPACE" --timeout=120s 2>/dev/null || warn "API pod not ready yet"

  echo ""
  info "Pod status:"
  kubectl get pods -n "$NAMESPACE" -o wide
  echo ""

  info "Access:"
  echo "  kubectl port-forward svc/sre-platform-ui 3001:80 -n $NAMESPACE"
  echo "  kubectl port-forward svc/api 8000:8000 -n $NAMESPACE"
  echo "  Open http://localhost:3001"
  echo ""
  info "Login: admin@sre.local"
  info "Retrieve auto-generated password:"
  echo ""
  echo "  kubectl get secret ${RELEASE_NAME}-sre-ai-platform-platform \"
  echo "    -n ${NAMESPACE} \"
  echo "    -o jsonpath='{.data.SRE_ADMIN_PASSWORD}' | base64 -d && echo"
  echo ""
  echo ""

  info "License status:"
  kubectl exec -n "$NAMESPACE" deploy/api -- curl -sS http://localhost:8000/license 2>/dev/null | python3 -m json.tool 2>/dev/null || warn "Could not check license (pod may still be starting)"
fi
