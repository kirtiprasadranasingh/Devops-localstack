#!/usr/bin/env bash
# Recover Kestra when rollout is stuck on Pending PVC (common on OKE free tier).
set -euo pipefail

NS="${KESTRA_NAMESPACE:-enlight-platform}"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

echo "==> Diagnose"
kubectl get pvc -n "${NS}" 2>/dev/null || true
kubectl get pods -n "${NS}" -l app=kestra -o wide
echo ""
kubectl describe pod -n "${NS}" -l app=kestra 2>/dev/null | tail -25 || true

DATA_STATUS=$(kubectl get pvc kestra-data -n "${NS}" -o jsonpath='{.status.phase}' 2>/dev/null || echo "Missing")
DB_STATUS=$(kubectl get pvc kestra-db -n "${NS}" -o jsonpath='{.status.phase}' 2>/dev/null || echo "Missing")

if [[ "${DATA_STATUS}" == "Bound" && "${DB_STATUS}" == "Bound" ]]; then
  echo ""
  echo "PVCs are Bound — waiting for pod (up to 10 min)..."
  kubectl rollout status deployment/kestra -n "${NS}" --timeout=600s
  exit 0
fi

echo ""
echo "==> PVC not Bound (${DATA_STATUS}/${DB_STATUS}) — switching Kestra to emptyDir"
echo "    (Flows must be re-imported after restart; use 19-import-flows-portforward.sh)"

kubectl patch deployment kestra -n "${NS}" --type=json -p='[
  {"op":"replace","path":"/spec/template/spec/volumes/0","value":{"name":"kestra-data","emptyDir":{}}},
  {"op":"replace","path":"/spec/template/spec/volumes/1","value":{"name":"kestra-db","emptyDir":{}}}
]' 2>/dev/null || {
  echo "Patch failed — applying emptyDir manifest"
  kubectl apply -f "${SCRIPT_DIR}/../manifests/30-kestra-emptydir.yaml"
}

kubectl delete pod -n "${NS}" -l app=kestra --force --grace-period=0 2>/dev/null || true
kubectl rollout restart deployment/kestra -n "${NS}"
kubectl rollout status deployment/kestra -n "${NS}" --timeout=600s

echo ""
echo "==> Kestra running. Re-import flows:"
echo "  bash oke/scripts/19-import-flows-portforward.sh"
