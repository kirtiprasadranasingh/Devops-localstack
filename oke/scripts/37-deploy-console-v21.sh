#!/usr/bin/env bash
# Deploy enlight-console v21 (fixed pipeline UI + post-reset flow).
set -euo pipefail

NS="${NS:-enlight-platform}"
IMAGE="${CONSOLE_IMAGE:-ap-mumbai-1.ocir.io/bmitpaosivqx/enlight-console:v21}"
KESTRA_URL="${KESTRA_URL:-http://kestra.144-24-100-85.nip.io}"
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"

kubectl apply -f "${ROOT}/oke/manifests/32-console-rbac.yaml" 2>/dev/null || true

kubectl set image "deployment/enlight-console" "console=${IMAGE}" -n "${NS}"
kubectl rollout status "deployment/enlight-console" -n "${NS}" --timeout=180s

echo "==> Import Kestra flow (no health-before, health-after retries)"
curl -sf -u "${KESTRA_USER:-admin@enlightlab.com}:${KESTRA_PASS:-Admin1234}" \
  -X PUT "${KESTRA_URL}/api/v1/main/flows/main/oke-dagger-gitops-pipeline" \
  -H "Content-Type: application/x-yaml" \
  --data-binary "@${ROOT}/kestra/flows/oke-dagger-gitops-pipeline.yaml" \
  | grep -o 'flow-version[^,]*' || true

echo ""
curl -sf "http://144-24-100-85.nip.io/api/health" || true
echo ""
echo "Console v21 deployed."
