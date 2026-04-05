# Helm chart (public distribution copy)

This directory mirrors **helm/sre-agent** from the upstream **rag-k8s-llm** product repository. The chart is published to **GitHub Pages** from this repo via `.github/workflows/publish-helm-pages.yml`.

When you change the chart in the private monorepo, refresh this copy before release (from **rag-k8s-llm** repo root):

```bash
./scripts/sync-helm-to-distribution.sh
```

Then commit `distribution/helm/sre-agent` and push **main** on **sre-ai-platform-distribution** (or push the monorepo and sync the subtree to that remote).
