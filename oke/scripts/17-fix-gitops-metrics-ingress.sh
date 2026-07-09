#!/usr/bin/env bash
# Fix GitOps + Grafana URLs — use subdomains (path /gitops hits console SPA).
#
# Usage:
#   export INGRESS_HOST=144-24-100-85.nip.io
#   bash oke/scripts/17-fix-gitops-metrics-ingress.sh
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
OKE_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
INGRESS_HOST="${INGRESS_HOST:-144-24-100-85.nip.io}"

echo "==> ArgoCD: remove /gitops rootpath (use subdomain instead)"
kubectl patch configmap argocd-cmd-params-cm -n argocd --type merge -p \
  '{"data":{"server.rootpath":"","server.insecure":"true"}}' 2>/dev/null || true
kubectl rollout restart deployment/argocd-server -n argocd 2>/dev/null || true
kubectl rollout status deployment/argocd-server -n argocd --timeout=300s 2>/dev/null || true

echo "==> GitOps ingress: gitops.${INGRESS_HOST}"
sed "s|PLACEHOLDER_HOST|${INGRESS_HOST}|g" "${OKE_ROOT}/ingress/gitops-host.yaml" | kubectl apply -f -

echo "==> Metrics ingress: metrics.${INGRESS_HOST}"
if kubectl get svc -n monitoring kube-prometheus-stack-grafana >/dev/null 2>&1; then
  sed "s|PLACEHOLDER_HOST|${INGRESS_HOST}|g" "${OKE_ROOT}/ingress/metrics-host.yaml" | kubectl apply -f -
else
  echo "WARN: Grafana not installed — run: bash oke/scripts/09-install-monitoring.sh ${INGRESS_HOST}"
fi

echo ""
echo "Open these URLs (not /gitops on console host):"
echo "  http://gitops.${INGRESS_HOST}"
echo "  http://metrics.${INGRESS_HOST}"
echo ""
kubectl get ingress -A | grep -E 'gitops|grafana|metrics' || kubectl get ingress -A
