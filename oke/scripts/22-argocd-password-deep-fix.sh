#!/usr/bin/env bash
# Deep ArgoCD admin password reset — fixes corrupt "Error: unknown flag" hash in secret.
# Usage: bash oke/scripts/22-argocd-password-deep-fix.sh
set -euo pipefail

NS=argocd
USER=admin
PASS="${ARGOCD_PASSWORD:-EnlightDemo2026!}"

echo "=============================================="
echo " ArgoCD deep password fix"
echo " Target: ${USER} / ${PASS}"
echo "=============================================="

echo "==> 0) Diagnose current secret (corrupt hash = login always fails)"
RAW=$(kubectl get secret argocd-secret -n "$NS" -o jsonpath='{.data.admin\.password}' 2>/dev/null | base64 -d 2>/dev/null || true)
if [[ -n "$RAW" ]]; then
  echo "admin.password starts with: ${RAW:0:40}..."
  if [[ "$RAW" != \$2* ]]; then
    echo "PROBLEM: hash is NOT bcrypt (likely 'Error: unknown flag' from bad reset)"
  fi
else
  echo "admin.password not set — will use initial-admin-secret"
fi

echo "==> 1) Ensure local admin enabled + correct external URL"
kubectl patch configmap argocd-cm -n "$NS" --type merge -p \
  '{"data":{"admin.enabled":"true","url":"https://argocd.enlightlab.com"}}' 2>/dev/null || true

echo "==> 2) Clear login rate-limit (redis)"
kubectl delete pod -n "$NS" -l app.kubernetes.io/name=argocd-redis --force --grace-period=0 2>/dev/null || true
sleep 3

echo "==> 3) Set initial-admin-secret (plaintext fallback)"
kubectl create secret generic argocd-initial-admin-secret -n "$NS" \
  --from-literal=password="${PASS}" \
  --dry-run=client -o yaml | kubectl apply -f -

echo "==> 4) Remove corrupt admin.password from argocd-secret"
kubectl get secret argocd-secret -n "$NS" -o json | python3 -c "
import json, sys
s = json.load(sys.stdin)
s.get('data', {}).pop('admin.password', None)
s.get('data', {}).pop('admin.passwordMtime', None)
json.dump(s, sys.stdout)
" | kubectl apply -f -

echo "==> 5) Generate bcrypt"
HASH=""
# Method A: same-version CLI inside argocd-server pod (best match)
HASH=$(kubectl exec -n "$NS" deploy/argocd-server -- argocd account bcrypt --password "${PASS}" 2>/dev/null | tail -1 || true)

# Method B: htpasswd image (no argocd CLI)
if [[ -z "$HASH" || "$HASH" != \$2* ]]; then
  HASH=$(kubectl run "htpasswd-$$" --rm -i --restart=Never -n "$NS" \
    --image=httpd:2.4-alpine \
    --command -- htpasswd -nbBC 10 "" "${PASS}" 2>/dev/null | cut -d: -f2 || true)
fi

if [[ -n "$HASH" && "$HASH" == \$2* ]]; then
  echo "bcrypt ok (${#HASH} chars)"
  python3 -c "
import json
json.dump({
  'stringData': {
    'admin.password': '''${HASH}''',
    'admin.passwordMtime': '$(date -u +%Y-%m-%dT%H:%M:%SZ)'
  }
}, open('/tmp/argocd-pw-patch.json', 'w'))
"
  kubectl patch secret argocd-secret -n "$NS" --type merge --patch-file /tmp/argocd-pw-patch.json
else
  echo "WARN: bcrypt generation failed — using initial-admin-secret only"
  echo "      (this still works after step 4 removed corrupt hash)"
fi

echo "==> 6) Restart argocd-server"
kubectl rollout restart deployment/argocd-server -n "$NS"
kubectl rollout status deployment/argocd-server -n "$NS" --timeout=300s
sleep 5

echo "==> 7) API login test (via argocd-server pod — no ephemeral pod)"
RESP=$(kubectl exec -n "$NS" deploy/argocd-server -- sh -c \
  "wget -qO- --post-data='username=${USER}&password=${PASS}' --header='Content-Type: application/x-www-form-urlencoded' http://127.0.0.1:8080/api/v1/session" 2>/dev/null || echo '{"error":"wget failed"}')

if echo "$RESP" | grep -q '"token"'; then
  echo "SUCCESS: API login works — password is correct"
else
  echo "API response: $RESP"
  echo "If still failing, run diagnostics in docs below"
fi

echo ""
echo "=============================================="
echo " Login: https://argocd.enlightlab.com"
echo "   username: ${USER}   (NOT an email)"
echo "   password: ${PASS}"
echo " Use Incognito. Copy-paste password."
echo "=============================================="
