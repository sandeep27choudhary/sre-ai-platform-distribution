#!/usr/bin/env bash
# Install sre-ai-platform using the bundled Helm chart.
# Designed to run from within the cloned distribution repo.
#
# Usage:
#   ./scripts/install.sh [OPTIONS]
#
# Options:
#   --license-key KEY   Activate full plan (skips trial)
#   --namespace NS      Target namespace (default: sre-ai)
#   --release NAME      Helm release name (default: sre-agent)
#   --offline           Use imagePullPolicy:Never (minikube / air-gap)
#   --no-check          Skip post-install health check
#
# Env overrides (same as flags):
#   SRE_LICENSE_KEY, SRE_NAMESPACE, SRE_RELEASE, SRE_OFFLINE=true, SRE_NO_CHECK=true

set -euo pipefail

NAMESPACE="${SRE_NAMESPACE:-sre-ai}"
RELEASE="${SRE_RELEASE:-sre-agent}"
OFFLINE="${SRE_OFFLINE:-false}"
NO_CHECK="${SRE_NO_CHECK:-false}"
LICENSE_KEY="${SRE_LICENSE_KEY:-}"
CHART_DIR="$(cd "$(dirname "$0")/../helm/sre-agent" && pwd)"

# ── Parse CLI args ────────────────────────────────────────────────────────────
while [[ $# -gt 0 ]]; do
  case $1 in
    --license-key|-l) LICENSE_KEY="$2"; shift 2 ;;
    --namespace|-n)   NAMESPACE="$2";   shift 2 ;;
    --release|-r)     RELEASE="$2";     shift 2 ;;
    --offline)        OFFLINE="true";   shift ;;
    --no-check)       NO_CHECK="true";  shift ;;
    *) echo "Unknown option: $1"; shift ;;
  esac
done

# ── Banner ────────────────────────────────────────────────────────────────────
echo ""
echo "╔══════════════════════════════════════════════════════╗"
echo "║      SRE AI Platform — Install                      ║"
echo "╚══════════════════════════════════════════════════════╝"
echo "  Chart     : $CHART_DIR"
echo "  Namespace : $NAMESPACE"
echo "  Release   : $RELEASE"
[[ "$OFFLINE" == "true" ]] && echo "  Mode      : offline (imagePullPolicy: Never)"
[[ -n "$LICENSE_KEY" ]]    && echo "  License   : provided"
echo ""

# ── Pre-flight checks ─────────────────────────────────────────────────────────
for cmd in kubectl helm; do
  if ! command -v "$cmd" >/dev/null 2>&1; then
    echo "ERROR: '$cmd' not found in PATH. Install it and re-run."
    exit 1
  fi
done

if ! kubectl cluster-info >/dev/null 2>&1; then
  echo "ERROR: kubectl cannot reach a cluster. Check your KUBECONFIG."
  exit 1
fi

# ── Build Helm args ───────────────────────────────────────────────────────────
HELM_ARGS=(
  upgrade --install "$RELEASE" "$CHART_DIR"
  --namespace "$NAMESPACE"
  --create-namespace
  --set-string "license.trialStartEpoch=$(date +%s)"
  --wait
  --timeout 15m
)

[[ "$OFFLINE" == "true" ]]  && HELM_ARGS+=(--set "offlineMode=true")
[[ -n "$LICENSE_KEY" ]]     && HELM_ARGS+=(--set-string "license.key=${LICENSE_KEY}")

# ── Install ───────────────────────────────────────────────────────────────────
echo "Running helm upgrade --install ..."
helm "${HELM_ARGS[@]}"

# ── Success banner ────────────────────────────────────────────────────────────
echo ""
echo "╔══════════════════════════════════════════════════════╗"
echo "║   Install complete! ✓                               ║"
echo "╚══════════════════════════════════════════════════════╝"
echo ""
SECRET_NAME="${RELEASE}-sre-ai-platform-platform"
echo "  Get admin password (single command — copy and run as-is):"
echo "    kubectl get secret ${SECRET_NAME} -n ${NAMESPACE} -o jsonpath='{.data.SRE_ADMIN_PASSWORD}' | base64 -d && echo"
echo ""
echo "  Access the UI:"
echo "    kubectl port-forward svc/sre-platform-ui 3001:80 -n ${NAMESPACE}"
echo "    Open: http://localhost:3001"
echo "    Email: admin@sre.local"
echo ""

# ── Post-install health check ─────────────────────────────────────────────────
if [[ "$NO_CHECK" != "true" ]]; then
  CHECK_SCRIPT="$(dirname "$0")/post-install-check.sh"
  if [[ -x "$CHECK_SCRIPT" ]]; then
    echo "Running post-install health check ..."
    echo ""
    "$CHECK_SCRIPT" --namespace "$NAMESPACE" --release "$RELEASE" || true
  fi
fi
