# Wipe Kestra data + set known strong basic-auth (Kestra rejects weak passwords).
# Cloud Shell: bash oke/scripts/14-reset-kestra-auth.sh
set -euo pipefail

NS=enlight-platform
USER="${KESTRA_USER:-admin@enlightlab.com}"
PASS="${KESTRA_PASS:-Admin1234}"

echo "==> Patch Kestra with strong basic-auth ($USER / $PASS)"
kubectl set env deployment/kestra -n "$NS" --containers=kestra KESTRA_CONFIGURATION="
kestra:
  tutorialFlows:
    enabled: false
  server:
    basic-auth:
      username: ${USER}
      password: ${PASS}
"

echo "==> Scale down and delete pods (clear in-memory/emptyDir)"
kubectl scale deployment/kestra -n "$NS" --replicas=0
kubectl delete pods -n "$NS" -l app=kestra --force --grace-period=0 2>/dev/null || true
sleep 3
kubectl scale deployment/kestra -n "$NS" --replicas=1
kubectl rollout status deployment/kestra -n "$NS" --timeout=300s

echo ""
echo "Login at: http://kestra.144-24-100-85.nip.io"
echo "  user: $USER"
echo "  pass: $PASS"
echo ""
echo "Then re-import flow oke-deploy-simple (DB was wiped)."
