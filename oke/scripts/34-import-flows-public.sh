#!/usr/bin/env bash
# Import Kestra flows via public ingress (no kubectl port-forward required).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"

export KESTRA_USER="${KESTRA_USER:-admin@enlightlab.com}"
export KESTRA_PASS="${KESTRA_PASS:-Admin1234}"
KESTRA_URL="${KESTRA_URL:-http://kestra.144-24-100-85.nip.io}"

import_one() {
  local file="$1"
  local flow_id namespace
  flow_id="$(grep '^id:' "$file" | awk '{print $2}')"
  namespace="$(grep '^namespace:' "$file" | awk '{print $2}')"
  namespace="${namespace:-main}"
  echo "  -> $(basename "$file") (${namespace}/${flow_id})"

  local url method code body
  for attempt in \
    "PUT|${KESTRA_URL}/api/v1/main/flows/${namespace}/${flow_id}" \
    "POST|${KESTRA_URL}/api/v1/main/flows" \
    "PUT|${KESTRA_URL}/api/v1/flows/${namespace}/${flow_id}"; do
    method="${attempt%%|*}"
    url="${attempt#*|}"
    body=$(curl -sf -u "${KESTRA_USER}:${KESTRA_PASS}" -X "${method}" \
      "${url}" \
      -H "Content-Type: application/x-yaml" \
      --data-binary @"${file}" \
      -w "\nHTTP_CODE:%{http_code}" 2>&1) || true
    code="${body##*HTTP_CODE:}"
    body="${body%HTTP_CODE:*}"
    if [[ "${code}" == "200" || "${code}" == "201" ]]; then
      echo "     OK ${method} (${code})"
      return 0
    fi
  done
  echo "     FAIL last HTTP ${code:-?}"
  echo "${body}" | tail -5
  return 1
}

echo "==> Import flows to ${KESTRA_URL}"
import_one "${ROOT}/kestra/flows/oke-dagger-gitops-pipeline.yaml"

echo ""
echo "==> Verify wait duration"
FLOW_JSON=$(curl -sf -u "${KESTRA_USER}:${KESTRA_PASS}" \
  "${KESTRA_URL}/api/v1/main/flows/main/oke-dagger-gitops-pipeline")
echo "${FLOW_JSON}" | grep -oE '"duration":"PT[^"]*"' | head -3
echo "${FLOW_JSON}" | grep -oE 'enlight-pipeline:v[0-9]+' | head -1
