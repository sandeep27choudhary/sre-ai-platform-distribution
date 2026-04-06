#!/usr/bin/env bash
# Post-install health check and validation for sre-ai-platform.
# Run after install.sh completes to verify the platform is working correctly.
#
# Usage:
#   ./scripts/post-install-check.sh [--namespace sre-ai] [--release sre-agent]
#
# Exit codes:
#   0 — all checks passed
#   1 — one or more critical checks failed

set -euo pipefail

# ── Defaults ─────────────────────────────────────────────────────────────────
NAMESPACE="${SRE_NAMESPACE:-sre-ai}"
RELEASE="${SRE_RELEASE:-}"          # auto-detected below if empty
ADMIN_EMAIL="${SRE_ADMIN_EMAIL:-admin@sre.local}"
ADMIN_PASSWORD="${SRE_ADMIN_PASSWORD:-}"
# Pick a free port unless overridden
_pick_free_port() { python3 -c "import socket; s=socket.socket(); s.bind(('',0)); p=s.getsockname()[1]; s.close(); print(p)"; }
API_LOCAL_PORT="${SRE_API_PORT:-$(_pick_free_port)}"
WAIT_TIMEOUT="${SRE_WAIT_TIMEOUT:-120}"   # seconds to wait for pods

PF_PID=""
PASS=0
FAIL=0

# ── Colour helpers ────────────────────────────────────────────────────────────
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'
ok()   { echo -e "${GREEN}  ✓ $*${NC}";  ((PASS++)) || true; }
fail() { echo -e "${RED}  ✗ $*${NC}";   ((FAIL++)) || true; }
warn() { echo -e "${YELLOW}  ⚠ $*${NC}"; }
info() { echo -e "  → $*"; }

# ── Cleanup on exit ───────────────────────────────────────────────────────────
cleanup() {
  if [[ -n "$PF_PID" ]]; then
    kill "$PF_PID" 2>/dev/null || true
  fi
}
trap cleanup EXIT

# ── Parse args ────────────────────────────────────────────────────────────────
while [[ $# -gt 0 ]]; do
  case $1 in
    --namespace|-n) NAMESPACE="$2"; shift 2 ;;
    --release|-r)   RELEASE="$2";   shift 2 ;;
    --email)        ADMIN_EMAIL="$2"; shift 2 ;;
    --password)     ADMIN_PASSWORD="$2"; shift 2 ;;
    *) shift ;;
  esac
done

# ── Auto-detect Helm release if not provided ──────────────────────────────────
if [[ -z "$RELEASE" ]]; then
  RELEASE=$(helm list -n "$NAMESPACE" -o json 2>/dev/null \
    | python3 -c "import sys,json; releases=json.load(sys.stdin); print(releases[0]['name'] if releases else '')" 2>/dev/null || echo "")
  if [[ -z "$RELEASE" ]]; then
    RELEASE="sre-agent"   # fallback
  fi
fi

echo ""
echo "═══════════════════════════════════════════════════════"
echo "   SRE AI Platform — Post-Install Health Check"
echo "═══════════════════════════════════════════════════════"
echo "   Namespace : $NAMESPACE"
echo "   Release   : $RELEASE"
echo ""

# ─────────────────────────────────────────────────────────────────────────────
# SECTION 1: Pod readiness
# ─────────────────────────────────────────────────────────────────────────────
echo "── Section 1: Pod Readiness ─────────────────────────────"

REQUIRED_COMPONENTS="api worker postgres ollama llm-gateway"

for component in $REQUIRED_COMPONENTS; do
  POD=$(kubectl get pods -n "$NAMESPACE" \
        -l "app.kubernetes.io/component=${component}" \
        --field-selector=status.phase=Running \
        -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || \
      kubectl get pods -n "$NAMESPACE" \
        -l "app=${component}" \
        --field-selector=status.phase=Running \
        -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")

  if [[ -z "$POD" ]]; then
    # Try by release label
    POD=$(kubectl get pods -n "$NAMESPACE" \
          --selector="app.kubernetes.io/name=${RELEASE}" \
          -o jsonpath="{.items[?(@.metadata.name=~'.*${component}.*')].metadata.name}" 2>/dev/null | awk '{print $1}' || echo "")
  fi

  if [[ -n "$POD" ]]; then
    READY=$(kubectl get pod "$POD" -n "$NAMESPACE" \
            -o jsonpath='{.status.containerStatuses[0].ready}' 2>/dev/null || echo "false")
    if [[ "$READY" == "true" ]]; then
      ok "Pod $component ($POD) is Running and Ready"
    else
      fail "Pod $component ($POD) exists but not Ready"
      kubectl describe pod "$POD" -n "$NAMESPACE" 2>/dev/null | grep -A5 "Events:" | tail -6 || true
    fi
  else
    fail "No running pod found for component: $component"
  fi
done

# Also show any pods in bad state
BAD_PODS=$(kubectl get pods -n "$NAMESPACE" \
  --field-selector='status.phase!=Running,status.phase!=Succeeded' \
  -o jsonpath='{range .items[*]}{.metadata.name}{"\t"}{.status.phase}{"\n"}{end}' 2>/dev/null || true)
if [[ -n "$BAD_PODS" ]]; then
  warn "Pods not in Running/Succeeded state:"
  echo "$BAD_PODS" | while read -r line; do echo "    $line"; done
fi

# ─────────────────────────────────────────────────────────────────────────────
# SECTION 2: API health via port-forward
# ─────────────────────────────────────────────────────────────────────────────
echo ""
echo "── Section 2: API Connectivity ─────────────────────────"

API_BASE="http://localhost:${API_LOCAL_PORT}"

# Start port-forward in background
kubectl port-forward svc/api "$API_LOCAL_PORT:8000" -n "$NAMESPACE" >/dev/null 2>&1 &
PF_PID=$!

# Wait for port-forward to be ready
info "Waiting for port-forward on :${API_LOCAL_PORT} ..."
for i in $(seq 1 20); do
  if curl -sf --max-time 2 "${API_BASE}/health" >/dev/null 2>&1; then
    break
  fi
  sleep 1
done

HEALTH_RESP=$(curl -sf --max-time 5 "${API_BASE}/health" 2>/dev/null || echo "")
if [[ -n "$HEALTH_RESP" ]]; then
  ok "API /health responded"
else
  fail "API /health did not respond — check api pod logs:"
  info "  kubectl logs -n $NAMESPACE deploy/api --tail=30"
  echo ""
  echo "Skipping API-dependent checks."
  echo ""
  echo "═══════════════════════════════════════════════════════"
  echo "   Result: ${PASS} passed, ${FAIL} failed"
  echo "═══════════════════════════════════════════════════════"
  exit 1
fi

READY_RESP=$(curl -sf --max-time 5 "${API_BASE}/ready" 2>/dev/null || echo "{}")
# /ready returns {"status":"ready","details":{"postgres":"ok","redis":"ok"}}
READY_STATUS=$(echo "$READY_RESP" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('status','unknown'))" 2>/dev/null || echo "unknown")
DB_OK=$(echo "$READY_RESP" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('details',{}).get('postgres','unknown'))" 2>/dev/null || echo "unknown")

if [[ "$DB_OK" == "ok" ]]; then
  ok "Database connectivity: ok"
else
  fail "Database not ready (status: $READY_STATUS, postgres: $DB_OK) — check postgres pod and secret"
  info "  Secret: kubectl get secret ${RELEASE}-sre-ai-platform-platform -n ${NAMESPACE} -o jsonpath='{.data.POSTGRES_PASSWORD}' | base64 -d"
fi

if [[ "$READY_STATUS" == "ready" ]]; then
  ok "API ready status: ok"
else
  warn "API ready status: $READY_STATUS (services may still be initializing)"
fi

# ─────────────────────────────────────────────────────────────────────────────
# SECTION 3: Authentication
# ─────────────────────────────────────────────────────────────────────────────
echo ""
echo "── Section 3: Authentication ────────────────────────────"

if [[ -z "$ADMIN_PASSWORD" ]]; then
  # Secret name: <release>-<chart-name>-platform (e.g. sre-agent-sre-ai-platform-platform)
  ADMIN_PASSWORD=$(kubectl get secret "${RELEASE}-sre-ai-platform-platform" -n "$NAMESPACE" \
    -o jsonpath='{.data.SRE_ADMIN_PASSWORD}' 2>/dev/null | base64 -d 2>/dev/null || \
    kubectl get secret "${RELEASE}-platform" -n "$NAMESPACE" \
    -o jsonpath='{.data.SRE_ADMIN_PASSWORD}' 2>/dev/null | base64 -d 2>/dev/null || echo "changeme")
fi

LOGIN_RESP=$(curl -sf --max-time 10 -X POST "${API_BASE}/auth/login" \
  -H "Content-Type: application/json" \
  -d "{\"email\":\"${ADMIN_EMAIL}\",\"password\":\"${ADMIN_PASSWORD}\"}" 2>/dev/null || echo "")

ACCESS_TOKEN=$(echo "$LOGIN_RESP" | python3 -c "import sys,json; print(json.load(sys.stdin).get('access_token',''))" 2>/dev/null || echo "")

if [[ -n "$ACCESS_TOKEN" ]]; then
  ok "Admin login succeeded (${ADMIN_EMAIL})"
else
  fail "Admin login failed — check credentials or DB state"
  info "  Try: kubectl logs -n $NAMESPACE deploy/api --tail=50 | grep -i 'login\|auth\|password'"
  info "  Expected email: ${ADMIN_EMAIL}"
fi

# ─────────────────────────────────────────────────────────────────────────────
# SECTION 4: Ollama model availability
# ─────────────────────────────────────────────────────────────────────────────
echo ""
echo "── Section 4: Ollama Models ─────────────────────────────"

OLLAMA_POD=$(kubectl get pods -n "$NAMESPACE" \
  -l "app.kubernetes.io/component=ollama" \
  -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || \
  kubectl get pods -n "$NAMESPACE" -l "app=ollama" \
  -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")

REQUIRED_MODELS="nomic-embed-text llama3.2"

if [[ -n "$OLLAMA_POD" ]]; then
  MODELS_LIST=$(kubectl exec "$OLLAMA_POD" -n "$NAMESPACE" -- ollama list 2>/dev/null || echo "")
  for model in $REQUIRED_MODELS; do
    if echo "$MODELS_LIST" | grep -q "$model"; then
      ok "Ollama model available: $model"
    else
      fail "Ollama model missing: $model"
      info "  Pull it manually: kubectl exec $OLLAMA_POD -n $NAMESPACE -- ollama pull $model"
      info "  Or wait for the post-install job: kubectl get job -n $NAMESPACE | grep pull-ollama"
    fi
  done
else
  warn "Ollama pod not found — skipping model check"
fi

# ─────────────────────────────────────────────────────────────────────────────
# SECTION 5: Core agent endpoint (T0 query)
# ─────────────────────────────────────────────────────────────────────────────
echo ""
echo "── Section 5: Agent Query (T0) ──────────────────────────"

if [[ -n "$ACCESS_TOKEN" ]]; then
  AGENT_RESP=$(curl -sf --max-time 20 -X POST "${API_BASE}/agent/ask" \
    -H "Content-Type: application/json" \
    -H "Authorization: Bearer ${ACCESS_TOKEN}" \
    -d '{"question":"cluster health"}' 2>/dev/null || echo "")

  # Response shape: {"response": {"summary": "...", "tier_used": N, ...}}
  TIER=$(echo "$AGENT_RESP" | python3 -c "import sys,json; d=json.load(sys.stdin); r=d.get('response',d); print(r.get('tier_used','?'))" 2>/dev/null || echo "?")
  SUMMARY=$(echo "$AGENT_RESP" | python3 -c "import sys,json; d=json.load(sys.stdin); r=d.get('response',d); print(r.get('summary','')[:80])" 2>/dev/null || echo "")

  if [[ -n "$SUMMARY" ]]; then
    ok "Agent responded (tier=${TIER}): ${SUMMARY}..."
  else
    fail "Agent /ask returned no summary"
    info "  Raw response: $(echo "$AGENT_RESP" | head -c 200)"
  fi
else
  warn "Skipping agent test — login failed"
fi

# ─────────────────────────────────────────────────────────────────────────────
# SECTION 6: Platform UI connectivity
# ─────────────────────────────────────────────────────────────────────────────
echo ""
echo "── Section 6: Platform UI ───────────────────────────────"

UI_POD=$(kubectl get pods -n "$NAMESPACE" \
  -l "app.kubernetes.io/component=sre-platform-ui" \
  -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || \
  kubectl get pods -n "$NAMESPACE" \
  -l "app=sre-platform-ui" \
  -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")

if [[ -n "$UI_POD" ]]; then
  UI_READY=$(kubectl get pod "$UI_POD" -n "$NAMESPACE" \
    -o jsonpath='{.status.containerStatuses[0].ready}' 2>/dev/null || echo "false")
  if [[ "$UI_READY" == "true" ]]; then
    ok "Platform UI pod is Ready"
  else
    fail "Platform UI pod not Ready"
  fi
else
  warn "Platform UI pod not found — UI may not be deployed"
fi

# ─────────────────────────────────────────────────────────────────────────────
# SECTION 7: Known issue remediation hints
# ─────────────────────────────────────────────────────────────────────────────
echo ""
echo "── Section 7: Issue Remediation Hints ──────────────────"

# Check for ImagePullBackOff
PULL_ERRORS=$(kubectl get pods -n "$NAMESPACE" \
  -o jsonpath='{range .items[*]}{.metadata.name}{"\t"}{range .status.containerStatuses[*]}{.state.waiting.reason}{end}{"\n"}{end}' 2>/dev/null | \
  grep -E "ImagePullBackOff|ErrImagePull" || true)
if [[ -n "$PULL_ERRORS" ]]; then
  warn "ImagePullBackOff detected — private images may need authentication:"
  echo "$PULL_ERRORS" | while read -r line; do echo "    $line"; done
  info "  Fix: kubectl create secret docker-registry regcred \\"
  info "         --docker-server=ghcr.io \\"
  info "         --docker-username=<github_username> \\"
  info "         --docker-password=<ghcr_pat> \\"
  info "         -n $NAMESPACE"
fi

# Check for CrashLoopBackOff
CRASH_PODS=$(kubectl get pods -n "$NAMESPACE" \
  -o jsonpath='{range .items[*]}{.metadata.name}{"\t"}{range .status.containerStatuses[*]}{.state.waiting.reason}{end}{"\n"}{end}' 2>/dev/null | \
  grep "CrashLoopBackOff" || true)
if [[ -n "$CRASH_PODS" ]]; then
  warn "CrashLoopBackOff pods detected:"
  echo "$CRASH_PODS" | while read -r podname _; do
    echo "    $podname"
    info "  Check logs: kubectl logs $podname -n $NAMESPACE --previous --tail=30"
  done
fi

# Check postgres secret consistency
SECRET_NAME="${RELEASE}-sre-ai-platform-platform"
DB_SECRET=$(kubectl get secret "$SECRET_NAME" -n "$NAMESPACE" \
  -o jsonpath='{.data.POSTGRES_PASSWORD}' 2>/dev/null | base64 -d 2>/dev/null || \
  kubectl get secret "${RELEASE}-platform" -n "$NAMESPACE" \
  -o jsonpath='{.data.POSTGRES_PASSWORD}' 2>/dev/null | base64 -d 2>/dev/null || echo "")
if [[ -z "$DB_SECRET" ]]; then
  fail "Platform secret missing POSTGRES_PASSWORD key"
  info "  Helm secret may not have been created — try re-running: helm upgrade $RELEASE"
else
  ok "Platform secret has POSTGRES_PASSWORD"
fi

# ─────────────────────────────────────────────────────────────────────────────
# Final summary
# ─────────────────────────────────────────────────────────────────────────────
echo ""
echo "═══════════════════════════════════════════════════════"
if [[ $FAIL -eq 0 ]]; then
  echo -e "${GREEN}   ✓ All checks passed: ${PASS} passed, 0 failed${NC}"
  echo ""
  echo "   Platform is ready. Access the UI:"
  echo "   kubectl port-forward svc/platform-ui 3000:3000 -n ${NAMESPACE}"
  echo "   Open: http://localhost:3000"
  echo "   Login: ${ADMIN_EMAIL}"
else
  echo -e "${YELLOW}   Result: ${PASS} passed, ${RED}${FAIL} failed${NC}"
  echo ""
  echo "   Review failures above. For detailed logs:"
  echo "   kubectl logs -n ${NAMESPACE} deploy/api --tail=50"
  echo "   kubectl logs -n ${NAMESPACE} deploy/worker --tail=30"
fi
echo "═══════════════════════════════════════════════════════"
echo ""

[[ $FAIL -eq 0 ]]
