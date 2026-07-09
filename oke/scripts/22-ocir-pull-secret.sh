#!/usr/bin/env bash
# Create OCIR image pull secret in enlight-platform (required for private pipeline image).
#
# Usage:
#   export OCIR_USERNAME='bmitpaosivqx/kirti@enlightlab.com'
#   export OCIR_TOKEN='your-auth-token'
#   bash oke/scripts/22-ocir-pull-secret.sh
set -euo pipefail

NS="${NAMESPACE:-enlight-platform}"
SECRET_NAME="${SECRET_NAME:-ocir-pull-secret}"

if [[ -z "${OCIR_USERNAME:-}" || -z "${OCIR_TOKEN:-}" ]]; then
  echo "ERROR: Set OCIR_USERNAME and OCIR_TOKEN"
  exit 1
fi

kubectl create secret docker-registry "${SECRET_NAME}" \
  --docker-server=ap-mumbai-1.ocir.io \
  --docker-username="${OCIR_USERNAME}" \
  --docker-password="${OCIR_TOKEN}" \
  -n "${NS}" \
  --dry-run=client -o yaml | kubectl apply -f -

kubectl patch serviceaccount kestra-runner -n "${NS}" --type=merge \
  -p "{\"imagePullSecrets\":[{\"name\":\"${SECRET_NAME}\"}]}" 2>/dev/null || true

kubectl patch serviceaccount default -n "${NS}" --type=merge \
  -p "{\"imagePullSecrets\":[{\"name\":\"${SECRET_NAME}\"}]}" 2>/dev/null || true

echo "OK: ${SECRET_NAME} in ${NS} — kestra-runner SA patched"
