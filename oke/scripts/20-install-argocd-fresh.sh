#!/usr/bin/env bash
# Fresh ArgoCD install + ingress for argocd.enlightlab.com and gitops.<nip-host>
#
# Usage:
#   export INGRESS_HOST=144-24-100-85.nip.io
#   bash oke/scripts/20-install-argocd-fresh.sh
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
OKE_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
INGRESS_HOST="${INGRESS_HOST:-144-24-100-85.nip.io}"
ARGOCD_PASS="${ARGOCD_PASSWORD:-EnlightDemo2026!}"

echo "=============================================="
echo " Install ArgoCD (namespace was missing)"
echo "=============================================="

echo "==> 1/6 Namespace + ArgoCD"
kubectl create namespace argocd --dry-run=client -o yaml | kubectl apply -f -
kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml
kubectl rollout status deployment/argocd-server -n argocd --timeout=600s

echo "==> 2/6 ClusterIP + insecure HTTP (for ingress)"
kubectl patch svc argocd-server -n argocd -p '{"spec":{"type":"ClusterIP"}}' 2>/dev/null || true
kubectl patch configmap argocd-cmd-params-cm -n argocd --type merge -p \
  '{"data":{"server.rootpath":"","server.insecure":"true"}}'
kubectl rollout restart deployment/argocd-server -n argocd
kubectl rollout status deployment/argocd-server -n argocd --timeout=300s

echo "==> 3/6 Ingress — argocd.enlightlab.com"
kubectl apply -f "${OKE_ROOT}/ingress/argocd-enlightlab-host.yaml"

echo "==> 4/6 Ingress — gitops.${INGRESS_HOST}"
sed "s|PLACEHOLDER_HOST|${INGRESS_HOST}|g" "${OKE_ROOT}/ingress/gitops-host.yaml" | kubectl apply -f -

echo "==> 5/6 Set admin password to ${ARGOCD_PASS}"
HASH=$(kubectl run "argocd-bcrypt-$$" --rm -i --restart=Never -n argocd \
  --image=quay.io/argoproj/argocd:v2.13.2 \
  --env="PASS=${ARGOCD_PASS}" \
  --command -- sh -c 'printf "%s" "$PASS" | argocd account bcrypt' 2>/dev/null | tail -1)
if [[ -z "$HASH" || "$HASH" != \$2* ]]; then
  echo "ERROR: bcrypt failed — run oke/scripts/22-argocd-password-deep-fix.sh"
  exit 1
fi
python3 << PY
import json
h = """${HASH}"""
json.dump({"stringData": {"admin.password": h, "admin.passwordMtime": "$(date -u +%Y-%m-%dT%H:%M:%SZ)"}}, open("/tmp/argocd-patch.json", "w"))
PY
kubectl patch secret argocd-secret -n argocd --type merge --patch-file /tmp/argocd-patch.json
kubectl rollout restart deployment/argocd-server -n argocd
kubectl rollout status deployment/argocd-server -n argocd --timeout=300s

echo "==> 6/6 Verify"
sleep 3
curl -sI -H "Host: argocd.enlightlab.com" http://144.24.100.85/ | head -3
curl -sI -H "Host: gitops.${INGRESS_HOST}" http://144.24.100.85/ | head -3

echo ""
echo "=============================================="
echo " DONE"
echo "  http://argocd.enlightlab.com"
echo "  http://gitops.${INGRESS_HOST}"
echo "  username: admin"
echo "  password: ${ARGOCD_PASS}"
echo "=============================================="
