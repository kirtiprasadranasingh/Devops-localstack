# OKE Terraform — Enlight DevOps Stack

See full guide: [docs/oke-getting-started.md](../../docs/oke-getting-started.md)

## Quick apply

```powershell
cd D:\platform-poc\oke\scripts
.\01-check-prereqs.ps1
.\02-terraform-apply.ps1
```

## terraform.tfvars

```hcl
compartment_id  = "ocid1.compartment.oc1..xxxxxxxx"
region          = "ap-mumbai-1"
cluster_name    = "enlight-devops"
node_ocpus      = 2
node_memory_gbs = 12
node_count      = 1
```

## Outputs

```powershell
terraform output ocir_fastapi_repo
terraform output ocir_console_repo
terraform output -raw configure_kubectl
```

## Destroy

```powershell
terraform destroy
```
