# DevOps Local Stack

**`devopslocalstack.enlightlab.com`** — Enlight Lab's open-source delivery platform.  
Local demo on your laptop today; Oracle OKE (free tier) in production.

Full architecture: [docs/devopslocalstack-architecture.md](docs/devopslocalstack-architecture.md)

## What you get

| Layer | What it does |
|-------|----------------|
| **Platform Console** | One client URL — deploy, status, guided demo |
| **Local stack** | Kestra, Dokploy, registry, Netdata |
| **Sample app** | FastAPI + Dagger pipeline |
| **Oracle OKE** | Terraform, OCIR, single-LB ingress |

## Flow (local)

```text
devopslocalstack.enlightlab.com  (or localhost:3100 locally)
       ↓
Run client demo
       ↓
Kestra → Dagger → registry → Dokploy → /health
```

## One LoadBalancer on OKE (free tier)

All hostnames → **same IP**:

| Host | Service |
|------|---------|
| `devopslocalstack.enlightlab.com` | Platform console |
| `app.devopslocalstack.enlightlab.com` | FastAPI |
| `kestra.devopslocalstack.enlightlab.com` | Kestra (phase 2) |
| `gitops.devopslocalstack.enlightlab.com` | ArgoCD (phase 2) |
| `metrics.devopslocalstack.enlightlab.com` | Grafana (phase 2) |

## Quick start (local)

```powershell
.\scripts\start-platform.ps1
```

Open **http://localhost:3100**

## OKE migration

```powershell
cd oke\scripts
.\01-check-prereqs.ps1
# ... through 06-deploy-manifests.ps1
```

Guide: [docs/oke-getting-started.md](docs/oke-getting-started.md)

## Final tech on OKE

| Role | Tool |
|------|------|
| Kubernetes | **OKE** (Oracle) |
| Registry | **OCIR** |
| Orchestration | **Kestra** |
| Build | **Dagger** |
| Deploy | **ArgoCD** (replaces Dokploy) |
| Ingress | **nginx** (1 free LB) |
| Monitoring | **Prometheus + Grafana** |
| UI | **This console** |
| Source | **GitHub** |
