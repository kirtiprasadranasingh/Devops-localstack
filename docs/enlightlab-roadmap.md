# DevOps Local Stack — Client roadmap

**Product:** `devopslocalstack.enlightlab.com`  
**Architecture:** [devopslocalstack-architecture.md](devopslocalstack-architecture.md)

## Phase 1 — Done (local)

- [x] Pipeline: Git → Kestra → Dagger → registry → Dokploy → health
- [x] Platform Console at `localhost:3100`
- [x] One-click **Run client demo**

## Phase 2 — OKE foundation

- [ ] `terraform apply` (free tier ARM node)
- [ ] nginx ingress — **1 LoadBalancer IP**
- [ ] Console + FastAPI on OCIR
- [ ] DNS: `devopslocalstack.enlightlab.com` → LB IP

## Phase 3 — Full stack on same LB

| Host | Service |
|------|---------|
| `devopslocalstack.enlightlab.com` | Console |
| `app.devopslocalstack.enlightlab.com` | FastAPI |
| `kestra.devopslocalstack.enlightlab.com` | Kestra |
| `gitops.devopslocalstack.enlightlab.com` | ArgoCD |
| `metrics.devopslocalstack.enlightlab.com` | Grafana |

## Phase 4 — Client polish

- [ ] TLS (cert-manager)
- [ ] Login on console
- [ ] OCI cost tags / Infracost panel

## What the client sees

1. Bookmark **`devopslocalstack.enlightlab.com`**
2. Click **Run client demo**
3. All services green
4. Open **`app.devopslocalstack.enlightlab.com/health`**
