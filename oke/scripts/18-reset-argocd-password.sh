#!/usr/bin/env bash
# Reset ArgoCD admin password to a known value (Cloud Shell).
# Usage: bash oke/scripts/18-reset-argocd-password.sh
# Default password: EnlightDemo2026!
set -euo pipefail

NEW_PASS="${ARGOCD_PASSWORD:-EnlightDemo2026!}"
NS=argocd

echo "==> Diagnose current hash"
RAW=$(kubectl get secret argocd-secret -n "$NS" -o jsonpath='{.data.admin\.password}' 2>/dev/null | base64 -d 2>/dev/null || true)
if [[ -n "$RAW" && "$RAW" != \$2* ]]; then
  echo "WARN: corrupt admin.password detected: ${RAW:0:50}..."
fi

echo "==> Clear redis lockout"
kubectl delete pod -n "$NS" -l app.kubernetes.io/name=argocd-redis --force --grace-period=0 2>/dev/null || true

echo "==> Generate bcrypt hash (inside argocd-server pod)"
HASH=$(kubectl exec -n "$NS" deploy/argocd-server -- argocd account bcrypt --password "${NEW_PASS}" 2>/dev/null | tail -1)

if [[ -z "$HASH" || "$HASH" != \$2* ]]; then
  echo "Fallback: htpasswd"
  HASH=$(kubectl run htpasswd-$$ --rm -i --restart=Never -n "$NS" \
    --image=httpd:2.4-alpine \
    --command -- htpasswd -nbBC 10 "" "${NEW_PASS}" 2>/dev/null | cut -d: -f2)
fi

if [[ -z "$HASH" || "$HASH" != \$2* ]]; then
  echo "ERROR: could not generate bcrypt hash"
  exit 1
fi

echo "==> Patch argocd-secret"
python3 -c "
import json
json.dump({
  'stringData': {
    'admin.password': '''${HASH}''',
    'admin.passwordMtime': '$(date -u +%Y-%m-%dT%H:%M:%SZ)'
  }
}, open('/tmp/argocd-patch.json', 'w'))
"
kubectl patch secret argocd-secret -n "$NS" --type merge --patch-file /tmp/argocd-patch.json

kubectl create secret generic argocd-initial-admin-secret -n "$NS" \
  --from-literal=password="${NEW_PASS}" \
  --dry-run=client -o yaml | kubectl apply -f -

echo "==> Restart argocd-server"
kubectl rollout restart deployment/argocd-server -n "$NS"
kubectl rollout status deployment/argocd-server -n "$NS" --timeout=300s

echo ""
echo "=============================================="
echo " ArgoCD login: https://argocd.enlightlab.com"
echo "   username: admin"
echo "   password: ${NEW_PASS}"
echo "=============================================="
