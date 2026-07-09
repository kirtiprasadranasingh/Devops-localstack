#!/usr/bin/env bash
# Fix argocd.enlightlab.com — same TLS pattern as selfheal (does NOT touch selfheal).
#
# Usage:
#   bash oke/scripts/21-fix-argocd-enlightlab-tls.sh
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
OKE_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
HOST=argocd.enlightlab.com
ARGOCD_PASS="${ARGOCD_PASSWORD:-EnlightDemo2026!}"

echo "=============================================="
echo " Fix ${HOST} (selfheal-safe)"
echo "=============================================="

# --- Discover TLS secret from working enlightlab ingress (selfheal / portal) ---
TLS_SECRET=""
TLS_NS=""
for ing in "selfheal/selfheal-ui-ingress" "enlight-staging/nginx-demo" "enlightlab-portal/portal-cicd-ingress"; do
  NS="${ing%%/*}"
  NAME="${ing##*/}"
  SEC=$(kubectl get ingress "$NAME" -n "$NS" -o jsonpath='{.spec.tls[0].secretName}' 2>/dev/null || true)
  if [[ -n "$SEC" ]]; then
    TLS_SECRET="$SEC"
    TLS_NS="$NS"
    echo "Found TLS secret: ${TLS_SECRET} (from ${NS}/${NAME})"
    break
  fi
done

if [[ -z "$TLS_SECRET" ]]; then
  echo "WARN: No TLS secret found on selfheal/portal ingress — HTTP only"
fi

# --- Ensure ArgoCD exists ---
if ! kubectl get namespace argocd >/dev/null 2>&1; then
  echo "==> Creating argocd namespace + install"
  kubectl create namespace argocd
  kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml
fi

echo "==> Wait for argocd-server"
kubectl rollout status deployment/argocd-server -n argocd --timeout=600s

echo "==> ArgoCD HTTP behind ingress (TLS terminated at nginx)"
kubectl patch svc argocd-server -n argocd -p '{"spec":{"type":"ClusterIP"}}' 2>/dev/null || true
kubectl patch configmap argocd-cmd-params-cm -n argocd --type merge -p \
  '{"data":{"server.rootpath":"","server.insecure":"true"}}'
kubectl rollout restart deployment/argocd-server -n argocd
kubectl rollout status deployment/argocd-server -n argocd --timeout=300s

# --- Copy TLS secret to argocd ns if needed ---
if [[ -n "$TLS_SECRET" ]]; then
  if ! kubectl get secret "$TLS_SECRET" -n argocd >/dev/null 2>&1; then
  echo "==> Copy TLS secret ${TLS_SECRET} into argocd namespace"
  kubectl get secret "$TLS_SECRET" -n "$TLS_NS" -o yaml | \
    sed "s/namespace: ${TLS_NS}/namespace: argocd/" | \
    kubectl apply -f - || \
    kubectl get secret "$TLS_SECRET" -n "$TLS_NS" -o json | \
      python3 -c "import json,sys; s=json.load(sys.stdin); s['metadata']={'name':'${TLS_SECRET}','namespace':'argocd'}; del s['metadata']['creationTimestamp'],s['metadata']['resourceVersion'],s['metadata']['uid']; json.dump(s,sys.stdout)" | \
      kubectl apply -f -
  fi
fi

# --- Build ingress YAML ---
INGRESS_FILE="/tmp/argocd-enlightlab-ingress.yaml"
cat > "$INGRESS_FILE" <<EOF
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: argocd-enlightlab
  namespace: argocd
  annotations:
    nginx.ingress.kubernetes.io/backend-protocol: HTTP
    nginx.ingress.kubernetes.io/ssl-redirect: "true"
    nginx.ingress.kubernetes.io/force-ssl-redirect: "true"
spec:
  ingressClassName: nginx
  rules:
    - host: ${HOST}
      http:
        paths:
          - path: /
            pathType: Prefix
            backend:
              service:
                name: argocd-server
                port:
                  number: 80
EOF

if [[ -n "$TLS_SECRET" ]]; then
  cat >> "$INGRESS_FILE" <<EOF
  tls:
    - hosts:
        - ${HOST}
      secretName: ${TLS_SECRET}
EOF
fi

echo "==> Apply ingress"
kubectl apply -f "$INGRESS_FILE"

# --- Set known admin password ---
echo "==> Set admin password"
HASH=$(kubectl run "argocd-bcrypt-$$" --rm -i --restart=Never -n argocd \
  --image=quay.io/argoproj/argocd:v2.13.2 \
  --env="PASS=${ARGOCD_PASS}" \
  --command -- sh -c 'printf "%s" "$PASS" | argocd account bcrypt' 2>/dev/null | tail -1 || true)
if [[ -n "$HASH" && "$HASH" == \$2* ]]; then
  python3 -c "import json; json.dump({'stringData':{'admin.password':'${HASH}','admin.passwordMtime':'$(date -u +%Y-%m-%dT%H:%M:%SZ)'}}, open('/tmp/p.json','w'))"
  kubectl patch secret argocd-secret -n argocd --type merge --patch-file /tmp/p.json
  kubectl rollout restart deployment/argocd-server -n argocd
  kubectl rollout status deployment/argocd-server -n argocd --timeout=300s
else
  echo "WARN: bcrypt failed — run oke/scripts/22-argocd-password-deep-fix.sh"
fi

echo ""
echo "==> Verify (does NOT touch selfheal)"
curl -sI "https://${HOST}" 2>/dev/null | head -5 || curl -sI "http://${HOST}" | head -5
curl -sI "https://selfheal.enlightlab.com" 2>/dev/null | head -3 || true

echo ""
echo "=============================================="
echo " ${HOST}"
echo "   https://${HOST}"
echo "   user: admin"
echo "   pass: ${ARGOCD_PASS}  (or existing if patch skipped)"
echo ""
echo " selfheal unchanged: https://selfheal.enlightlab.com"
echo "=============================================="
