#!/usr/bin/env bash
# Build, push, and deploy enlight-console:v21 from Oracle Cloud Shell.
# Prereq: git pull (v21 console code must be in this repo).
set -euo pipefail

NS="${NS:-enlight-platform}"
IMAGE="ap-mumbai-1.ocir.io/bmitpaosivqx/enlight-console:v21"
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"

echo "=========================================="
echo " Build + push + deploy console v21"
echo "=========================================="

if [[ ! -f "${ROOT}/console/Dockerfile" ]]; then
  echo "ERROR: ${ROOT}/console/Dockerfile not found."
  echo "Run: cd ~/Devops-localstack && git pull"
  exit 1
fi

if ! grep -q 'v21' "${ROOT}/console/frontend/src/branding.js" 2>/dev/null; then
  echo "WARN: branding.js may not be v21 — git pull latest from laptop push first."
fi

echo ""
echo "==> 1) Docker login (OCIR)"
if ! docker info >/dev/null 2>&1; then
  echo "ERROR: docker not available in this shell"
  exit 1
fi
echo "Login if needed: docker login ap-mumbai-1.ocir.io"
echo "  Username: <tenancy-namespace>/oracleidentitycloudservice/<your-email>"
echo "  Password: Auth Token from OCI Console"
docker login ap-mumbai-1.ocir.io || true

echo ""
echo "==> 2) Build ${IMAGE}"
cd "${ROOT}/console"
docker build -t "${IMAGE}" .

echo ""
echo "==> 3) Push ${IMAGE}"
docker push "${IMAGE}"

echo ""
echo "==> 4) RBAC + deploy"
kubectl apply -f "${ROOT}/oke/manifests/32-console-rbac.yaml" 2>/dev/null || true
kubectl patch serviceaccount enlight-console -n "${NS}" --type=merge \
  -p '{"imagePullSecrets":[{"name":"ocir-pull-secret"}]}' 2>/dev/null || true

kubectl set image deployment/enlight-console "console=${IMAGE}" -n "${NS}"
kubectl delete pods -n "${NS}" -l app=enlight-console --force --grace-period=0 2>/dev/null || true
kubectl rollout status deployment/enlight-console -n "${NS}" --timeout=300s

echo ""
echo "==> 5) Import Kestra flow v5 (post-reset fix)"
FLOW="${ROOT}/kestra/flows/oke-dagger-gitops-pipeline.yaml"
if [[ -f "${FLOW}" ]]; then
  curl -sf -u "${KESTRA_USER:-admin@enlightlab.com}:${KESTRA_PASS:-Admin1234}" \
    -X PUT "http://kestra.144-24-100-85.nip.io/api/v1/main/flows/main/oke-dagger-gitops-pipeline" \
    -H "Content-Type: application/x-yaml" \
    --data-binary "@${FLOW}" >/dev/null && echo "Kestra flow OK" || echo "Kestra import skipped"
fi

echo ""
curl -sf "http://144-24-100-85.nip.io/api/health" || sleep 5 && curl -sf "http://144-24-100-85.nip.io/api/health"
echo ""
echo "Done — open http://144-24-100-85.nip.io"
