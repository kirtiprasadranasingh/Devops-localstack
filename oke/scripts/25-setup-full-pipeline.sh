#!/usr/bin/env bash
# Wire the full OKE delivery pipeline: Kestra → Dagger → OCIR → ArgoCD → OKE
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
OKE_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
ROOT="$(cd "${OKE_ROOT}/.." && pwd)"

INGRESS_HOST="${INGRESS_HOST:-144-24-100-85.nip.io}"
KESTRA_URL="${KESTRA_URL:-http://kestra.${INGRESS_HOST}}"
CONSOLE_IMAGE="${CONSOLE_IMAGE:-ap-mumbai-1.ocir.io/bmitpaosivqx/enlight-console:v13}"

echo "=============================================="
echo " Enlight Lab — Full OKE pipeline setup"
echo " Flow: oke-dagger-gitops-pipeline"
echo "=============================================="

echo ""
echo "==> 1/5 — Kestra RBAC"
kubectl apply -f "${OKE_ROOT}/manifests/31-kestra-rbac.yaml"

echo ""
echo "==> 2/5 — Import Kestra flows"
export KESTRA_PUBLIC_URL="${KESTRA_URL}"
bash "${SCRIPT_DIR}/13-import-kestra-flows.sh"

echo ""
echo "==> 3/5 — ArgoCD Application (fastapi-minimal)"
kubectl apply -f "${OKE_ROOT}/gitops/argocd/fastapi-minimal.yaml" 2>/dev/null || \
  echo "WARN: ArgoCD not installed or app already exists"

echo ""
echo "==> 4/5 — Console (oke-dagger-gitops-pipeline)"
if [[ -f "${OKE_ROOT}/manifests/20-console.yaml" ]]; then
  sed "s|PLACEHOLDER_OCIR_CONSOLE|${CONSOLE_IMAGE}|g; \
       s|PLACEHOLDER_PUBLIC_BASE_URL|http://${INGRESS_HOST}|g; \
       s|PLACEHOLDER_KESTRA_PUBLIC_URL|http://kestra.${INGRESS_HOST}|g" \
    "${OKE_ROOT}/manifests/20-console.yaml" | kubectl apply -f -
  kubectl set image deployment/enlight-console \
    console="${CONSOLE_IMAGE}" -n enlight-platform
  kubectl rollout status deployment/enlight-console -n enlight-platform --timeout=300s
fi

echo ""
echo "==> 5/5 — Verify"
echo "Console:  http://${INGRESS_HOST}"
echo "Kestra:   ${KESTRA_URL}/ui/flows/main/oke-dagger-gitops-pipeline"
echo "ArgoCD:   https://argocd.enlightlab.com"
echo "Demo app: http://app.${INGRESS_HOST}"
echo ""
echo "Before Run client demo, set Kestra OSS secrets (UI is locked on free/OSS):"
echo "  export GITHUB_TOKEN OCIR_USERNAME OCIR_TOKEN"
echo "  bash oke/scripts/17-kestra-secrets-oss.sh"
