#Requires -Version 5.1
<#
.SYNOPSIS
  Install ArgoCD on OKE (GitOps — replaces Dokploy in cloud).
#>

$ErrorActionPreference = "Stop"

Write-Host ""
Write-Host "==> ArgoCD namespace" -ForegroundColor Cyan
kubectl create namespace argocd --dry-run=client -o yaml | kubectl apply -f -

Write-Host ""
Write-Host "==> Install ArgoCD (HA disabled for free tier)" -ForegroundColor Cyan
kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml

Write-Host ""
Write-Host "==> Wait for argocd-server" -ForegroundColor Cyan
kubectl rollout status deployment/argocd-server -n argocd --timeout=300s

Write-Host ""
Write-Host "==> Patch ArgoCD service to ClusterIP (ingress handles external access)" -ForegroundColor Cyan
kubectl patch svc argocd-server -n argocd -p '{"spec": {"type": "ClusterIP"}}' 2>$null

Write-Host ""
Write-Host "ArgoCD admin password:" -ForegroundColor Yellow
$secret = kubectl get secret argocd-initial-admin-secret -n argocd -o jsonpath="{.data.password}" 2>$null
if ($secret) {
  $pwd = [System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String($secret))
  Write-Host "  user: admin"
  Write-Host "  pass: $pwd"
}
else {
  Write-Host "  (secret not ready yet — run again in 1 min)" -ForegroundColor DarkGray
}

Write-Host ""
Write-Host "==> Configure ArgoCD root path /gitops (same hostname as console)" -ForegroundColor Cyan
kubectl patch configmap argocd-cmd-params-cm -n argocd --type merge -p '{"data":{"server.rootpath":"/gitops"}}' 2>$null
kubectl rollout restart deployment/argocd-server -n argocd 2>$null

Write-Host "After path-a-deploy, apply ArgoCD ingress:" -ForegroundColor Green
Write-Host "  .\10-apply-argocd-ingress.ps1 -IngressHost <same-host-as-console>"
Write-Host ""
Write-Host "Next: apply gitops app — .\08-apply-gitops.ps1" -ForegroundColor Green
