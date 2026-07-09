#!/usr/bin/env bash
# Wire argocd.enlightlab.com -> argocd-server (same LB as console).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
OKE_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

echo "==> Check ArgoCD is running"
kubectl get pods -n argocd -l app.kubernetes.io/name=argocd-server

echo "==> Ensure ArgoCD serves at root (no /gitops prefix)"
kubectl patch configmap argocd-cmd-params-cm -n argocd --type merge -p \
  '{"data":{"server.rootpath":"","server.insecure":"true"}}' 2>/dev/null || true
kubectl rollout restart deployment/argocd-server -n argocd
kubectl rollout status deployment/argocd-server -n argocd --timeout=300s

echo "==> Apply ingress argocd.enlightlab.com"
kubectl apply -f "${OKE_ROOT}/ingress/argocd-enlightlab-host.yaml"

echo ""
kubectl get ingress -n argocd
echo ""
echo "Open: http://argocd.enlightlab.com"
echo "Login: admin"
echo "Password:"
kubectl get secret argocd-initial-admin-secret -n argocd -o jsonpath='{.data.password}' 2>/dev/null | base64 -d || echo "(run 18-reset-argocd-password.sh if needed)"
echo ""
