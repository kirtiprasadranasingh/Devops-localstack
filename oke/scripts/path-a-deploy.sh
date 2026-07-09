#!/usr/bin/env bash
# Path A — deploy core workloads onto an EXISTING OKE cluster.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CONSOLE_IMAGE="${CONSOLE_IMAGE:-ap-mumbai-1.ocir.io/bmitpaosivqx/enlight-console:latest}"
INGRESS_HOST="${INGRESS_HOST:-devopslocalstack.enlightlab.com}"
PUBLIC_BASE_URL="${PUBLIC_BASE_URL:-http://${INGRESS_HOST}}"

echo "==> Namespace"
kubectl apply -f "${ROOT}/manifests/00-namespace.yaml"

echo "==> Kestra RBAC"
kubectl apply -f "${ROOT}/manifests/31-kestra-rbac.yaml"

echo "==> Kestra"
kubectl apply -f "${ROOT}/manifests/30-kestra.yaml"

echo "==> Console"
sed -e "s|PLACEHOLDER_OCIR_CONSOLE|${CONSOLE_IMAGE}|g" \
    -e "s|PLACEHOLDER_PUBLIC_BASE_URL|${PUBLIC_BASE_URL}|g" \
    -e "s|PLACEHOLDER_KESTRA_PUBLIC_URL|http://kestra.${INGRESS_HOST}|g" \
    "${ROOT}/manifests/20-console.yaml" | kubectl apply -f -

echo "==> Console ingress (${INGRESS_HOST})"
sed "s|PLACEHOLDER_HOST|${INGRESS_HOST}|g" \
  "${ROOT}/ingress/devopslocalstack-paths.yaml" | kubectl apply -f -

echo "==> Rollout"
kubectl rollout status deployment/enlight-console -n enlight-platform --timeout=300s

echo ""
echo "Core deploy done."
kubectl get pods,svc,ingress -n enlight-platform
