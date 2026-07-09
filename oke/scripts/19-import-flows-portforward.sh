#!/usr/bin/env bash
# Import flows through kubectl port-forward — tries multiple Kestra API versions.
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
  local flow_id namespace
  flow_id="$(grep '^id:' "$file" | awk '{print $2}')"
  namespace="$(grep '^namespace:' "$file" | awk '{print $2}')"
  namespace="${namespace:-main}"
  echo "  -> $(basename "$file") (${namespace}/${flow_id})"

  local url method code body
  for attempt in \
    "POST|${KESTRA_PF}/api/v1/main/flows" \
    "PUT|${KESTRA_PF}/api/v1/main/flows/${namespace}/${flow_id}" \
    "POST|${KESTRA_PF}/api/v1/flows" \
    "PUT|${KESTRA_PF}/api/v1/flows/${namespace}/${flow_id}"; do
    method="${attempt%%|*}"
    url="${attempt#*|}"
    body=$(curl -s -u "${KESTRA_USER}:${KESTRA_PASS}" -X "${method}" \
      "${url}" \
      -H "Content-Type: application/x-yaml" \
      --data-binary @"${file}" \
      -w "\nHTTP_CODE:%{http_code}")
    code="${body##*HTTP_CODE:}"
    body="${body%HTTP_CODE:*}"
    if [[ "${code}" == "200" || "${code}" == "201" ]]; then
      echo "     OK ${method} ${url} (${code})"
      return 0
    fi
  done

  echo "     FAIL last HTTP ${code}"
  echo "${body}" | tail -3
  return 1
}

trigger_test() {
  local flow_id="$1"
  local namespace="${2:-main}"
  for url in \
    "${KESTRA_PF}/api/v1/main/executions/${namespace}/${flow_id}" \
    "${KESTRA_PF}/api/v1/executions/${namespace}/${flow_id}"; do
    body=$(curl -s -u "${KESTRA_USER}:${KESTRA_PASS}" -X POST "${url}" -w "\nHTTP_CODE:%{http_code}")
    code="${body##*HTTP_CODE:}"
    if [[ "${code}" == "200" || "${code}" == "201" ]]; then
      echo "Trigger OK via ${url}"
      echo "${body%HTTP_CODE:*}" | head -c 200
      echo ""
      return 0
    fi
  done
  echo "Trigger FAILED for ${flow_id}"
  return 1
}

echo "==> Port-forward svc/kestra ${PF_PORT}:8080"
kubectl port-forward -n "${NS}" "svc/kestra" "${PF_PORT}:8080" >/tmp/kestra-pf.log 2>&1 &
PF_PID=$!
trap 'kill ${PF_PID} 2>/dev/null || true' EXIT

for i in $(seq 1 30); do
  if curl -sf -u "${KESTRA_USER}:${KESTRA_PASS}" "${KESTRA_PF}/api/v1/configs" >/dev/null 2>&1; then
    break
  fi
  sleep 2
done

echo "==> API probe"
for path in /api/v1/configs /api/v1/main/flows /api/v1/flows; do
  code=$(curl -s -o /dev/null -w "%{http_code}" -u "${KESTRA_USER}:${KESTRA_PASS}" "${KESTRA_PF}${path}")
  echo "  ${path} -> ${code}"
done

for flow in oke-health-check.yaml oke-deploy-simple.yaml oke-dagger-gitops-pipeline.yaml; do
  path="${ROOT}/kestra/flows/${flow}"
  [[ -f "$path" ]] && import_one "$path" || echo "SKIP ${flow}"
done

echo ""
echo "Test trigger oke-deploy-simple:"
trigger_test oke-deploy-simple main || true
