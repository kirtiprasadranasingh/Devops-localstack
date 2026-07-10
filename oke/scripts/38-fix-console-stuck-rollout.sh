#!/usr/bin/env bash
# Recover stuck enlight-console rollout (ImagePullBackOff, Terminating pod, SA missing).
set -euo pipefail

NS="${NS:-enlight-platform}"
PREFERRED="${CONSOLE_IMAGE:-ap-mumbai-1.ocir.io/bmitpaosivqx/enlight-console:v21}"
FALLBACK="${CONSOLE_FALLBACK:-ap-mumbai-1.ocir.io/bmitpaosivqx/enlight-console:v20}"

echo "=========================================="
echo " enlight-console rollout recovery"
echo "=========================================="

echo ""
echo "==> 1) Current pods"
kubectl get pods -n "${NS}" -l app=enlight-console -o wide || true

NEW_POD=$(kubectl get pods -n "${NS}" -l app=enlight-console \
  --sort-by=.metadata.creationTimestamp \
  -o jsonpath='{.items[-1].metadata.name}' 2>/dev/null || true)

if [[ -n "${NEW_POD}" ]]; then
  echo ""
  echo "==> 2) Newest pod events (${NEW_POD})"
  kubectl describe pod "${NEW_POD}" -n "${NS}" | sed -n '/Events:/,$p' | tail -20
fi

echo ""
echo "==> 3) Ensure ServiceAccount + RBAC"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
if [[ -f "${ROOT}/oke/manifests/32-console-rbac.yaml" ]]; then
  kubectl apply -f "${ROOT}/oke/manifests/32-console-rbac.yaml"
else
  echo "WARN: 32-console-rbac.yaml not found — applying inline SA"
  kubectl apply -f - <<'EOF'
apiVersion: v1
kind: ServiceAccount
metadata:
  name: enlight-console
  namespace: enlight-platform
EOF
fi

kubectl patch serviceaccount enlight-console -n "${NS}" --type=merge \
  -p '{"imagePullSecrets":[{"name":"ocir-pull-secret"}]}' 2>/dev/null || true

kubectl patch deployment enlight-console -n "${NS}" --type=json -p='[
  {"op":"replace","path":"/spec/template/spec/serviceAccountName","value":"enlight-console"},
  {"op":"replace","path":"/spec/template/spec/imagePullSecrets","value":[{"name":"ocir-pull-secret"}]}
]' 2>/dev/null || true

kubectl patch deployment enlight-console -n "${NS}" -p '{"spec":{"progressDeadlineSeconds":900}}'

echo ""
echo "==> 4) Pick image (prefer ${PREFERRED}, fallback ${FALLBACK})"
IMAGE="${PREFERRED}"
if ! docker pull "${PREFERRED}" >/dev/null 2>&1; then
  echo "    ${PREFERRED} not pullable — using ${FALLBACK}"
  IMAGE="${FALLBACK}"
fi

kubectl set image deployment/enlight-console "console=${IMAGE}" -n "${NS}"

echo ""
echo "==> 5) Clear stuck pods + old ReplicaSets"
kubectl delete pods -n "${NS}" -l app=enlight-console --force --grace-period=0 2>/dev/null || true

kubectl get rs -n "${NS}" -l app=enlight-console -o name | while read -r rs; do
  want=$(kubectl get "${rs}" -n "${NS}" -o jsonpath='{.spec.replicas}' 2>/dev/null || echo 0)
  if [[ "${want}" == "0" ]]; then
    kubectl delete "${rs}" -n "${NS}" --force --grace-period=0 2>/dev/null || true
  fi
done

echo ""
echo "==> 6) Wait for rollout"
if kubectl rollout status deployment/enlight-console -n "${NS}" --timeout=300s; then
  echo "OK: rollout complete"
else
  echo "WARN: still not ready — describe:"
  kubectl get pods -n "${NS}" -l app=enlight-console
  kubectl describe pod -n "${NS}" -l app=enlight-console | tail -30
  exit 1
fi

echo ""
kubectl get pods -n "${NS}" -l app=enlight-console -o wide
curl -sf "http://144-24-100-85.nip.io/api/health" || true
echo ""
echo "Done. Console: http://144-24-100-85.nip.io"
