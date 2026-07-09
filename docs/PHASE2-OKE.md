# Enlight Lab — Phase 2 (GitOps + Monitoring)

Phase 1 is done: **Console → Kestra → rollout** works.

Phase 2 adds:
- **ArgoCD** at `/gitops`
- **Grafana** at `/metrics`
- **GitOps app** (demo ConfigMap in `enlight-staging`)
- **Optional** OCIR secrets for future build pipeline

---

## One command (Cloud Shell)

```bash
export INGRESS_HOST=144-24-100-85.nip.io
bash oke/scripts/15-phase2-setup.sh
```

Takes ~10–15 minutes (ArgoCD ~3 min, Grafana helm ~10 min).

Skip Grafana if slow:

```bash
SKIP_MONITORING=1 bash oke/scripts/15-phase2-setup.sh
```

---

## After install — verify

| URL | Login |
|-----|-------|
| http://144-24-100-85.nip.io/gitops | ArgoCD `admin` + password from script output |
| http://144-24-100-85.nip.io/metrics | Grafana `admin` / `admin` |
| http://144-24-100-85.nip.io | Console should show GitOps + Metrics links green |

Get ArgoCD password anytime:

```bash
kubectl get secret argocd-initial-admin-secret -n argocd -o jsonpath='{.data.password}' | base64 -d; echo
```

---

## GitOps app (ArgoCD)

Application `enlight-demo-staging` syncs a **safe ConfigMap** in `enlight-staging` — it does **not** replace your running FastAPI.

**If ArgoCD shows "repo not found":** push this repo to GitHub (`oke/gitops/...`), then:

```bash
kubectl apply -f oke/gitops/argocd/fastapi-staging.yaml
```

---

## Optional — OCIR secrets (for future full build)

```bash
export OCIR_USERNAME='bmitpaosivqx/YOUR_OCI_USERNAME'
export OCIR_TOKEN='YOUR_AUTH_TOKEN'
export KESTRA_USER=admin@enlightlab.com
export KESTRA_PASS=Admin1234
bash oke/scripts/16-kestra-secrets.sh
```

**Note:** Kaniko build in `oke-deploy-pipeline` needs Kestra Enterprise Kubernetes runner. For now:
1. Build/push image on Windows: `docker build` + `docker push`
2. Run flow `oke-deploy-rollout` in Kestra (rollout + health)

---

## Phase 3 (later)

- Production DNS → `devopslocalstack.enlightlab.com`
- Persistent Kestra database
- Kestra secrets in Kubernetes Secret (not env)
