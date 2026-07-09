# Cloud Shell — fix stuck enlight-console rollout
# Paste commands one block at a time.

echo "=== Pods ==="
kubectl get pods -n enlight-platform -l app=enlight-console -o wide

echo ""
echo "=== Events (last) ==="
kubectl get events -n enlight-platform --field-selector involvedObject.name=enlight-console --sort-by='.lastTimestamp' | tail -15

echo ""
echo "=== Describe newest pod ==="
POD=$(kubectl get pods -n enlight-platform -l app=enlight-console --sort-by=.metadata.creationTimestamp -o jsonpath='{.items[-1:].metadata.name}')
echo "POD=$POD"
kubectl describe pod "$POD" -n enlight-platform | tail -40

echo ""
echo "=== Image + env ==="
kubectl get deploy enlight-console -n enlight-platform -o jsonpath='image={.spec.template.spec.containers[0].image}{"\n"}'
kubectl get deploy enlight-console -n enlight-platform -o jsonpath='{range .spec.template.spec.containers[0].env[*]}{.name}={.value}{"\n"}{end}'
