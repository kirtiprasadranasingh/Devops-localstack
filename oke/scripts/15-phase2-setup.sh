#!/usr/bin/env bash
# Phase 2 — ArgoCD (/gitops) + Grafana (/metrics) on existing OKE cluster.
#
# Usage (Cloud Shell):
#   export INGRESS_HOST=144-24-100-85.nip.io
#   bash oke/scripts/15-phase2-setup.sh
#
# Optional: skip steps
#   SKIP_MONITORING=1 bash oke/scripts/15-phase2-setup.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
OKE_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
INGRESS_HOST="${INGRESS_HOST:-144-24-100-85.nip.io}"
PUBLIC_BASE="${PUBLIC_BASE_URL:-http://${INGRESS_HOST}}"

echo "=============================================="
echo " Enlight Lab — Phase 2"
echo " GitOps:   http://gitops.${INGRESS_HOST}"
echo " Metrics:  http://metrics.${INGRESS_HOST}"
echo "=============================================="

echo ""
echo "==> Step 1/5 — ArgoCD namespace + install"
kubectl create namespace argocd --dry-run=client -o yaml | kubectl apply -f -
kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml
kubectl rollout status deployment/argocd-server -n argocd --timeout=600s || true

echo ""
echo "==> Step 2/5 — ArgoCD config (path /gitops, HTTP ingress)"
kubectl patch svc argocd-server -n argocd -p '{"spec":{"type":"ClusterIP"}}' 2>/dev/null || true
kubectl patch configmap argocd-cmd-params-cm -n argocd --type merge -p \
  '{"data":{"server.rootpath":"/gitops","server.insecure":"true"}}' 2>/dev/null || true
kubectl rollout restart deployment/argocd-server -n argocd 2>/dev/null || true
kubectl rollout status deployment/argocd-server -n argocd --timeout=300s || true

echo ""
echo "==> Step 3/5 — ArgoCD ingress (subdomain gitops.${INGRESS_HOST})"
kubectl patch configmap argocd-cmd-params-cm -n argocd --type merge -p \
  '{"data":{"server.rootpath":"","server.insecure":"true"}}' 2>/dev/null || true
kubectl rollout restart deployment/argocd-server -n argocd 2>/dev/null || true
kubectl rollout status deployment/argocd-server -n argocd --timeout=300s 2>/dev/null || true
sed "s|PLACEHOLDER_HOST|${INGRESS_HOST}|g" "${OKE_ROOT}/ingress/gitops-host.yaml" | kubectl apply -f -

echo ""
echo "==> Step 4/5 — GitOps application (demo ConfigMap in enlight-staging)"
kubectl apply -f "${OKE_ROOT}/gitops/argocd/fastapi-staging.yaml" || \
  echo "WARN: ArgoCD Application apply failed — push repo to GitHub first, then re-apply"

# Bootstrap configmap directly so demo works even before git sync
kubectl apply -f "${OKE_ROOT}/gitops/apps/fastapi-staging/configmap.yaml"

if [[ "${SKIP_MONITORING:-0}" != "1" ]]; then
  echo ""
  echo "==> Step 5/5 — Grafana monitoring at /metrics (helm, ~5-10 min)"
  if command -v helm >/dev/null 2>&1; then
    bash "${SCRIPT_DIR}/09-install-monitoring.sh" "${INGRESS_HOST}"
  else
    echo "helm not found — install monitoring manually:"
    echo "  bash oke/scripts/09-install-monitoring.sh ${INGRESS_HOST}"
  fi
else
  echo ""
  echo "==> Step 5/5 — Skipped monitoring (SKIP_MONITORING=1)"
fi

echo ""
echo "=============================================="
echo " ArgoCD admin password:"
kubectl get secret argocd-initial-admin-secret -n argocd -o jsonpath='{.data.password}' 2>/dev/null | base64 -d || echo "(wait 1 min, re-run)"
echo ""
echo " URLs:"
echo "  Console:  ${PUBLIC_BASE}"
echo "  GitOps:   http://gitops.${INGRESS_HOST}"
echo "  Metrics:  http://metrics.${INGRESS_HOST}  (admin / admin after helm install)"
echo "  Kestra:   http://kestra.${INGRESS_HOST}"
echo ""
echo " Next — Kestra build secrets (optional full pipeline):"
echo "  bash oke/scripts/16-kestra-secrets.sh"
echo "=============================================="
