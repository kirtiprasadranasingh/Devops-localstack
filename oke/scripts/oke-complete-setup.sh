#!/usr/bin/env bash

# Complete Enlight Lab OKE setup — existing cluster (Path A).

#

# Usage:

#   export CONSOLE_IMAGE=ap-mumbai-1.ocir.io/bmitpaosivqx/enlight-console:v7

#   export INGRESS_HOST=144-24-100-85.nip.io

#   export PUBLIC_BASE_URL=http://144-24-100-85.nip.io

#   bash oke/scripts/oke-complete-setup.sh

#

# Optional:

#   INSTALL_ARGOCD=1 INSTALL_MONITORING=1 bash oke/scripts/oke-complete-setup.sh



set -euo pipefail



SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

OKE_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"



export CONSOLE_IMAGE="${CONSOLE_IMAGE:-ap-mumbai-1.ocir.io/bmitpaosivqx/enlight-console:v7}"

export INGRESS_HOST="${INGRESS_HOST:-144-24-100-85.nip.io}"

export PUBLIC_BASE_URL="${PUBLIC_BASE_URL:-http://${INGRESS_HOST}}"

export KESTRA_URL="${KESTRA_URL:-http://kestra.enlight-platform.svc.cluster.local:8080}"



echo "=============================================="

echo " Enlight Lab — OKE complete setup"

echo " Console:  ${PUBLIC_BASE_URL}"

echo " Kestra:   http://kestra.${INGRESS_HOST}"

echo " Demo app: http://app.${INGRESS_HOST}"

echo " GitOps:   ${PUBLIC_BASE_URL}/gitops"

echo " Metrics:  ${PUBLIC_BASE_URL}/metrics"

echo "=============================================="



echo ""

echo "==> Step 1/6 — Core workloads"

bash "${SCRIPT_DIR}/path-a-deploy.sh"



echo ""

echo "==> Step 2/6 — Kestra RBAC"

kubectl apply -f "${OKE_ROOT}/manifests/31-kestra-rbac.yaml"



echo ""

echo "==> Step 3/6 — Hostname ingress (kestra + app)"

sed "s|PLACEHOLDER_HOST|${INGRESS_HOST}|g" "${OKE_ROOT}/ingress/kestra-host.yaml" | kubectl apply -f -

sed "s|PLACEHOLDER_HOST|${INGRESS_HOST}|g" "${OKE_ROOT}/ingress/app-host.yaml" | kubectl apply -f -



echo ""

echo "==> Step 4/6 — Wait for Kestra"

kubectl rollout status deployment/kestra -n enlight-platform --timeout=600s || true



echo ""

echo "==> Step 5/6 — Import Kestra flows"

bash "${SCRIPT_DIR}/13-import-kestra-flows.sh" || {

  echo "WARN: in-cluster import failed — use Kestra UI or:"

  echo "  curl -X POST http://kestra.${INGRESS_HOST}/api/v1/main/flows -H 'Content-Type: application/x-yaml' --data-binary @kestra/flows/oke-deploy-simple.yaml"

}



if [[ "${INSTALL_ARGOCD:-0}" == "1" ]]; then

  echo ""

  echo "==> Optional — ArgoCD"

  powershell.exe -File "${SCRIPT_DIR}/07-install-argocd.ps1" 2>/dev/null || bash -c "kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml"

  sed "s|PLACEHOLDER_HOST|${INGRESS_HOST}|g" "${OKE_ROOT}/ingress/argocd-paths.yaml" | kubectl apply -f -

fi



if [[ "${INSTALL_MONITORING:-0}" == "1" ]]; then

  echo ""

  echo "==> Optional — Grafana monitoring"

  powershell.exe -File "${SCRIPT_DIR}/09-install-monitoring.ps1" -IngressHost "${INGRESS_HOST}" 2>/dev/null || \

    sed "s|PLACEHOLDER_HOST|${INGRESS_HOST}|g" "${OKE_ROOT}/ingress/grafana-paths.yaml" | kubectl apply -f -

fi



echo ""

echo "==> Step 6/6 — Verify console"

kubectl rollout status deployment/enlight-console -n enlight-platform --timeout=300s



echo ""

echo "=============================================="

echo " DONE"

echo "  1. Open ${PUBLIC_BASE_URL}"

echo "  2. Ensure flows imported: oke-health-check, oke-deploy-simple"

echo "  3. Click 'Run client demo'"

echo "  4. Watch at http://kestra.${INGRESS_HOST}"

echo ""

echo " Rebuild console from Windows:"

echo "   .\\oke\\scripts\\redeploy-console.ps1 -Tag v7 -IngressHost ${INGRESS_HOST}"

echo "=============================================="

