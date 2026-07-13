#!/bin/bash
# Enlight Lab OKE pipeline — BuildKit build (Kaniko replacement).
set -e

GIT_BRANCH="${GIT_BRANCH:-main}"
GIT_REPO="${GIT_REPO:-https://github.com/kirtiprasadranasingh/Devops-localstack.git}"
GITOPS_MANIFEST="${GITOPS_MANIFEST:-oke/gitops/apps/fastapi/deployment.yaml}"
OCIR_REGISTRY="${OCIR_REGISTRY:-ap-mumbai-1.ocir.io/bmitpaosivqx}"
OCIR_IMAGE_NAME="${OCIR_IMAGE_NAME:-enlight-fastapi}"
BUILDKIT_ADDR="${BUILDKIT_HOST:-unix:///run/buildkit/buildkitd.sock}"

case "${IMAGE_TAG:-}" in
  ""|null|NULL) IMAGE_TAG="$(date +%Y%m%d-%H%M%S)" ;;
esac

FULL_IMAGE="${OCIR_REGISTRY}/${OCIR_IMAGE_NAME}:${IMAGE_TAG}"
REPO_URL="${GIT_REPO#https://}"

echo "==> Enlight pipeline starting (BuildKit)"
echo "    branch=${GIT_BRANCH} repo=${GIT_REPO}"
echo "    image=${FULL_IMAGE}"

if [ -z "${GITHUB_TOKEN:-}" ]; then
  echo "ERROR: GITHUB_TOKEN is empty — run oke/scripts/17-kestra-secrets-oss.sh"
  exit 1
fi

export DOCKER_CONFIG="${DOCKER_CONFIG:-/root/.docker}"
mkdir -p "${DOCKER_CONFIG}" /run/buildkit

if [ -f "${DOCKER_CONFIG}/config.json" ]; then
  echo "==> Using mounted OCIR credentials (${DOCKER_CONFIG}/config.json)"
elif [ -n "${OCIR_USER:-}" ] && [ -n "${OCIR_PASS:-}" ]; then
  OCIR_HOST="${FULL_IMAGE%%/*}"
  AUTH=$(printf '%s:%s' "$OCIR_USER" "$OCIR_PASS" | base64 | tr -d '\n')
  jq -n \
    --arg user "$OCIR_USER" \
    --arg pass "$OCIR_PASS" \
    --arg auth "$AUTH" \
    --arg host "$OCIR_HOST" \
    --arg https "https://${OCIR_HOST}" \
    '{auths: {
      ($host): {"username": $user, "password": $pass, "auth": $auth},
      ($https): {"username": $user, "password": $pass, "auth": $auth}
    }}' > "${DOCKER_CONFIG}/config.json"
  echo "==> Wrote OCIR docker config for ${OCIR_HOST}"
else
  echo "ERROR: No OCIR credentials — mount ocir-pull-secret or set Kestra secrets"
  exit 1
fi

echo "==> Start BuildKit daemon"
buildkitd --addr "${BUILDKIT_ADDR}" >/tmp/buildkitd.log 2>&1 &
BUILDKITD_PID=$!
cleanup() {
  kill "${BUILDKITD_PID}" 2>/dev/null || true
}
trap cleanup EXIT

for i in $(seq 1 45); do
  if buildctl --addr "${BUILDKIT_ADDR}" debug workers >/dev/null 2>&1; then
    echo "    buildkitd ready (${i}s)"
    break
  fi
  if ! kill -0 "${BUILDKITD_PID}" 2>/dev/null; then
    echo "ERROR: buildkitd exited early — log:"
    cat /tmp/buildkitd.log || true
    exit 1
  fi
  sleep 1
  if [ "$i" -eq 45 ]; then
    echo "ERROR: buildkitd did not become ready — log:"
    cat /tmp/buildkitd.log || true
    exit 1
  fi
done

echo "==> Clone GitHub"
rm -rf /work
git clone --depth 1 -b "$GIT_BRANCH" "https://x-access-token:${GITHUB_TOKEN}@${REPO_URL}" /work

BUILD_CTX="/work/sample-app/fastapi-minimal"
if [ ! -f "${BUILD_CTX}/Dockerfile" ]; then
  echo "ERROR: ${BUILD_CTX}/Dockerfile not found in cloned repo"
  ls -la /work/sample-app 2>/dev/null || ls -la /work
  exit 1
fi

echo "==> GitOps commit BEFORE build (image tag is pre-defined: ${IMAGE_TAG})"
cd /work
git config user.email "kestra@enlightlab.com"
git config user.name "Kestra Enlight Lab"
sed -i "s|image:.*|image: ${FULL_IMAGE}|" "$GITOPS_MANIFEST"
git add "$GITOPS_MANIFEST"
if git diff --cached --quiet; then
  echo "GitOps manifest unchanged"
else
  git commit -m "deploy: ${FULL_IMAGE} [kestra pipeline]"
  git push "https://x-access-token:${GITHUB_TOKEN}@${REPO_URL}" HEAD:"${GIT_BRANCH}"
fi

echo "==> BuildKit build ${FULL_IMAGE}"
buildctl --addr "${BUILDKIT_ADDR}" build \
  --frontend dockerfile.v0 \
  --local context="${BUILD_CTX}" \
  --local dockerfile="${BUILD_CTX}" \
  --opt filename=Dockerfile \
  --output "type=image,name=${FULL_IMAGE},push=true"

echo "DONE ${FULL_IMAGE}"
