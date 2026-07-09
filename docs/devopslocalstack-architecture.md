# DevOps Local Stack — architecture & final tech on OKE

**Product URL:** `https://devopslocalstack.enlightlab.com`  
**Brand:** Enlight Lab · DevOps Local Stack

---

## One LoadBalancer rule (Oracle free tier)

Oracle Always Free gives you **one flexible LoadBalancer**. We use it like this:

```text
                    ONE public IP (nginx ingress)
                              │
        ┌─────────────────────┼─────────────────────┐
        ▼                     ▼                     ▼
 devopslocalstack      app.devopslocalstack   kestra.devopslocalstack
 .enlightlab.com       .enlightlab.com        .enlightlab.com
 (console)             (FastAPI)              (phase 2)
```

**Important:** Multiple hostnames does **not** mean multiple load balancers.  
All DNS A records point to the **same IP**. Kubernetes ingress routes by hostname.

| DNS host | Points to | Service |
|----------|-----------|---------|
| `devopslocalstack.enlightlab.com` | Same IP | Platform console |
| `app.devopslocalstack.enlightlab.com` | Same IP | FastAPI app |
| `kestra.devopslocalstack.enlightlab.com` | Same IP | Kestra (phase 2) |
| `gitops.devopslocalstack.enlightlab.com` | Same IP | ArgoCD (phase 2) |
| `metrics.devopslocalstack.enlightlab.com` | Same IP | Grafana (phase 2) |

---

## Tech stack: local today → OKE final

| Role | Local (laptop) | Final on OKE |
|------|----------------|--------------|
| **Client UI** | Platform Console `localhost:3100` | Same console at `devopslocalstack.enlightlab.com` |
| **Orchestration** | Kestra (Docker) | Kestra (Helm on OKE) |
| **Build pipeline** | Dagger CLI | Dagger (inside Kestra jobs / CI) |
| **Image registry** | Local registry `:5000` | **OCIR** (Oracle Container Registry) |
| **Deploy** | Dokploy | **ArgoCD** (GitOps — pull from Git, sync to cluster) |
| **Sample app** | FastAPI in Dokploy | FastAPI Deployment on OKE |
| **Monitoring** | Netdata | **Prometheus + Grafana** (or Netdata DaemonSet) |
| **Ingress** | Docker published ports | **nginx ingress** (1 LB IP) |
| **Infrastructure** | Docker Desktop | **OKE** + Terraform |
| **Secrets** | `.env` files | Kubernetes Secrets + OCI Vault (later) |
| **Source code** | GitHub | GitHub (unchanged) |

### What we drop on OKE
- Docker Desktop as runtime (replaced by OKE nodes)
- Dokploy (replaced by ArgoCD)
- Local registry (replaced by OCIR)
- `host.docker.internal` hacks (real DNS + ingress)

### What stays the same
- **GitHub** as source of truth
- **Kestra** as the “click to run pipeline” brain
- **Dagger** for reproducible builds
- **FastAPI** sample app
- **Platform Console** as the one client-facing UI

---

## End-to-end flow on OKE (final)

```text
Client opens devopslocalstack.enlightlab.com
       ↓
Clicks "Run client demo"
       ↓
Kestra (on OKE) runs pipeline:
  clone GitHub → Dagger build → push OCIR → update GitOps manifest
       ↓
ArgoCD syncs new image to cluster
       ↓
Health check on app.devopslocalstack.enlightlab.com/health
       ↓
Metrics visible at metrics.devopslocalstack.enlightlab.com
```

---

## Phased rollout

| Phase | What's live | LB usage |
|-------|-------------|----------|
| **1** (now) | OKE + ingress + console + FastAPI | 1 LB |
| **2** | + Kestra on cluster | same LB |
| **3** | + ArgoCD, retire Dokploy | same LB |
| **4** | + Grafana, TLS (cert-manager) | same LB |

---

## Free tier sizing (OKE)

| Resource | Value |
|----------|-------|
| Node shape | `VM.Standard.A1.Flex` (ARM) |
| OCPUs | 2 |
| Memory | 12 GB |
| Worker nodes | 1 |
| Load balancers | **1** (nginx only) |

---

## Related docs

- [oke-getting-started.md](oke-getting-started.md) — install steps
- [enlightlab-roadmap.md](enlightlab-roadmap.md) — client roadmap
