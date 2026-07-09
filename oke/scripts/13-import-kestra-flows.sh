#!/usr/bin/env bash
# Import Enlight Lab flows into Kestra (requires basic-auth).
set -euo pipefail

KESTRA_URL="${KESTRA_URL:-http://kestra.144-24-100-85.nip.io}"
KESTRA_PUBLIC_URL="${KESTRA_PUBLIC_URL:-}"
KESTRA_USER="${KESTRA_USER:-admin@enlightlab.com}"
KESTRA_PASS="${KESTRA_PASS:-}"

if [[ -z "${KESTRA_PASS}" ]]; then
  echo "ERROR: Set KESTRA_PASS (same password as Kestra UI login)"
  exit 1
fi

AUTH=(-u "${KESTRA_USER}:${KESTRA_PASS}")

import_flow() {
  local file="$1"
  local name flow_id
  name="$(basename "$file")"
  flow_id="$(grep '^id:' "$file" | awk '{print $2}')"
  echo "  -> ${name} (${flow_id})"

  for base in "${KESTRA_URL}" "${KESTRA_PUBLIC_URL}"; do
    [[ -z "$base" ]] && continue
    if curl -sf "${AUTH[@]}" -X POST "${base}/api/v1/main/flows" \
      -H "Content-Type: application/x-yaml" \
      --data-binary @"${file}"; then
      echo "     OK POST via ${base}"
      return 0
    fi
    if curl -sf "${AUTH[@]}" -X PUT "${base}/api/v1/main/flows/main/${flow_id}" \
      -H "Content-Type: application/x-yaml" \
      --data-binary @"${file}"; then
      echo "     OK PUT via ${base}"
      return 0
    fi
    echo "     FAIL via ${base} (check user/pass and Kestra URL)"
  done
  echo "FAIL ${name}"
  return 1
}

echo "==> Import flows to ${KESTRA_URL}"

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"

for flow in oke-health-check.yaml oke-deploy-simple.yaml oke-deploy-rollout.yaml oke-deploy-pipeline.yaml oke-dagger-gitops-pipeline.yaml; do
  path="${ROOT}/kestra/flows/${flow}"
  [[ -f "$path" ]] && import_flow "$path" || echo "SKIP ${flow}"
done

echo ""
echo "Test execution (health-check):"
for base in "${KESTRA_URL}" "${KESTRA_PUBLIC_URL}"; do
  [[ -z "$base" ]] && continue
  if curl -sf "${AUTH[@]}" -X POST "${base}/api/v1/main/executions/main/oke-health-check"; then
    echo " OK via ${base}"
    exit 0
  fi
done
echo "WARN: could not trigger test execution"
