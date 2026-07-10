#!/usr/bin/env bash
# Fix console Live activity "Forbidden" — apply RBAC + ensure SA on deployment + restart.
set -euo pipefail

NS="${NS:-enlight-platform}"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
RBAC="${ROOT}/oke/manifests/32-console-rbac.yaml"

echo "=========================================="
echo " Fix console pipeline log RBAC"
echo "=========================================="

if [[ ! -f "${RBAC}" ]]; then
  echo "ERROR: ${RBAC} not found — clone repo first"
  exit 1
fi

echo "==> 1) Apply RBAC (jobs, jobs/status, pods/log)"
kubectl apply -f "${RBAC}"

echo "==> 2) Ensure deployment uses enlight-console ServiceAccount"
kubectl patch deployment enlight-console -n "${NS}" --type=json -p='[
  {"op":"add","path":"/spec/template/spec/serviceAccountName","value":"enlight-console"}
]' 2>/dev/null || \
kubectl patch deployment enlight-console -n "${NS}" --type=merge -p \
  '{"spec":{"template":{"spec":{"serviceAccountName":"enlight-console"}}}}'

kubectl patch serviceaccount enlight-console -n "${NS}" --type=merge \
  -p '{"imagePullSecrets":[{"name":"ocir-pull-secret"}]}' 2>/dev/null || true

echo "==> 3) Restart console pod (pick up new RBAC token)"
kubectl scale deployment enlight-console -n "${NS}" --replicas=0
sleep 3
kubectl delete pods -n "${NS}" -l app=enlight-console --force --grace-period=0 2>/dev/null || true
kubectl scale deployment enlight-console -n "${NS}" --replicas=1

for i in $(seq 1 24); do
  READY=$(kubectl get pods -n "${NS}" -l app=enlight-console \
    -o jsonpath='{.items[0].status.containerStatuses[0].ready}' 2>/dev/null || true)
  [[ "${READY}" == "true" ]] && break
  sleep 5
done

echo ""
echo "==> 4) Verify SA + can-i"
SA=$(kubectl get deployment enlight-console -n "${NS}" \
  -o jsonpath='{.spec.template.spec.serviceAccountName}')
echo "    ServiceAccount: ${SA:-default}"

kubectl auth can-i get jobs --as="system:serviceaccount:${NS}:enlight-console" -n "${NS}"
kubectl auth can-i get jobs/status --as="system:serviceaccount:${NS}:enlight-console" -n "${NS}"
kubectl auth can-i get pods/log --as="system:serviceaccount:${NS}:enlight-console" -n "${NS}"

echo ""
echo "==> 5) Health"
curl -sf "http://144-24-100-85.nip.io/api/health" || true
echo ""
echo "Done — re-run client demo; Live activity should stream pipeline logs."
