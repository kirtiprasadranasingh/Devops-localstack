#!/usr/bin/env bash
# Deploy THIS project's FastAPI app (enlight-platform) — separate from selfheal.
#
# Usage:
#   export INGRESS_HOST=144-24-100-85.nip.io
#   export FASTAPI_IMAGE=ap-mumbai-1.ocir.io/bmitpaosivqx/enlight-fastapi:latest
#   bash oke/scripts/24-deploy-enlight-demo-app.sh
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
OKE_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
INGRESS_HOST="${INGRESS_HOST:-144-24-100-85.nip.io}"
FASTAPI_IMAGE="${FASTAPI_IMAGE:-ap-mumbai-1.ocir.io/bmitpaosivqx/enlight-fastapi:latest}"

echo "=============================================="
echo " Enlight Lab demo app (separate from selfheal)"
echo " Image: ${FASTAPI_IMAGE}"
echo " URL:   http://app.${INGRESS_HOST}"
echo "=============================================="

echo "==> 1/4 Namespace"
kubectl apply -f "${OKE_ROOT}/manifests/00-namespace.yaml"

echo "==> 2/4 FastAPI deployment + service (enlight-platform)"
sed "s|PLACEHOLDER_OCIR_FASTAPI|${FASTAPI_IMAGE}|g" \
  "${OKE_ROOT}/manifests/10-fastapi.yaml" | kubectl apply -f -
kubectl rollout status deployment/fastapi-minimal -n enlight-platform --timeout=300s

echo "==> 3/4 Ingress app.${INGRESS_HOST} -> fastapi-minimal:8000"
sed "s|PLACEHOLDER_HOST|${INGRESS_HOST}|g" \
  "${OKE_ROOT}/ingress/app-enlight-platform.yaml" | kubectl apply -f -

echo "==> 4/4 Point console + Kestra at OUR app (not enlight-staging)"
kubectl set env deployment/enlight-console -n enlight-platform \
  APP_HEALTH_URL=http://fastapi-minimal.enlight-platform.svc.cluster.local:8000/health \
  GITOPS_PUBLIC_URL=https://argocd.enlightlab.com 2>/dev/null || true

echo ""
echo "==> Verify"
kubectl get pods,svc,ingress -n enlight-platform -l app=fastapi-minimal 2>/dev/null || \
  kubectl get pods,svc,ingress -n enlight-platform | grep -E 'fastapi|app-enlight'
code=$(curl -s -o /dev/null -w "%{http_code}" "http://app.${INGRESS_HOST}/health" 2>/dev/null || echo "ERR")
echo "http://app.${INGRESS_HOST}/health -> HTTP ${code}"

echo ""
echo "=============================================="
echo " Demo app: http://app.${INGRESS_HOST}"
echo " Health:   http://app.${INGRESS_HOST}/health"
echo ""
echo " Kestra flow inputs (update in UI if needed):"
echo "   k8s_namespace: enlight-platform"
echo "   k8s_deployment: fastapi-minimal"
echo "   app_health_url: http://fastapi-minimal.enlight-platform.svc.cluster.local:8000/health"
echo "=============================================="
