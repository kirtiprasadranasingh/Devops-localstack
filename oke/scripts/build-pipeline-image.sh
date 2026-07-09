#!/usr/bin/env bash
# Build and push enlight-pipeline runner image to OCIR.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
IMAGE="${PIPELINE_IMAGE:-ap-mumbai-1.ocir.io/bmitpaosivqx/enlight-pipeline:v1}"

echo "==> Build ${IMAGE}"
docker build -t "${IMAGE}" "${ROOT}/oke/pipeline-runner"
docker push "${IMAGE}"
echo "Done. Pipeline image ready for oke-dagger-gitops-pipeline"
