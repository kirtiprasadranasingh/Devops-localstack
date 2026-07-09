#!/usr/bin/env bash
# Import flows through kubectl port-forward — avoids nginx 504 on large YAML.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
NS="${KESTRA_NAMESPACE:-enlight-platform}"

export KESTRA_USER="${KESTRA_USER:-admin@enlightlab.com}"
export KESTRA_PASS="${KESTRA_PASS:-Admin1234}"

PF_PORT="${PF_PORT:-18080}"
KESTRA_PF="http://127.0.0.1:${PF_PORT}"

import_one() {
  local file="$1"
  local flow_id
  flow_id="$(grep '^id:' "$file" | awk '{print $2}')"
  echo "  -> $(basename "$file") (${flow_id})"
  if curl -sf -u "${KESTRA_USER}:${KESTRA_PASS}" -X POST \
    "${KESTRA_PF}/api/v1/main/flows" \
    -H "Content-Type: application/x-yaml" \
    --data-binary @"${file}"; then
    echo "     OK POST"
    return 0
  fi
  if curl -sf -u "${KESTRA_USER}:${KESTRA_PASS}" -X PUT \
    "${KESTRA_PF}/api/v1/main/flows/main/${flow_id}" \
    -H "Content-Type: application/x-yaml" \
    --data-binary @"${file}"; then
    echo "     OK PUT"
    return 0
  fi
  echo "     FAIL — response:"
  curl -s -u "${KESTRA_USER}:${KESTRA_PASS}" -X POST \
    "${KESTRA_PF}/api/v1/main/flows" \
    -H "Content-Type: application/x-yaml" \
    --data-binary @"${file}" \
    -w "\nHTTP %{http_code}\n" | tail -5
  return 1
}

echo "==> Port-forward svc/kestra ${PF_PORT}:8080"
kubectl port-forward -n "${NS}" "svc/kestra" "${PF_PORT}:8080" >/tmp/kestra-pf.log 2>&1 &
PF_PID=$!
trap 'kill ${PF_PID} 2>/dev/null || true' EXIT

for i in $(seq 1 20); do
  if curl -sf -u "${KESTRA_USER}:${KESTRA_PASS}" "${KESTRA_PF}/api/v1/configs" >/dev/null 2>&1; then
    break
  fi
  sleep 2
done

export KESTRA_URL="${KESTRA_PF}"
export KESTRA_PUBLIC_URL=""

for flow in oke-health-check.yaml oke-deploy-simple.yaml oke-dagger-gitops-pipeline.yaml; do
  path="${ROOT}/kestra/flows/${flow}"
  [[ -f "$path" ]] && import_one "$path" || echo "SKIP ${flow}"
done

echo ""
echo "Test trigger oke-deploy-simple:"
curl -sf -u "${KESTRA_USER}:${KESTRA_PASS}" -X POST \
  "${KESTRA_PF}/api/v1/main/executions/main/oke-deploy-simple" | head -c 200 && echo ""
