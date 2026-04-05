#!/usr/bin/env bash
# Clone this repository (public distribution: Helm chart lives under helm/sre-agent only)
# and run scripts/install.sh against that chart.
#
# Usage:
#   curl -fsSL https://raw.githubusercontent.com/sandeep27choudhary/sre-ai-platform-distribution/main/scripts/bootstrap-install.sh | bash -s --
#
# Env:
#   SRE_BOOTSTRAP_REPO   Git URL (default: this distribution repo)
#   SRE_BOOTSTRAP_BRANCH Branch (default: main)
#   SRE_BOOTSTRAP_DIR    Clone directory name (default: sre-ai-install)

set -euo pipefail

REPO="${SRE_BOOTSTRAP_REPO:-https://github.com/sandeep27choudhary/sre-ai-platform-distribution.git}"
BRANCH="${SRE_BOOTSTRAP_BRANCH:-main}"
WORKDIR="${SRE_BOOTSTRAP_DIR:-sre-ai-install}"

echo ">>> Cloning ${REPO} (branch ${BRANCH}) into ./${WORKDIR} ..."
git clone --depth 1 -b "$BRANCH" "$REPO" "$WORKDIR"
cd "$WORKDIR"
exec ./scripts/install.sh "$@"
