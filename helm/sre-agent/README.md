# sre-agent Helm Chart

Production-ready, lightweight Helm chart for the **Kubernetes Forensic SRE Troubleshooting Assistant**. Runs locally on minikube or in real clusters with minimal dependencies, low resource usage, and clean service separation.

## Features

- **Under 10 services**: api (sre-core), **llm-gateway** (provider-agnostic), ollama (sre-llm), postgres, worker (sre-rag), sre-platform-ui, loki, fluent-bit, redis, minio
- **Multi-LLM support**: All LLM traffic goes through llm-gateway. Default provider: Ollama (offline). Optional: OpenAI, OpenRouter, Gemini when API keys are supplied.
- **Local-first**: Works with `imagePullPolicy: Never` for minikube; configurable for registries
- **LLM scales independently**: Optional HPA for Ollama; core and data plane stay under 512Mi
- **Deterministic first**: Core + embedded data plane (indexer, snapshot, anomaly) in one pod; no extra data-plane pod
- **RBAC**: Least-privilege; read-only cluster access for the API (mcp-readonly-sa)
- **ConfigMaps** for Loki and Fluent Bit; **PVCs** only for Postgres and Ollama (RAG + models)

## Prerequisites

- Kubernetes >= 1.25.0
- Helm 3
- (Optional) Ingress controller (e.g. nginx) if using Ingress
- For **minikube**: build images locally and load into minikube; set `offlineMode: true` or `image.pullPolicy: Never` for api/worker

## Install

### 1. Create namespace and install

```bash
# Default: install into namespace sre-ai (create it if missing)
helm install sre-agent ./helm/sre-agent -n sre-ai --create-namespace

# Or install into a custom namespace
helm install sre-agent ./helm/sre-agent -n my-sre --create-namespace
```

### 2. Minikube (local images)

Build and load images into minikube, then install with offline-friendly settings:

```bash
eval $(minikube docker-env -p sre-ai-lab)
docker build -t rag-k8s-llm-api:latest ./api
docker build -t rag-k8s-llm-llm-gateway:latest ./llm-gateway
docker build -t rag-k8s-llm-worker:latest ./worker

helm install sre-agent ./helm/sre-agent -n sre-ai --create-namespace \
  --set offlineMode=true \
  --set sreCore.image.pullPolicy=Never \
  --set llmGateway.image.pullPolicy=Never \
  --set sreRag.worker.image.pullPolicy=Never
```

### 3. With custom values

```bash
helm install sre-agent ./helm/sre-agent -n sre-ai --create-namespace \
  -f my-values.yaml
```

## Upgrade / Uninstall

```bash
helm upgrade sre-agent ./helm/sre-agent -n sre-ai
helm uninstall sre-agent -n sre-ai
```

## Configuration

| Key | Description | Default |
|-----|-------------|---------|
| `sreCore.enabled` | Deploy API (core + data plane) | `true` |
| `sreCore.replicas` | API replicas | `1` |
| `sreCore.resources` | CPU/memory requests and limits | 200m/256Mi–500m/512Mi |
| `sreLlm.enabled` | Deploy Ollama | `true` |
| `sreLlm.replicas` | Ollama replicas | `1` |
| `sreLlm.persistence.size` | PVC size for models | `10Gi` |
| `sreLlm.hpa.enabled` | HPA for Ollama | `false` |
| `sreRag.postgres.persistence.size` | Postgres PVC size | `2Gi` |
| `sreUi.enabled` | Deploy legacy Open WebUI | `false` |
| `config.llmModel` | Default LLM model name | `llama3.2` |
| `config.llmGatewayUrl` | LLM gateway base URL (core and worker) | `http://llm-gateway:8000` |
| `llmGateway.enabled` | Deploy LLM gateway | `true` |
| `llmGateway.provider` | `ollama` \| `openai` \| `openrouter` \| `gemini` | `ollama` |
| `llmGateway.existingSecret` | K8s secret name for API keys (keys: openai-api-key, etc.) | `""` |
| `config.postgresPassword` | Postgres password | `rag` (override in prod) |
| `ingress.enabled` | Create Ingress for UI/API | `true` |
| `ingress.hosts` | Hosts and paths | `sre-agent.local` |
| `offlineMode` | Force imagePullPolicy: Never | `false` |
| `rbac.create` | Create RBAC (SA, ClusterRole, bindings) | `true` |

## Service grouping (logical)

| Deployment | Purpose | Components (logical) |
|------------|---------|----------------------|
| **api** (sre-core) | Investigation + reasoning | intent-engine, entity-resolver, playbook-orchestrator, specialist-investigators, evidence-graph-builder, cluster-indexer, snapshot-cache, anomaly-detector, api-server |
| **llm-gateway** | Provider-agnostic LLM routing | /generate, /embed, /models; routes to Ollama (default), OpenAI, OpenRouter, or Gemini |
| **ollama** (sre-llm) | Local model server (default backend) | ollama, llm-reasoner |
| **postgres** + **worker** (sre-rag) | Knowledge base | embedding-service, vector-store (pgvector), memory-manager (worker) |
| **sre-platform-ui** | Primary chat/admin frontend | custom SRE UI |
| **loki** | Log store | — |
| **fluent-bit** | Log shipper | — |
| **redis** | Cache | — |

## Networking

- **Internal**: All services use ClusterIP. API, Ollama, Postgres, Redis, Loki, Worker communicate inside the cluster.
- **External**: Ingress (if enabled) exposes SRE Platform UI and API; or use `kubectl port-forward` for UI and API.

## Security

- **Service accounts**: API uses `mcp-readonly-sa` (ClusterRole: get/list/watch on pods, events, deployments, etc.; no write).
- **Secrets**: Postgres password is in values; for production use `existingPostgresSecret` or external secrets.
- **Legacy Open WebUI**: Disabled by default. Enable only if explicitly needed.

## Performance

- **Core and data plane**: Target &lt; 500Mi memory per pod.
- **LLM**: Can scale separately (HPA or manual replicas); 2–4Gi typical per Ollama pod.
- **Minikube**: Chart is designed to run on minikube with ~4GB RAM (tune replicas/resources as needed).

## Failure tolerance

- **Core restart**: Stateless; cluster index and snapshot rebuild on startup.
- **RAG**: Postgres uses PVC; data persists across restarts.
- **Ollama**: Use persistence for models; otherwise models are re-downloaded after restart.

## Output (chart structure)

```
helm/sre-agent/
  Chart.yaml
  values.yaml
  README.md
  templates/
    _helpers.tpl
    namespace.yaml
    rbac.yaml
    configmap-loki.yaml
    configmap-fluentbit.yaml
    pvc-postgres.yaml
    pvc-ollama.yaml
    deployment-sre-core.yaml
    deployment-sre-llm.yaml
    statefulset-postgres.yaml
    deployment-worker.yaml
    deployment-sre-ui.yaml
    deployment-loki.yaml
    deployment-fluentbit.yaml
    deployment-redis.yaml
    ingress.yaml
    hpa-sre-llm.yaml
    NOTES.txt
```

## Install command example

```bash
helm install sre-agent ./helm/sre-agent -n sre-ai --create-namespace
```

Philosophy: **Lightweight, modular, deterministic first. LLM is optional compute, not a core dependency.**
