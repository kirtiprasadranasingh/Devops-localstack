#!/usr/bin/env bash
# EMERGENCY: restore enlight-console v20 when deploy is broken / 503.
set -euo pipefail
NS=enlight-platform
IMAGE=ap-mumbai-1.ocir.io/bmitpaosivqx/enlight-console:v20

kubectl patch deployment enlight-console -n $NS --type=merge -p \
  '{"spec":{"strategy":{"type":"Recreate"},"progressDeadlineSeconds":600}}'
kubectl set image deployment/enlight-console console="$IMAGE" -n $NS
kubectl scale deployment enlight-console -n $NS --replicas=0
sleep 4
kubectl delete pods -n $NS -l app=enlight-console --force --grace-period=0 2>/dev/null || true
kubectl get rs -n $NS -l app=enlight-console -o name 2>/dev/null | xargs -r -I{} kubectl delete {} -n $NS --force --grace-period=0 2>/dev/null || true
kubectl scale deployment enlight-console -n $NS --replicas=1

for i in $(seq 1 30); do
  READY=$(kubectl get pods -n $NS -l app=enlight-console -o jsonpath='{.items[0].status.containerStatuses[0].ready}' 2>/dev/null || true)
  [[ "$READY" == "true" ]] && break
  sleep 5
done
kubectl get pods -n $NS -l app=enlight-console
curl -s http://144-24-100-85.nip.io/api/health; echo
