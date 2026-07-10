#!/usr/bin/env bash
# Fix enlight-console rollout — creates missing ServiceAccount, deploys v18.
set -euo pipefail

NS="${NS:-enlight-platform}"
CONSOLE_IMAGE="${CONSOLE_IMAGE:-ap-mumbai-1.ocir.io/bmitpaosivqx/enlight-console:v19}"
INGRESS_HOST="${INGRESS_HOST:-144-24-100-85.nip.io}"

echo "=============================================="
echo " Fix enlight-console (SA + v18)"
echo "=============================================="

echo "==> 1/6 Create ServiceAccount + RBAC (root cause of FailedCreate)"
kubectl apply -f - <<EOF
apiVersion: v1
kind: ServiceAccount
metadata:
  name: enlight-console
  namespace: ${NS}
---
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  name: enlight-console-job-reader
  namespace: ${NS}
rules:
  - apiGroups: ["batch"]
    resources: ["jobs"]
    verbs: ["get", "list"]
  - apiGroups: [""]
    resources: ["pods", "pods/log"]
    verbs: ["get", "list"]
---
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: enlight-console-job-reader
  namespace: ${NS}
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: Role
  name: enlight-console-job-reader
subjects:
  - kind: ServiceAccount
    name: enlight-console
    namespace: ${NS}
EOF

echo "==> 2/6 OCIR pull secret on enlight-console SA"
if [[ -n "${OCIR_USERNAME:-}" && -n "${OCIR_TOKEN:-}" ]]; then
  bash "$(dirname "$0")/22-ocir-pull-secret.sh"
else
  kubectl patch serviceaccount enlight-console -n "${NS}" --type=merge \
    -p '{"imagePullSecrets":[{"name":"ocir-pull-secret"}]}' 2>/dev/null || true
fi

echo "==> 3/6 Set image ${CONSOLE_IMAGE}"
kubectl set image deployment/enlight-console console="${CONSOLE_IMAGE}" -n "${NS}"
kubectl patch deployment enlight-console -n "${NS}" -p '{"spec":{"progressDeadlineSeconds":900}}'
kubectl patch deployment enlight-console -n "${NS}" --type=json -p='[
  {"op":"replace","path":"/spec/template/spec/serviceAccountName","value":"enlight-console"},
  {"op":"replace","path":"/spec/template/spec/containers/0/imagePullPolicy","value":"Always"}
]'

kubectl set env deployment/enlight-console -n "${NS}" \
  PIPELINE_IMAGE=ap-mumbai-1.ocir.io/bmitpaosivqx/enlight-pipeline:v9 \
  MODE=oke \
  PUBLIC_BASE_URL="http://${INGRESS_HOST}" \
  KESTRA_PUBLIC_URL="http://kestra.${INGRESS_HOST}" \
  --overwrite 2>/dev/null || true

echo "==> 4/6 Scale down stuck old ReplicaSets"
kubectl get rs -n "${NS}" -l app=enlight-console -o name | while read -r rs; do
  ready=$(kubectl get "$rs" -n "${NS}" -o jsonpath='{.status.readyReplicas}' 2>/dev/null || echo 0)
  desired=$(kubectl get "$rs" -n "${NS}" -o jsonpath='{.spec.replicas}' 2>/dev/null || echo 0)
  if [[ "${ready:-0}" == "0" && "${desired:-0}" == "0" ]]; then
    kubectl delete "$rs" -n "${NS}" --ignore-not-found 2>/dev/null || true
  fi
done

echo "==> 5/6 Force new pod"
kubectl delete pods -n "${NS}" -l app=enlight-console --force --grace-period=0 2>/dev/null || true

for i in $(seq 1 60); do
  img=$(kubectl get pods -n "${NS}" -l app=enlight-console -o jsonpath='{.items[0].spec.containers[0].image}' 2>/dev/null || true)
  ready=$(kubectl get pods -n "${NS}" -l app=enlight-console -o jsonpath='{.items[0].status.containerStatuses[0].ready}' 2>/dev/null || true)
  if [[ "${img}" == *":v18" && "${ready}" == "true" ]]; then
    echo "Pod ready on v18"
    break
  fi
  sleep 5
done

echo "==> 6/6 Verify"
kubectl get pods -n "${NS}" -l app=enlight-console -o wide
kubectl get pods -n "${NS}" -l app=enlight-console \
  -o jsonpath='image={.items[0].spec.containers[0].image}{"\n"}'
curl -sf "http://${INGRESS_HOST}/api/health" && echo ""
echo "PASS if health shows console_version v18"
