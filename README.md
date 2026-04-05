# SRE AI Platform — install guide (public)

This repository contains **documentation, the packaged Helm chart source (`helm/sre-agent`)**, and helper scripts to install the **Kubernetes Forensic SRE Assistant** on your cluster. Application **source code** lives in the upstream repo; images are pulled from **GitHub Container Registry (GHCR)** and the **Helm chart index** is served from **GitHub Pages** on this repository.

**Upstream product repository:** [rag-k8s-llm](https://github.com/sandeep27choudhary/rag-k8s-llm) (full source and docs; may be private — this repo stays public for installs).

---

## Prerequisites

- Kubernetes **1.25+**
- **kubectl** configured for your cluster
- **Helm 3**
- Optional: **minikube** or **kind** for local testing

---

## Option A — Helm repository (recommended, no Git clone of product source)

When the vendor publishes the chart to GitHub Pages (or another HTTPS Helm repo), use:

```bash
helm repo add sre-ai https://sandeep27choudhary.github.io/sre-ai-platform-distribution
helm repo update
helm install sre-ai sre-ai/sre-ai-platform -n sre-ai --create-namespace \
  -f examples/values-example.yaml \
  --set-string config.jwtSecretKey="$(openssl rand -hex 32)" \
  --set-string config.postgresPassword="$(openssl rand -hex 16)" \
  --set-string config.sreAdminPassword="$(openssl rand -base64 24)" \
  --set-string license.trialStartEpoch="$(date +%s)" \
  --set license.trialDays=7
```

Replace `examples/values-example.yaml` with your path after copying it locally. For paid production installs, add `-f examples/values-production.yaml` (or merge its settings) and set `license.key`.  
Edit `license.key` and `license.publicKey` in values when your vendor supplies them (see **License** below).

If the Helm repo URL differs, check with your vendor.

---

## Option B — Bootstrap script (clone this repo, install from bundled chart)

The bootstrap script clones **this** repository (which contains **`helm/sre-agent` only** as the installable chart) and runs `./scripts/install.sh`.

```bash
curl -fsSL https://raw.githubusercontent.com/sandeep27choudhary/sre-ai-platform-distribution/main/scripts/bootstrap-install.sh | bash -s --
```

With a license key:

```bash
curl -fsSL https://raw.githubusercontent.com/sandeep27choudhary/sre-ai-platform-distribution/main/scripts/bootstrap-install.sh | bash -s -- --license-key 'YOUR_LICENSE_KEY'
```

With extra values (paths are relative to the cloned repo):

```bash
curl -fsSL https://raw.githubusercontent.com/sandeep27choudhary/sre-ai-platform-distribution/main/scripts/bootstrap-install.sh | bash -s -- \
  --license-key 'YOUR_LICENSE_KEY' --values examples/values-production.yaml
```

**Override clone URL or branch** (forks or testing):

```bash
export SRE_BOOTSTRAP_REPO="https://github.com/sandeep27choudhary/sre-ai-platform-distribution.git"
export SRE_BOOTSTRAP_BRANCH="main"
curl -fsSL https://raw.githubusercontent.com/sandeep27choudhary/sre-ai-platform-distribution/main/scripts/bootstrap-install.sh | bash -s --
```

---

## Option C — Clone this repo and run the installer locally

```bash
git clone --depth 1 https://github.com/sandeep27choudhary/sre-ai-platform-distribution.git
cd sre-ai-platform-distribution
./scripts/install.sh --license-key 'YOUR_LICENSE_KEY'
```

**Full product source** (build images from source, develop features) is in the private upstream [rag-k8s-llm](https://github.com/sandeep27choudhary/rag-k8s-llm) repository — not required for a normal GHCR-based install from this chart.

---

## License keys (RS256)

- Your vendor sends you a **single line** `LICENSE_KEY=...` (JWT). **Do not** share it publicly.
- **Do not** commit license keys or RSA **private** keys to Git.
- You may receive an **RSA public** PEM to place under `license.publicKey` in your values file (or it may be baked into the vendor’s API image).

**Apply a license after install:**

```bash
helm upgrade sre-ai sre-ai/sre-ai-platform -n sre-ai \
  --set-string license.key='YOUR_LICENSE_KEY' \
  --reuse-values
```

(Adjust release name and repo if your install differs.)

---

## Verify

```bash
kubectl get pods -n sre-ai
kubectl port-forward -n sre-ai svc/sre-platform-ui 3001:80
kubectl port-forward -n sre-ai svc/api 8000:8000
curl -sS http://localhost:8000/license
```

Open `http://localhost:3001` for the platform UI. Default admin credentials must be set in your values (see `examples/values-example.yaml`); do **not** use `CHANGEME` in production.

---

## Images

First-party images are published to **GHCR** under `ghcr.io/sandeep27choudhary/sre-agent-*` (see `examples/values-example.yaml`). If pulls fail with `unauthorized`, the packages may be private — ask your vendor for pull credentials or for packages to be public.

---

## Security

- Never commit **license keys**, **RSA private keys**, or **HMAC signing secrets**.
- See the vendor’s **secure delivery** documentation in the upstream repo (`docs/SECURE_CUSTOMER_DELIVERY.md`).

---

## Support

Issues for **installing from this guide** may be opened in this repository. **Product bugs** and **feature requests** belong to the upstream [rag-k8s-llm](https://github.com/sandeep27choudhary/rag-k8s-llm) repository.
