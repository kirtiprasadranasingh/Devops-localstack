#Requires -Version 5.1
<#
.SYNOPSIS
  Install nginx ingress controller on OKE (one LoadBalancer IP).
#>

$ErrorActionPreference = "Stop"

Write-Host ""
Write-Host "==> Adding ingress-nginx helm repo" -ForegroundColor Cyan
helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx
helm repo update

Write-Host ""
Write-Host "==> Installing ingress-nginx" -ForegroundColor Cyan
helm upgrade --install ingress-nginx ingress-nginx/ingress-nginx `
    --namespace ingress-nginx `
    --create-namespace `
    --set controller.service.type=LoadBalancer `
    --set controller.service.annotations."service\.beta\.kubernetes\.io/oci-load-balancer-shape"="flexible" `
    --set controller.service.annotations."service\.beta\.kubernetes\.io/oci-load-balancer-shape-flex-min"="10" `
    --set controller.service.annotations."service\.beta\.kubernetes\.io/oci-load-balancer-shape-flex-max"="10" `
    --wait --timeout 10m

Write-Host ""
Write-Host "==> Waiting for external IP (up to 5 min)" -ForegroundColor Cyan
$ip = $null
for ($i = 0; $i -lt 30; $i++) {
    $ip = kubectl get svc -n ingress-nginx ingress-nginx-controller -o jsonpath="{.status.loadBalancer.ingress[0].ip}" 2>$null
    if ($ip) { break }
    Start-Sleep -Seconds 10
    Write-Host "  ... waiting" -ForegroundColor DarkGray
}

if ($ip) {
    Write-Host ""
    Write-Host "LoadBalancer IP: $ip" -ForegroundColor Green
    Write-Host ""
    Write-Host "Point DNS A records to this ONE IP:" -ForegroundColor Yellow
    Write-Host "  devopslocalstack.enlightlab.com"
    Write-Host "  app.devopslocalstack.enlightlab.com"
    Write-Host ""
    Write-Host "Or test locally (hosts file):" -ForegroundColor DarkGray
    Write-Host "  $ip  devopslocalstack.enlightlab.com"
    Write-Host "  $ip  app.devopslocalstack.enlightlab.com"
}
else {
    Write-Host "WARN: No external IP yet. Run:" -ForegroundColor Yellow
    Write-Host "  kubectl get svc -n ingress-nginx ingress-nginx-controller -w"
}

Write-Host ""
Write-Host "Next: .\05-push-images.ps1 then .\06-deploy-manifests.ps1" -ForegroundColor Green
