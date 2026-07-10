#!/usr/bin/env bash
# Reliable enlight-console deploy — never hangs on "old replicas pending termination".
set -euo pipefail

NS="${NS:-enlight-platform}"
PREFERRED="${CONSOLE_IMAGE:-ap-mumbai-1.ocir.io/bmitpaosivqx/enlight-console:v23}"
FALLBACK="${CONSOLE_FALLBACK:-ap-mumbai-1.ocir.io/bmitpaosivqx/enlight-console:v20}"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"

echo "=========================================="
echo " Safe console deploy (no rollout hang)"
echo "=========================================="

pick_image() { docker pull "$1" >/dev/null 2>&1; }

echo ""
echo "==> 1) Image tag (skip docker pull on Cloud Shell — it is arm64, cluster is amd64)"
IMAGE="${PREFERRED}"
echo "    Target: ${IMAGE}"
echo "    Note: verify via pod events if deploy fails (ImagePullBackOff = tag missing in OCIR)"

# Optional: only test pull when host matches cluster arch (amd64)
ARCH="$(uname -m)"
if [[ "${ARCH}" == "x86_64" ]]; then
  if ! docker pull "${PREFERRED}" >/dev/null 2>&1; then
    echo "    WARN: ${PREFERRED} not pullable — falling back to ${FALLBACK}"
    IMAGE="${FALLBACK}"
    docker pull "${IMAGE}" >/dev/null 2>&1 || {
      echo "ERROR: Neither image exists. Build with: docker build --platform linux/amd64 ..."
      exit 1
    }
  fi
fi

echo ""
echo "==> 2) RBAC + Recreate strategy"
kubectl apply -f "${ROOT}/oke/manifests/32-console-rbac.yaml" 2>/dev/null || true
kubectl patch serviceaccount enlight-console -n "${NS}" --type=merge \
  -p '{"imagePullSecrets":[{"name":"ocir-pull-secret"}]}' 2>/dev/null || true
kubectl patch deployment enlight-console -n "${NS}" --type=json -p='[
  {"op":"replace","path":"/spec/strategy","value":{"type":"Recreate"}}
]' 2>/dev/null || true
kubectl patch deployment enlight-console -n "${NS}" --type=merge -p \
  '{"spec":{"progressDeadlineSeconds":600,"revisionHistoryLimit":2}}' 2>/dev/null || true

echo ""
echo "==> 3) Scale to zero + force-delete stuck pods"
kubectl set image deployment/enlight-console "console=${IMAGE}" -n "${NS}"
kubectl scale deployment/enlight-console -n "${NS}" --replicas=0
sleep 3
kubectl delete pods -n "${NS}" -l app=enlight-console --force --grace-period=0 2>/dev/null || true
kubectl get rs -n "${NS}" -l app=enlight-console -o name 2>/dev/null | while read -r rs; do
  kubectl delete "${rs}" -n "${NS}" --force --grace-period=0 2>/dev/null || true
done

echo ""
echo "==> 4) Scale to one + wait for Ready"
kubectl scale deployment/enlight-console -n "${NS}" --replicas=1

for i in $(seq 1 36); do
  READY=$(kubectl get pods -n "${NS}" -l app=enlight-console \
    -o jsonpath='{.items[0].status.containerStatuses[0].ready}' 2>/dev/null || true)
  if [[ "${READY}" == "true" ]]; then
    echo "    Pod ready."
    break
  fi
  if kubectl get pods -n "${NS}" -l app=enlight-console 2>/dev/null | grep -qE 'ImagePullBackOff|ErrImagePull'; then
    echo "ERROR: Image pull failed:"
    kubectl describe pod -n "${NS}" -l app=enlight-console | sed -n '/Events:/,$p' | tail -12
    exit 1
  fi
  sleep 5
done

kubectl get pods -n "${NS}" -l app=enlight-console -o wide
curl -sf "http://144-24-100-85.nip.io/api/health" || true
echo ""
echo "Done: http://144-24-100-85.nip.io"
