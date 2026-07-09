# Enlight Lab — Full OKE Pipeline

## What this project does

One client console on Oracle OKE that runs the full delivery story:

```text
Console → Kestra → Dagger → OCIR → Git commit → ArgoCD → OKE → health check
```

| Component | Role |
|-----------|------|
| **Platform Console** | Client UI — one button to deploy |
| **Kestra** | Orchestrates the pipeline |
| **Dagger** | Builds the FastAPI image from GitHub |
| **OCIR** | Stores container images |
| **ArgoCD** | GitOps — syncs manifests from Git to OKE |
| **Oracle OKE** | Runs the application |

Dokploy is **local laptop only** — not used on OKE.

## Live URLs (nip.io testing)

| Service | URL |
|---------|-----|
| Console | http://144-24-100-85.nip.io |
| Demo app | http://app.144-24-100-85.nip.io |
| Kestra | http://kestra.144-24-100-85.nip.io |
| ArgoCD | https://argocd.enlightlab.com |

## Deploy to cluster (Cloud Shell)

```bash
# 1. Secrets (OCIR + GitHub write access)
export KESTRA_URL=http://kestra.144-24-100-85.nip.io
export OCIR_USERNAME='bmitpaosivqx/<oci-user>'
export OCIR_TOKEN='<auth-token>'
export GITHUB_TOKEN='ghp_...'   # write access to Devops-localstack
bash oke/scripts/16-kestra-secrets.sh

# 2. Full pipeline setup
export CONSOLE_IMAGE=ap-mumbai-1.ocir.io/bmitpaosivqx/enlight-console:v13
bash oke/scripts/25-setup-full-pipeline.sh
```

## Build console image (laptop)

```powershell
cd D:\platform-poc\console
docker build -t ap-mumbai-1.ocir.io/bmitpaosivqx/enlight-console:v13 .
docker push ap-mumbai-1.ocir.io/bmitpaosivqx/enlight-console:v13
```

## Kestra flow

**`oke-dagger-gitops-pipeline`** (`kestra/flows/oke-dagger-gitops-pipeline.yaml`):

1. Health check (before)
2. Clone `Devops-localstack` from GitHub
3. Dagger build `sample-app/fastapi-minimal` → push to OCIR
4. Update `oke/gitops/apps/fastapi/deployment.yaml` → git push
5. ArgoCD auto-sync → rollout on OKE
6. Health check (after)

Smoke test only: `oke-deploy-simple` (rollout restart, no build).

## GitOps

- ArgoCD Application: `oke/gitops/argocd/fastapi-minimal.yaml`
- Manifests: `oke/gitops/apps/fastapi/`
- Repo: https://github.com/kirtiprasadranasingh/Devops-localstack.git

## Important

- **selfheal** (`enlight-staging` / `fastapi`) is separate — do not touch
- Demo app: `enlight-platform` / `fastapi-minimal`
- Push this repo to GitHub before running the full pipeline (Kestra clones from Git)
