# Enlight Lab — full OKE workflow

End-to-end: **Console → Kestra → build → OCIR → Kubernetes → health check**.

---

## Architecture

```text
Client browser
    │
    ├─ http://144-24-100-85.nip.io          → Enlight Lab console
    ├─ http://kestra.144-24-100-85.nip.io   → Kestra UI
    └─ http://app.144-24-100-85.nip.io      → Demo FastAPI app

Console "Run client demo"
    └─ POST Kestra API (cluster internal)
           └─ Flow: oke-deploy-simple (or oke-deploy-pipeline)
                  ├─ health check (before)
                  ├─ kubectl rollout restart (fastapi in enlight-staging)
                  ├─ health check (after)
                  └─ (full pipeline adds Kaniko build → OCIR push)
```

Same load balancer IP as your other Enlight Lab projects.

---

## One-time setup (Cloud Shell)

### 1. Push latest console image (Windows)

```powershell
cd D:\platform-poc\console
docker build --no-cache -t ap-mumbai-1.ocir.io/bmitpaosivqx/enlight-console:fix5 .
docker push ap-mumbai-1.ocir.io/bmitpaosivqx/enlight-console:fix5
```

### 2. Run complete setup

```bash
export CONSOLE_IMAGE=ap-mumbai-1.ocir.io/bmitpaosivqx/enlight-console:fix5
export INGRESS_HOST=144-24-100-85.nip.io
export PUBLIC_BASE_URL=http://144-24-100-85.nip.io

# Copy scripts from laptop or git clone when pushed
bash oke/scripts/oke-complete-setup.sh
```

### 3. Import flows (if script fails)

In **Kestra UI** → **Flows** → **Create** → **Import**:
- `kestra/flows/oke-deploy-simple.yaml` — start here
- `kestra/flows/oke-deploy-pipeline.yaml` — full build (needs secrets)

---

## Kestra secrets (full build pipeline only)

In Kestra UI → **Namespace** `main` → **Secrets**:

| Secret | Value |
|--------|--------|
| `OCIR_USERNAME` | `bmitpaosivqx/oracleidentitycloudservice/kirti@enlightlab.com` |
| `OCIR_TOKEN` | Your OCIR auth token |
| `GITHUB_TOKEN` | GitHub PAT (only if repo is private) |

---

## Run the demo (client workflow)

1. Open **http://144-24-100-85.nip.io**
2. Click **Run client demo ▶**
3. Click **Watch in Kestra →** (or open http://kestra.144-24-100-85.nip.io)
4. See execution: health → rollout → health
5. Open **http://app.144-24-100-85.nip.io** — demo app

---

## Flows

| Flow | What it does |
|------|----------------|
| `oke-deploy-simple` | Rollout + health (proves workflow) |
| `oke-deploy-pipeline` | Git clone → Kaniko build → OCIR push → rollout → health |

---

## Local vs cloud

| | Local (laptop) | Cloud (OKE) |
|--|----------------|-------------|
| Console | localhost:3100 | nip.io / devopslocalstack.enlightlab.com |
| Orchestration | Kestra + Dokploy | Kestra + kubectl |
| Build | Dagger + local registry | Kaniko + OCIR |
| Deploy | Dokploy | Kubernetes rollout |

---

## Production DNS (later)

| Hostname | Service |
|----------|---------|
| `devopslocalstack.enlightlab.com` | Console |
| `kestra.devopslocalstack.enlightlab.com` | Kestra |
| `app.devopslocalstack.enlightlab.com` | Demo app |

All point to the **same** load balancer IP.

---

## Troubleshooting

| Problem | Fix |
|---------|-----|
| Demo button fails | Import `oke-deploy-simple` flow in Kestra |
| Kestra blank page | Use `kestra.<host>` not `/kestra/ui` |
| Flow fails on rollout | Check RBAC: `kubectl apply -f oke/manifests/31-kestra-rbac.yaml` |
| Build fails | Add OCIR secrets; use `oke-deploy-simple` first |

---

## Files

```
oke/scripts/oke-complete-setup.sh   — run everything
oke/scripts/13-import-kestra-flows.sh
kestra/flows/oke-deploy-simple.yaml
kestra/flows/oke-deploy-pipeline.yaml
oke/manifests/30-kestra.yaml
oke/manifests/31-kestra-rbac.yaml
oke/ingress/kestra-host.yaml
oke/ingress/app-host.yaml
console/                           — Enlight Lab UI
```
