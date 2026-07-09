#!/usr/bin/env bash
# Add Kestra secrets for full build pipeline (OCIR push).
#
# Usage:
#   export KESTRA_URL=http://kestra.144-24-100-85.nip.io
#   export KESTRA_USER=admin@enlightlab.com
#   export KESTRA_PASS=Admin1234
#   export OCIR_USERNAME='bmitpaosivqx/oci-username'
#   export OCIR_TOKEN='your-auth-token'
#   bash oke/scripts/16-kestra-secrets.sh
set -euo pipefail

KESTRA_URL="${KESTRA_URL:-http://kestra.144-24-100-85.nip.io}"
KESTRA_USER="${KESTRA_USER:-admin@enlightlab.com}"
KESTRA_PASS="${KESTRA_PASS:-Admin1234}"
AUTH=(-u "${KESTRA_USER}:${KESTRA_PASS}")

if [[ -z "${OCIR_USERNAME:-}" || -z "${OCIR_TOKEN:-}" ]]; then
  echo "Set OCIR_USERNAME and OCIR_TOKEN before running."
  echo "  OCIR_USERNAME format: bmitpaosivqx/<oci-username>"
  echo "  OCIR_TOKEN: OCI Console -> User Settings -> Auth Tokens"
  exit 1
fi

put_secret() {
  local key="$1" value="$2"
  echo "  -> ${key}"
  curl -sf "${AUTH[@]}" -X PUT \
    "${KESTRA_URL}/api/v1/main/namespaces/main/secrets/${key}" \
    -H "Content-Type: application/json" \
    -d "$(printf '{"value":"%s"}' "$value")" \
    || curl -sf "${AUTH[@]}" -X POST \
    "${KESTRA_URL}/api/v1/main/namespaces/main/secrets" \
    -H "Content-Type: application/json" \
    -d "$(printf '{"id":"%s","value":"%s"}' "$key" "$value")"
}

echo "==> Kestra secrets on ${KESTRA_URL}"
put_secret "OCIR_USERNAME" "${OCIR_USERNAME}"
put_secret "OCIR_TOKEN" "${OCIR_TOKEN}"

if [[ -n "${GITHUB_TOKEN:-}" ]]; then
  put_secret "GITHUB_TOKEN" "${GITHUB_TOKEN}"
fi

echo ""
echo "Done. Import and run flow: oke-deploy-rollout (rollout demo)"
echo "Full Kaniko build requires Kestra Enterprise Kubernetes runner — use manual docker push for now."
