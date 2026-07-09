# Enlight Lab on Oracle OKE — Path A (existing cluster)

**Full workflow guide:** [docs/FULL-WORKFLOW-OKE.md](../docs/FULL-WORKFLOW-OKE.md)

## Quick start (Cloud Shell)

```bash
export CONSOLE_IMAGE=ap-mumbai-1.ocir.io/bmitpaosivqx/enlight-console:fix5
export INGRESS_HOST=144-24-100-85.nip.io
export PUBLIC_BASE_URL=http://144-24-100-85.nip.io

bash oke/scripts/oke-complete-setup.sh
```

## URLs (testing without DNS)

| Service | URL |
|---------|-----|
| Console | http://144-24-100-85.nip.io |
| Kestra | http://kestra.144-24-100-85.nip.io |
| Demo app | http://app.144-24-100-85.nip.io |

## Client demo workflow

1. Open console → **Run client demo**
2. Kestra runs `oke-deploy-simple`: health → rollout → health
3. Watch execution in Kestra UI

## Scripts

| Script | Purpose |
|--------|---------|
| `oke-complete-setup.sh` | Everything in one go |
| `path-a-deploy.sh` | Core workloads only |
| `13-import-kestra-flows.sh` | Import pipeline YAML |
| `07-install-argocd.ps1` | ArgoCD (phase 2) |

## Flows

- `kestra/flows/oke-deploy-simple.yaml` — rollout + verify (default)
- `kestra/flows/oke-deploy-pipeline.yaml` — Kaniko build + OCIR + rollout
