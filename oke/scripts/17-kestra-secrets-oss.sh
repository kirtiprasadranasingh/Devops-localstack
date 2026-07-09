#!/usr/bin/env bash
# Kestra OSS secrets — set via env vars on the Kestra deployment (not UI).
set -euo pipefail

NS="${KESTRA_NAMESPACE:-enlight-platform}"
DEPLOY="${KESTRA_DEPLOYMENT:-kestra}"
REIMPORT=1
[[ "${1:-}" == "--no-reimport" ]] && REIMPORT=0

b64() { printf '%s' "$1" | base64 -w0 2>/dev/null || printf '%s' "$1" | base64; }

if [[ -z "${GITHUB_TOKEN:-}" ]]; then
  echo "ERROR: Set GITHUB_TOKEN (write access to Devops-localstack repo)"
  exit 1
fi
if [[ -z "${OCIR_USERNAME:-}" || -z "${OCIR_TOKEN:-}" ]]; then
  echo "ERROR: Set OCIR_USERNAME and OCIR_TOKEN"
  exit 1
fi

echo "==> Adding OSS secrets to ${DEPLOY} in ${NS}"

kubectl set env deployment/"${DEPLOY}" -n "${NS}" \
  "SECRET_GITHUB_TOKEN=$(b64 "$GITHUB_TOKEN")" \
  "SECRET_OCIR_USERNAME=$(b64 "$OCIR_USERNAME")" \
  "SECRET_OCIR_TOKEN=$(b64 "$OCIR_TOKEN")"

echo ""
echo "==> Restarting Kestra (required for OSS secrets)"
kubectl rollout restart deployment/"${DEPLOY}" -n "${NS}"
kubectl rollout status deployment/"${DEPLOY}" -n "${NS}" --timeout=300s

if [[ "${REIMPORT}" -eq 1 ]]; then
  echo ""
  echo "==> Re-importing flows (restart wipes in-memory DB without PVC)"
  SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
  bash "${SCRIPT_DIR}/19-import-flows-portforward.sh"
fi

echo ""
echo "Done."
