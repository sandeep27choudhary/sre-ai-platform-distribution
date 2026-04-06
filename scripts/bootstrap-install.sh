#!/usr/bin/env bash
# One-line installer for sre-ai-platform.
#
# Usage (one-liner):
#   curl -fsSL https://raw.githubusercontent.com/sandeep27choudhary/sre-ai-platform-distribution/main/scripts/bootstrap-install.sh | bash
#
# With a license key:
#   curl -fsSL https://raw.githubusercontent.com/sandeep27choudhary/sre-ai-platform-distribution/main/scripts/bootstrap-install.sh \
#     | bash -s -- --license-key 'YOUR_KEY'
#
# Air-gap / minikube (images already loaded locally):
#   curl -fsSL ... | bash -s -- --offline
#
# All flags are passed through to install.sh:
#   --license-key KEY   Activate full plan
#   --namespace NS      Target namespace      (default: sre-ai)
#   --release NAME      Helm release name     (default: sre-agent)
#   --offline           imagePullPolicy:Never (minikube / air-gap)
#   --no-check          Skip post-install health check
#
# Env overrides:
#   SRE_BOOTSTRAP_REPO    Git URL to clone  (default: this distribution repo)
#   SRE_BOOTSTRAP_BRANCH  Branch to clone   (default: main)
#   SRE_BOOTSTRAP_DIR     Local clone path  (default: sre-ai-install)

set -euo pipefail

REPO="${SRE_BOOTSTRAP_REPO:-https://github.com/sandeep27choudhary/sre-ai-platform-distribution.git}"
BRANCH="${SRE_BOOTSTRAP_BRANCH:-main}"
WORKDIR="${SRE_BOOTSTRAP_DIR:-sre-ai-install}"

echo ""
echo "╔══════════════════════════════════════════════════════╗"
echo "║      SRE AI Platform — Bootstrap Installer          ║"
echo "╚══════════════════════════════════════════════════════╝"
echo ""

# Pre-flight: check dependencies
for cmd in git kubectl helm; do
  if ! command -v "$cmd" >/dev/null 2>&1; then
    echo "ERROR: '$cmd' is required but not found in PATH."
    echo "  Install guide: https://github.com/sandeep27choudhary/sre-ai-platform-distribution#prerequisites"
    exit 1
  fi
done

if ! kubectl cluster-info >/dev/null 2>&1; then
  echo "ERROR: kubectl cannot reach a cluster. Check your KUBECONFIG."
  exit 1
fi

echo "  ✓ kubectl and helm found"
echo "  ✓ Cluster is reachable"
echo ""

# Clone distribution repo
if [[ -d "$WORKDIR" ]]; then
  echo "  Directory ./$WORKDIR already exists — pulling latest ..."
  git -C "$WORKDIR" pull --ff-only 2>/dev/null || true
else
  echo "  Cloning distribution repo ..."
  git clone --depth 1 -b "$BRANCH" "$REPO" "$WORKDIR"
fi

echo "  ✓ Distribution repo ready in ./$WORKDIR"
echo ""

# Hand off to install.sh (pass all args through)
cd "$WORKDIR"
exec ./scripts/install.sh "$@"
