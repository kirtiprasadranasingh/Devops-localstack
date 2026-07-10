#!/usr/bin/env bash
# Fix Kestra flow still using PT15M wait — force re-import from repo.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
FLOW="${ROOT}/kestra/flows/oke-dagger-gitops-pipeline.yaml"

echo "==> Local flow wait duration:"
grep -A1 'wait-pipeline' "$FLOW" | grep duration || true

echo "==> Re-import via port-forward"
bash "${SCRIPT_DIR}/19-import-flows-portforward.sh"

echo ""
echo "If wait still shows PT15M, the repo on Cloud Shell is outdated:"
echo "  git pull origin main"
echo "  bash oke/scripts/33-fix-kestra-flow-wait.sh"
