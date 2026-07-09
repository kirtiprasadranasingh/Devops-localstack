#!/usr/bin/env bash
# Fix Kestra not starting: OKE volume attach conflicts + slow/crash startup.
set -euo pipefail

NS="${KESTRA_NAMESPACE:-enlight-platform}"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"

echo "==> Current pod + logs"
kubectl get pods -n "${NS}" -l app=kestra -o wide
echo ""
kubectl logs -n "${NS}" -l app=kestra --tail=80 2>/dev/null || true

echo ""
echo "==> Switch to emptyDir (avoids dual PVC attach issues on OKE)"
kubectl scale deployment/kestra -n "${NS}" --replicas=0
sleep 5
kubectl delete pod -n "${NS}" -l app=kestra --force --grace-period=0 2>/dev/null || true

kubectl apply -f "${ROOT}/oke/manifests/30-kestra-emptydir.yaml"

# Re-apply secrets from deployment env (if already set they persist on deployment object)
echo ""
echo "==> Start Kestra"
kubectl scale deployment/kestra -n "${NS}" --replicas=1

echo "Waiting up to 15 minutes for Kestra (first start is slow)..."
for i in $(seq 1 90); do
  if kubectl exec -n "${NS}" deploy/kestra -- wget -q -O- http://127.0.0.1:8080/api/v1/configs >/dev/null 2>&1; then
    echo "Kestra API is up after ${i}0s"
    break
  fi
  READY=$(kubectl get pods -n "${NS}" -l app=kestra -o jsonpath='{.items[0].status.containerStatuses[0].ready}' 2>/dev/null || echo "false")
  RESTARTS=$(kubectl get pods -n "${NS}" -l app=kestra -o jsonpath='{.items[0].status.containerStatuses[0].restartCount}' 2>/dev/null || echo "?")
  echo "  wait ${i}/90 — ready=${READY} restarts=${RESTARTS}"
  if [[ "${RESTARTS}" != "?" && "${RESTARTS}" -gt 2 ]]; then
    echo "Pod crash-looping — last logs:"
    kubectl logs -n "${NS}" -l app=kestra --tail=40
    exit 1
  fi
  sleep 10
done

kubectl get pods -n "${NS}" -l app=kestra

echo ""
echo "==> Re-import flows"
export KESTRA_USER="${KESTRA_USER:-admin@enlightlab.com}"
export KESTRA_PASS="${KESTRA_PASS:-Admin1234}"
bash "${SCRIPT_DIR}/19-import-flows-portforward.sh"

echo ""
echo "Done. Open http://kestra.144-24-100-85.nip.io"
