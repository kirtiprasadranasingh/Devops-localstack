#!/usr/bin/env bash
# Deploy enlight-console v20 (demo reset button + Kaniko flow).
set -euo pipefail

NS="${NS:-enlight-platform}"
IMAGE="${CONSOLE_IMAGE:-ap-mumbai-1.ocir.io/bmitpaosivqx/enlight-console:v20}"

kubectl apply -f oke/manifests/32-console-rbac.yaml

kubectl set image "deployment/enlight-console" "console=${IMAGE}" -n "${NS}"
kubectl rollout status "deployment/enlight-console" -n "${NS}" --timeout=180s

echo ""
curl -sf "http://144-24-100-85.nip.io/api/health" || true
echo ""
echo "Console v20 deployed — Reset demo app button is on the home page."
