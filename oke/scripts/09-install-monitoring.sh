#!/usr/bin/env bash
# Install Grafana + Prometheus at /metrics (Cloud Shell).
# Usage: bash oke/scripts/09-install-monitoring.sh 144-24-100-85.nip.io
set -euo pipefail

INGRESS_HOST="${1:-144-24-100-85.nip.io}"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
OKE_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

echo "==> monitoring namespace"
kubectl create namespace monitoring --dry-run=client -o yaml | kubectl apply -f -

echo "==> helm repo"
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts 2>/dev/null || true
helm repo update

echo "==> kube-prometheus-stack (this may take several minutes)"
helm upgrade --install kube-prometheus-stack prometheus-community/kube-prometheus-stack \
  -n monitoring \
  --set grafana.adminPassword=admin \
  --set prometheus.prometheusSpec.serviceMonitorSelectorNilUsesHelmValues=false \
  --wait --timeout 15m

echo "==> Grafana ingress metrics.${INGRESS_HOST}"
sed "s|PLACEHOLDER_HOST|${INGRESS_HOST}|g" "${OKE_ROOT}/ingress/metrics-host.yaml" | kubectl apply -f -

echo ""
echo "Grafana: http://metrics.${INGRESS_HOST}"
echo "  user: admin  pass: admin"
