#Requires -Version 5.1
<#
.SYNOPSIS
  Install Grafana (kube-prometheus-stack) for Enlight Lab monitoring at /metrics.
.PARAMETER IngressHost
  Same host as console (e.g. 144-24-100-85.nip.io).
#>
param(
    [Parameter(Mandatory = $true)]
    [string]$IngressHost
)

$ErrorActionPreference = "Stop"
$OkeRoot = Resolve-Path (Join-Path $PSScriptRoot "..")

Write-Host ""
Write-Host "==> monitoring namespace" -ForegroundColor Cyan
kubectl create namespace monitoring --dry-run=client -o yaml | kubectl apply -f -

Write-Host ""
Write-Host "==> Add prometheus-community helm repo" -ForegroundColor Cyan
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts 2>$null
helm repo update

Write-Host ""
Write-Host "==> Install kube-prometheus-stack" -ForegroundColor Cyan
helm upgrade --install kube-prometheus-stack prometheus-community/kube-prometheus-stack `
  -n monitoring `
  --set grafana.adminPassword=admin `
  --set prometheus.prometheusSpec.serviceMonitorSelectorNilUsesHelmValues=false `
  --wait --timeout 10m

Write-Host ""
Write-Host "==> Grafana ingress at /metrics" -ForegroundColor Cyan
$ingress = @"
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: grafana-paths
  namespace: monitoring
  annotations:
    nginx.ingress.kubernetes.io/ssl-redirect: "false"
    nginx.ingress.kubernetes.io/use-regex: "true"
    nginx.ingress.kubernetes.io/rewrite-target: /`$2
spec:
  ingressClassName: nginx
  rules:
    - host: $IngressHost
      http:
        paths:
          - path: /metrics(/|`$)(.*)
            pathType: ImplementationSpecific
            backend:
              service:
                name: kube-prometheus-stack-grafana
                port:
                  number: 80
"@
$staging = Join-Path $env:TEMP "grafana-paths.yaml"
Set-Content -Path $staging -Value $ingress -NoNewline
kubectl apply -f $staging

Write-Host ""
Write-Host "Grafana UI: http://${IngressHost}/metrics" -ForegroundColor Green
Write-Host "  user: admin  pass: admin  (change after first login)" -ForegroundColor DarkGray
