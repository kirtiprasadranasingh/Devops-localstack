#!/usr/bin/env bash
# Morning demo finish — GitOps app + metrics ingress (~15 min if Grafana exists).
# Usage: bash oke/scripts/23-morning-demo-finish.sh
set -euo pipefail

INGRESS_HOST="${INGRESS_HOST:-144-24-100-85.nip.io}"

echo "=============================================="
echo " Enlight Lab — morning demo finish"
echo " $(date -u +%H:%M:%SZ)"
echo "=============================================="

echo ""
echo "==> 1/4 ArgoCD Application (enlight-demo-staging)"
kubectl apply -f - <<'EOF'
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: enlight-demo-staging
  namespace: argocd
  finalizers:
    - resources-finalizer.argocd.argoproj.io
spec:
  project: default
  source:
    repoURL: https://github.com/kirtiprasadranasingh/Devops-localstack.git
    targetRevision: main
    path: oke/gitops/apps/fastapi-staging
  destination:
    server: https://kubernetes.default.svc
    namespace: enlight-staging
  syncPolicy:
    automated:
      prune: false
      selfHeal: true
    syncOptions:
      - CreateNamespace=false
EOF

echo ""
echo "==> 2/4 Bootstrap ConfigMap (works even if Git not pushed yet)"
kubectl apply -f - <<'EOF'
apiVersion: v1
kind: ConfigMap
metadata:
  name: enlight-demo-info
  namespace: enlight-staging
  labels:
    app: fastapi
    managed-by: argocd
data:
  platform: enlight-lab
  demo_url: http://app.144-24-100-85.nip.io
  health_path: /health
  description: GitOps-managed demo metadata (safe — does not replace running FastAPI)
EOF

echo ""
echo "==> 3/4 Console env — GitOps link to shared ArgoCD"
kubectl set env deployment/enlight-console -n enlight-platform \
  GITOPS_PUBLIC_URL=https://argocd.enlightlab.com 2>/dev/null || true
kubectl rollout status deployment/enlight-console -n enlight-platform --timeout=120s 2>/dev/null || true

echo ""
echo "==> 4/4 Metrics ingress"
if kubectl get svc -n monitoring kube-prometheus-stack-grafana >/dev/null 2>&1; then
  kubectl apply -f - <<EOF
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: metrics-host
  namespace: monitoring
  annotations:
    nginx.ingress.kubernetes.io/ssl-redirect: "false"
spec:
  ingressClassName: nginx
  rules:
    - host: metrics.${INGRESS_HOST}
      http:
        paths:
          - path: /
            pathType: Prefix
            backend:
              service:
                name: kube-prometheus-stack-grafana
                port:
                  number: 80
EOF
  echo "Metrics: http://metrics.${INGRESS_HOST} (admin/admin)"
else
  echo "Grafana not installed — skip or run: bash oke/scripts/09-install-monitoring.sh ${INGRESS_HOST}"
fi

echo ""
echo "==> Quick health check"
for u in \
  "http://${INGRESS_HOST}" \
  "http://kestra.${INGRESS_HOST}" \
  "http://app.${INGRESS_HOST}" \
  "https://argocd.enlightlab.com" \
  "https://selfheal.enlightlab.com"; do
  code=$(curl -sk -o /dev/null -w "%{http_code}" "$u" 2>/dev/null || echo "ERR")
  echo "  $code  $u"
done
if kubectl get svc -n monitoring kube-prometheus-stack-grafana >/dev/null 2>&1; then
  code=$(curl -s -o /dev/null -w "%{http_code}" "http://metrics.${INGRESS_HOST}" 2>/dev/null || echo "ERR")
  echo "  $code  http://metrics.${INGRESS_HOST}"
fi

echo ""
echo "=============================================="
echo " DEMO CHECKLIST (10:45 meeting)"
echo "  1. http://${INGRESS_HOST}  → Run client demo"
echo "  2. http://kestra.${INGRESS_HOST}"
echo "  3. http://app.${INGRESS_HOST}"
echo "  4. https://argocd.enlightlab.com → enlight-demo-staging"
echo "  5. http://metrics.${INGRESS_HOST} (if installed)"
echo "  6. https://selfheal.enlightlab.com/staging"
echo "=============================================="
