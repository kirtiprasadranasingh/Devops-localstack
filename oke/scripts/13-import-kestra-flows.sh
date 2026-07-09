#!/usr/bin/env bash
# Import Enlight Lab flows into Kestra (Kestra 1.3 API).
set -euo pipefail

KESTRA_URL="${KESTRA_URL:-http://kestra.enlight-platform.svc.cluster.local:8080}"
KESTRA_PUBLIC_URL="${KESTRA_PUBLIC_URL:-}"

import_flow() {
  local file="$1"
  local name flow_id
  name="$(basename "$file")"
  flow_id="$(grep '^id:' "$file" | awk '{print $2}')"
  echo "  -> ${name} (${flow_id})"

  for base in "${KESTRA_URL}" "${KESTRA_PUBLIC_URL}"; do
    [[ -z "$base" ]] && continue
    if curl -sf -X POST "${base}/api/v1/main/flows" \
      -H "Content-Type: application/x-yaml" \
      --data-binary @"${file}"; then
      return 0
    fi
    if curl -sf -X PUT "${base}/api/v1/main/flows/main/${flow_id}" \
      -H "Content-Type: application/x-yaml" \
      --data-binary @"${file}"; then
      return 0
    fi
  done
  echo "FAIL ${name}"
  return 1
}

echo "==> Import flows"

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"

for flow in oke-health-check.yaml oke-deploy-simple.yaml oke-deploy-rollout.yaml oke-deploy-pipeline.yaml; do
  path="${ROOT}/kestra/flows/${flow}"
  [[ -f "$path" ]] && import_flow "$path" || echo "SKIP ${flow}"
done

echo ""
echo "Test execution (health-check):"
for base in "${KESTRA_URL}" "${KESTRA_PUBLIC_URL}"; do
  [[ -z "$base" ]] && continue
  if curl -sf -X POST "${base}/api/v1/main/executions/main/oke-health-check"; then
    echo " OK via ${base}"
    exit 0
  fi
done
echo "WARN: could not trigger test execution"
