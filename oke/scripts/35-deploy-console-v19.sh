#!/usr/bin/env bash
# Deploy enlight-console v19 on OKE (run from Cloud Shell with kubectl access).
set -euo pipefail

NS="${NS:-enlight-platform}"
IMAGE="${CONSOLE_IMAGE:-ap-mumbai-1.ocir.io/bmitpaosivqx/enlight-console:v19}"

kubectl apply -f oke/manifests/32-console-rbac.yaml 2>/dev/null || true

kubectl set image "deployment/enlight-console" "console=${IMAGE}" -n "${NS}"
kubectl rollout status "deployment/enlight-console" -n "${NS}" --timeout=180s

echo ""
curl -sf "http://144-24-100-85.nip.io/api/health" | head -c 200 || true
echo ""
echo "Console v19 deployed. Open http://144-24-100-85.nip.io and click Run client demo."
