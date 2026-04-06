# SreA — Kubernetes SRE AI Platform

**SreA** is a self-hosted, production-grade SRE assistant for Kubernetes.  
Deterministic RCA · Forensic investigation · Autonomous incident response · Local-first, offline-capable.

Images: **GHCR** · Helm chart: **GitHub Pages** on this repo.

---

## Install (one command)

```bash
curl -fsSL https://raw.githubusercontent.com/sandeep27choudhary/sre-ai-platform-distribution/main/scripts/bootstrap-install.sh | bash
```

That's it. The installer will:
1. Clone this repo
2. Install the Helm chart into your cluster (namespace `sre-ai`)
3. Wait for all pods to be ready
4. Run a post-install health check

---

## Prerequisites

| Requirement | Version |
|---|---|
| Kubernetes | 1.25+ |
| Helm | 3.x |
| kubectl | configured for your cluster |

---

## Options

### With a license key

```bash
curl -fsSL https://raw.githubusercontent.com/sandeep27choudhary/sre-ai-platform-distribution/main/scripts/bootstrap-install.sh \
  | bash -s -- --license-key 'YOUR_LICENSE_KEY'
```

### Air-gap / minikube (images pre-loaded locally)

```bash
curl -fsSL https://raw.githubusercontent.com/sandeep27choudhary/sre-ai-platform-distribution/main/scripts/bootstrap-install.sh \
  | bash -s -- --offline
```

### Custom namespace or release name

```bash
curl -fsSL https://raw.githubusercontent.com/sandeep27choudhary/sre-ai-platform-distribution/main/scripts/bootstrap-install.sh \
  | bash -s -- --namespace my-sre --release my-platform
```

### All flags

| Flag | Default | Description |
|---|---|---|
| `--license-key KEY` | — | Activate full plan, skip trial |
| `--namespace NS` | `sre-ai` | Kubernetes namespace |
| `--release NAME` | `sre-agent` | Helm release name |
| `--offline` | — | `imagePullPolicy: Never` (minikube / air-gap) |
| `--no-check` | — | Skip post-install health check |

---

## Helm repo (Option B)

```bash
helm repo add sre-ai https://sandeep27choudhary.github.io/sre-ai-platform-distribution
helm repo update
helm upgrade --install sre-agent sre-ai/sre-ai-platform --namespace sre-ai --create-namespace --set-string license.trialStartEpoch="$(date +%s)"
```

> The release name (`sre-agent` above) determines your secret name: `sre-agent-sre-ai-platform-platform`.

## Clone and install locally (Option C)

```bash
git clone --depth 1 https://github.com/sandeep27choudhary/sre-ai-platform-distribution.git
cd sre-ai-platform-distribution
./scripts/install.sh
```

> **Passwords are auto-generated on first install.**  
> Helm generates `postgresPassword` (24 chars), `jwtSecretKey` (64 chars), and `sreAdminPassword` (20 chars), stored in a Kubernetes Secret. All values persist across upgrades.

---

## After install

### Get your credentials

First, find your release name:

```bash
helm list -n sre-ai
```

Then retrieve the admin password (replace `<release>` with your release name):

```bash
kubectl get secret <release>-sre-ai-platform-platform -n sre-ai -o jsonpath='{.data.SRE_ADMIN_PASSWORD}' | base64 -d && echo
```

Example — if your release is `sre-agent`:

```bash
kubectl get secret sre-agent-sre-ai-platform-platform -n sre-ai -o jsonpath='{.data.SRE_ADMIN_PASSWORD}' | base64 -d && echo
```

Example — if your release is `sre-ai-platform` (Helm repo default):

```bash
kubectl get secret sre-ai-platform-sre-ai-platform-platform -n sre-ai -o jsonpath='{.data.SRE_ADMIN_PASSWORD}' | base64 -d && echo
```

**Default admin email:** `admin@sre.local`

### Access the UI

```bash
kubectl port-forward svc/sre-platform-ui 3001:80 -n sre-ai
```

Open **http://localhost:3001** and log in with `admin@sre.local`.

### Run the health check

The health check runs automatically after install. You can also run it any time:

```bash
./scripts/post-install-check.sh
```

Checks: pod readiness · API health · database · login · Ollama models · agent query · platform UI.

---

## Upgrade

```bash
helm repo update
helm upgrade sre-agent sre-ai/sre-ai-platform -n sre-ai --reuse-values
```

Secrets and passwords are preserved automatically.

---

## Apply a license key after install

```bash
helm upgrade sre-agent sre-ai/sre-ai-platform \
  --namespace sre-ai \
  --set-string license.key='YOUR_LICENSE_KEY' \
  --reuse-values
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

- Admin credentials are stored in Kubernetes Secrets — restrict access with RBAC.
- All inference runs on-cluster via Ollama — no data leaves your cluster.
- License keys and RSA private keys must never be committed to Git.

---

## Troubleshooting

```bash
# Check pod status
kubectl get pods -n sre-ai

# API logs
kubectl logs -n sre-ai deploy/api --tail=50

# Worker logs
kubectl logs -n sre-ai deploy/worker --tail=30

# Re-run health check
./scripts/post-install-check.sh --namespace sre-ai --release sre-agent
```

## Support

- Install issues → open an issue in this repository
- Product bugs / features → [rag-k8s-llm](https://github.com/sandeep27choudhary/rag-k8s-llm)
