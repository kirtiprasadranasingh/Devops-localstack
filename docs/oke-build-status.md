# OKE build status — DevOps Local Stack

## Done in repo (ready to run)

| Item | Status |
|------|--------|
| Terraform OKE + OCIR | `oke/terraform/` — **init + validate OK** |
| K8s manifests | `oke/manifests/` |
| Ingress (1 LB) | `oke/ingress/devopslocalstack.yaml` |
| ArgoCD (phase 2) | `oke/scripts/07-install-argocd.ps1` |
| GitOps app | `oke/gitops/` |
| Master script | `oke/scripts/build-oke.ps1` |
| OCI CLI | Installed via winget (restart terminal for PATH) |

## Blocker: OCI API auth (401)

`terraform plan` failed with **401 NotAuthenticated**.

Your `~/.oci/config` exists but the API key does not match Oracle Console.

### Fix (5 minutes)

1. Open **OCI Console** → Profile (top right) → **API Keys**
2. Check fingerprint matches config: `85:26:bd:72:...`
3. If not, **Add API Key** → upload public key:
   ```
   C:\Users\KIRTI\.oci\oci_api_key_public.pem
   ```
   (Generate with `openssl` or re-run `oci setup config` in a **new** terminal)
4. Verify:
   ```powershell
   cd D:\platform-poc\oke\scripts
   .\verify-oci-auth.ps1
   ```

## After auth works — run build

```powershell
cd D:\platform-poc\oke\scripts

.\verify-oci-auth.ps1          # must pass
.\02-terraform-apply.ps1       # ~15 min — creates OKE cluster
.\03-kubeconfig.ps1
.\04-install-platform.ps1      # nginx ingress → ONE public IP
.\05-push-images.ps1           # needs Docker Desktop running
.\06-deploy-manifests.ps1
.\07-install-argocd.ps1        # GitOps (optional phase 2)
```

Or one command (after auth fixed):

```powershell
.\build-oke.ps1 -Step all
```

## DNS (same IP for all)

```
devopslocalstack.enlightlab.com
app.devopslocalstack.enlightlab.com
```

## Docker Desktop

Start Docker Desktop before step 05 (image push).
