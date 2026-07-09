# OKE migration — DevOps Local Stack

**Product:** `devopslocalstack.enlightlab.com`

## What you get on OKE (phase 1)

| URL | App |
|-----|-----|
| `devopslocalstack.enlightlab.com` | Platform Console |
| `app.devopslocalstack.enlightlab.com` | FastAPI sample app |

**One LoadBalancer IP** serves both (and more in phase 2).

---

## Before you start

### 1. Install OCI CLI

https://docs.oracle.com/en-us/iaas/Content/API/SDKDocs/cliinstall.htm

```powershell
oci setup config
```

### 2. Create terraform.tfvars

```powershell
cd D:\platform-poc\oke\terraform
copy terraform.tfvars.example terraform.tfvars
```

Set `compartment_id` from OCI Console → Identity → Compartments.

### 3. Run scripts in order

```powershell
cd D:\platform-poc\oke\scripts
.\01-check-prereqs.ps1
.\02-terraform-apply.ps1
.\03-kubeconfig.ps1
.\04-install-platform.ps1
.\05-push-images.ps1
.\06-deploy-manifests.ps1
```

---

## DNS — one IP for everything

```powershell
kubectl get svc -n ingress-nginx ingress-nginx-controller
```

Point **all** A records to that IP:

```
devopslocalstack.enlightlab.com
app.devopslocalstack.enlightlab.com
kestra.devopslocalstack.enlightlab.com   (phase 2)
gitops.devopslocalstack.enlightlab.com    (phase 2)
metrics.devopslocalstack.enlightlab.com   (phase 2)
```

**Hosts file test:**

```
<LB_IP>  devopslocalstack.enlightlab.com
<LB_IP>  app.devopslocalstack.enlightlab.com
```

---

## Architecture

See [devopslocalstack-architecture.md](devopslocalstack-architecture.md) for final tech stack on OKE.
