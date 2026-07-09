#!/bin/sh
# Enlight Lab OKE pipeline — runs inside a Kubernetes Job (triggered by Kestra).
set -eu

GIT_BRANCH="${GIT_BRANCH:-main}"
GIT_REPO="${GIT_REPO:-https://github.com/kirtiprasadranasingh/Devops-localstack.git}"
GITOPS_MANIFEST="${GITOPS_MANIFEST:-oke/gitops/apps/fastapi/deployment.yaml}"
OCIR_REGISTRY="${OCIR_REGISTRY:-ap-mumbai-1.ocir.io/bmitpaosivqx}"
OCIR_IMAGE_NAME="${OCIR_IMAGE_NAME:-enlight-fastapi}"
IMAGE_TAG="${IMAGE_TAG:-$(date +%Y%m%d-%H%M%S)}"

: "${GITHUB_TOKEN:?GITHUB_TOKEN required}"
: "${OCIR_USER:?OCIR_USER required}"
: "${OCIR_PASS:?OCIR_PASS required}"

apk add --no-cache curl bash git sed
curl -fsSL https://dl.dagger.io/dagger/install.sh | BIN_DIR=/usr/local/bin sh
pip install --no-cache-dir dagger-io

FULL_IMAGE="${OCIR_REGISTRY}/${OCIR_IMAGE_NAME}:${IMAGE_TAG}"
AUTH=$(printf '%s:%s' "$OCIR_USER" "$OCIR_PASS" | base64 | tr -d '\n')
mkdir -p /root/.docker
printf '{"auths":{"ap-mumbai-1.ocir.io":{"auth":"%s"}}}' "$AUTH" > /root/.docker/config.json

REPO_URL="${GIT_REPO#https://}"
git clone --depth 1 -b "$GIT_BRANCH" "https://x-access-token:${GITHUB_TOKEN}@${REPO_URL}" /work
cd /work/sample-app/fastapi-minimal/dagger
dagger call build-and-publish \
  --registry="${OCIR_REGISTRY}" \
  --image="${OCIR_IMAGE_NAME}" \
  --tag="${IMAGE_TAG}"

cd /work
git config user.email "kestra@enlightlab.com"
git config user.name "Kestra Enlight Lab"
sed -i "s|image:.*|image: ${FULL_IMAGE}|" "$GITOPS_MANIFEST"
git add "$GITOPS_MANIFEST"
git diff --cached --quiet || git commit -m "deploy: ${FULL_IMAGE} [kestra pipeline]"
git push origin "$GIT_BRANCH"
echo "DONE ${FULL_IMAGE}"
