#!/usr/bin/env bash
# Build linux/amd64 console image from Cloud Shell (arm64 host → amd64 OKE nodes).
set -euo pipefail

NS="${NS:-enlight-platform}"
TAG="${CONSOLE_TAG:-v22}"
IMAGE="ap-mumbai-1.ocir.io/bmitpaosivqx/enlight-console:${TAG}"
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"

echo "=========================================="
echo " Build console ${TAG} for linux/amd64"
echo "=========================================="

if [[ ! -f "${ROOT}/console/Dockerfile" ]]; then
  echo "ERROR: git pull first — console/ not found under ${ROOT}"
  exit 1
fi

echo "==> Docker login (if needed)"
docker login ap-mumbai-1.ocir.io || true

echo "==> Build --platform linux/amd64 (required for OKE x86 nodes)"
cd "${ROOT}/console"
docker build --platform linux/amd64 -t "${IMAGE}" .

echo "==> Push ${IMAGE}"
docker push "${IMAGE}"

echo "==> Safe deploy (no rollout hang)"
CONSOLE_IMAGE="${IMAGE}" bash "${ROOT}/oke/scripts/40-deploy-console-safe.sh"
