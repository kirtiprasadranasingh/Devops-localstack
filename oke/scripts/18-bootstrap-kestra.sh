#!/usr/bin/env bash
# One-shot Kestra recovery: PVC + ingress timeouts + secrets + flow import (via port-forward).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
NS="${KESTRA_NAMESPACE:-enlight-platform}"

export KESTRA_USER="${KESTRA_USER:-admin@enlightlab.com}"
export KESTRA_PASS="${KESTRA_PASS:-Admin1234}"

echo "=============================================="
echo " Kestra bootstrap — fix 504 + lost flows"
echo "=============================================="

echo ""
echo "==> 1/6 PVC + Kestra deployment (persistent flows)"
kubectl apply -f "${ROOT}/oke/manifests/32-kestra-pvc.yaml"
kubectl apply -f "${ROOT}/oke/manifests/30-kestra.yaml"

echo ""
echo "==> 2/6 Ingress timeouts (fix 504 on large flow import)"
INGRESS_HOST="${INGRESS_HOST:-144-24-100-85.nip.io}"
sed "s|PLACEHOLDER_HOST|${INGRESS_HOST}|g" "${ROOT}/oke/ingress/kestra-host.yaml" | kubectl apply -f -

echo ""
echo "==> 3/6 Secrets (skip if not set)"
if [[ -n "${GITHUB_TOKEN:-}" && -n "${OCIR_USERNAME:-}" && -n "${OCIR_TOKEN:-}" ]]; then
  bash "${SCRIPT_DIR}/17-kestra-secrets-oss.sh" --no-reimport
else
  echo "WARN: GITHUB_TOKEN / OCIR_* not set — skipping secrets step"
  kubectl rollout status deployment/kestra -n "${NS}" --timeout=300s
fi

echo ""
echo "==> 4/6 Wait for Kestra API"
for i in $(seq 1 30); do
  if curl -sf -u "${KESTRA_USER}:${KESTRA_PASS}" \
    "http://kestra.${INGRESS_HOST}/api/v1/configs" >/dev/null 2>&1; then
    echo "Kestra API ready"
    break
  fi
  echo "  waiting... (${i}/30)"
  sleep 5
done

echo ""
echo "==> 5/6 Import flows via port-forward (bypasses ingress 504)"
bash "${SCRIPT_DIR}/19-import-flows-portforward.sh"

echo ""
echo "==> 6/6 Verify"
curl -sf -u "${KESTRA_USER}:${KESTRA_PASS}" \
  "${KESTRA_URL:-http://kestra.${INGRESS_HOST}}/api/v1/main/flows/main/oke-dagger-gitops-pipeline" \
  | head -c 120 && echo ""

echo ""
echo "Done. Build pipeline image if not done:"
echo "  bash oke/scripts/build-pipeline-image.sh"
echo "Then run:"
echo "  curl -u ${KESTRA_USER}:*** -X POST http://kestra.${INGRESS_HOST}/api/v1/main/executions/main/oke-dagger-gitops-pipeline"
