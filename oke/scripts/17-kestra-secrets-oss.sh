#!/usr/bin/env bash
# Kestra OSS secrets — set via env vars on the Kestra deployment (not UI).
#
# OSS requires:
#   1. Base64-encode each secret value
#   2. Set SECRET_<KEY> on the Kestra pod
#   3. Restart Kestra
#
# Usage (Cloud Shell or laptop with kubectl):
#   export GITHUB_TOKEN='ghp_...'
#   export OCIR_USERNAME='bmitpaosivqx/oci-username'
#   export OCIR_TOKEN='your-auth-token'
#   bash oke/scripts/17-kestra-secrets-oss.sh
set -euo pipefail

NS="${KESTRA_NAMESPACE:-enlight-platform}"
DEPLOY="${KESTRA_DEPLOYMENT:-kestra}"

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
echo "    Flow references: secret('GITHUB_TOKEN'), secret('OCIR_USERNAME'), secret('OCIR_TOKEN')"

kubectl set env deployment/"${DEPLOY}" -n "${NS}" \
  "SECRET_GITHUB_TOKEN=$(b64 "$GITHUB_TOKEN")" \
  "SECRET_OCIR_USERNAME=$(b64 "$OCIR_USERNAME")" \
  "SECRET_OCIR_TOKEN=$(b64 "$OCIR_TOKEN")"

echo ""
echo "==> Restarting Kestra (required for OSS secrets to load)"
kubectl rollout restart deployment/"${DEPLOY}" -n "${NS}"
kubectl rollout status deployment/"${DEPLOY}" -n "${NS}" --timeout=300s

echo ""
echo "Done. Secrets are loaded from env vars — UI Secrets tab stays locked on OSS."
echo "Test: run flow oke-dagger-gitops-pipeline from Kestra UI."
