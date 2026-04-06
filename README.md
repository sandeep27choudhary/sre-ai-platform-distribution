# SreA — Kubernetes SRE Assistant

**SreA** (SRE Assistant) is a self-hosted, air-gap-ready Kubernetes troubleshooting assistant.  
Deterministic RCA, forensic investigation, and autonomous incident response — all running on your cluster.

Images are pulled from **GHCR** · Helm chart index is served from **GitHub Pages** on this repo.

---

## Prerequisites

| Requirement | Version |
|---|---|
| Kubernetes | 1.25+ |
| Helm | 3.x |
| kubectl | configured for your cluster |

---

## Install

### Option A — Bootstrap (one command, recommended)

```bash
curl -fsSL https://raw.githubusercontent.com/sandeep27choudhary/sre-ai-platform-distribution/main/scripts/bootstrap-install.sh | bash
```

With a license key (activates full plan, skips trial):

```bash
curl -fsSL https://raw.githubusercontent.com/sandeep27choudhary/sre-ai-platform-distribution/main/scripts/bootstrap-install.sh \
  | bash -s -- --license-key 'YOUR_LICENSE_KEY'
```

### Option B — Helm repo

```bash
helm repo add sre-ai https://sandeep27choudhary.github.io/sre-ai-platform-distribution
helm repo update

helm upgrade --install sre-agent sre-ai/sre-ai-platform \
  -n sre-ai --create-namespace \
  --set-string license.trialStartEpoch="$(date +%s)"
```

> **Passwords are auto-generated on first install** — no need to pass them.  
> Helm generates a random `postgresPassword` (24 chars), `jwtSecretKey` (64 chars), and `sreAdminPassword` (20 chars) and stores them in a Kubernetes Secret. Values persist across upgrades.

### Option C — Clone and install locally

```bash
git clone --depth 1 https://github.com/sandeep27choudhary/sre-ai-platform-distribution.git
cd sre-ai-platform-distribution
./scripts/install.sh
```

---

## Get your credentials after install

Passwords are stored in a Kubernetes Secret. Retrieve them with:

```bash
# Admin UI password
kubectl get secret sre-agent-sre-ai-platform-platform \
  -n sre-ai \
  -o jsonpath='{.data.SRE_ADMIN_PASSWORD}' | base64 -d && echo

# Postgres password
kubectl get secret sre-agent-sre-ai-platform-platform \
  -n sre-ai \
  -o jsonpath='{.data.POSTGRES_PASSWORD}' | base64 -d && echo
```

> **Note:** The secret name uses the Helm release name as a prefix.  
> If you installed with a different release name, replace `sre-agent` with your release name.  
> Check with: `helm list -n sre-ai`

**Default admin email:** `admin@sre.local`

---

## Access the UI

```bash
kubectl port-forward svc/sre-platform-ui 3001:80 -n sre-ai
```

Open **http://localhost:3001** — log in with `admin@sre.local` and the password retrieved above.

---

## Verify the install

```bash
# All pods should be Running
kubectl get pods -n sre-ai

# API health + license status
kubectl port-forward svc/api 8000:8000 -n sre-ai &
curl -s http://localhost:8000/health | python3 -m json.tool
curl -s http://localhost:8000/license | python3 -m json.tool
```

---

## Upgrade

```bash
helm repo update
helm upgrade sre-agent sre-ai/sre-ai-platform -n sre-ai --reuse-values
```

Passwords and secrets are preserved automatically across upgrades.

---

## Apply a license key

```bash
helm upgrade sre-agent sre-ai/sre-ai-platform \
  -n sre-ai \
  --set-string license.key='YOUR_LICENSE_KEY' \
  --reuse-values
```

Verify:

```bash
curl -s http://localhost:8000/license | python3 -m json.tool
```

---

## Images

All images are published to GHCR under `ghcr.io/sandeep27choudhary/`:

| Image | Purpose |
|---|---|
| `sre-agent-api` | Core API + RCA engine |
| `sre-agent-worker` | Log ingestion + embedding |
| `sre-agent-llm-gateway` | Provider-agnostic LLM proxy |
| `sre-agent-platform-ui` | React/Next.js platform UI |
| `sre-agent-whatsapp` | WhatsApp gateway |

---

## Security

- Never commit license keys or RSA private keys to Git.
- Admin credentials are stored in Kubernetes Secrets — use RBAC to restrict access.
- All inference runs on-cluster via Ollama — no data leaves your cluster.

---

## Support

- Install issues → open an issue in this repository
- Product bugs / features → [rag-k8s-llm](https://github.com/sandeep27choudhary/rag-k8s-llm)
