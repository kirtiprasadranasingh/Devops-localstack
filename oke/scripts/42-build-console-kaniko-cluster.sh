#!/usr/bin/env bash
# Build enlight-console on OKE with Kaniko (amd64) — works from ARM Cloud Shell.
# No cross-compile on Cloud Shell; Kaniko runs on cluster x86 nodes.
set -euo pipefail

NS="${NS:-enlight-platform}"
TAG="${CONSOLE_TAG:-v22}"
IMAGE="ap-mumbai-1.ocir.io/bmitpaosivqx/enlight-console:${TAG}"
GIT_REPO="${GIT_REPO:-https://github.com/kirtiprasadranasingh/Devops-localstack.git}"
GIT_BRANCH="${GIT_BRANCH:-github-clean}"
JOB="enlight-console-build-${TAG//./-}"

echo "=========================================="
echo " Kaniko build console ${TAG} in-cluster"
echo "=========================================="

kubectl apply -f - <<EOF
apiVersion: batch/v1
kind: Job
metadata:
  name: ${JOB}
  namespace: ${NS}
spec:
  backoffLimit: 0
  ttlSecondsAfterFinished: 1800
  template:
    spec:
      serviceAccountName: kestra-runner
      restartPolicy: Never
      imagePullSecrets:
        - name: ocir-pull-secret
      initContainers:
        - name: git-clone
          image: alpine/git:latest
          command:
            - /bin/sh
            - -c
            - |
              set -e
              git clone --depth 1 -b ${GIT_BRANCH} ${GIT_REPO} /workspace
              ls -la /workspace/console/
          volumeMounts:
            - name: src
              mountPath: /workspace
      containers:
        - name: kaniko
          image: gcr.io/kaniko-project/executor:v1.23.2
          args:
            - --dockerfile=/workspace/console/Dockerfile
            - --context=/workspace/console
            - --destination=${IMAGE}
            - --cache=false
            - --single-snapshot
          env:
            - name: DOCKER_CONFIG
              value: /kaniko/.docker
          volumeMounts:
            - name: src
              mountPath: /workspace
            - name: docker-config
              mountPath: /kaniko/.docker
              readOnly: true
      volumes:
        - name: src
          emptyDir: {}
        - name: docker-config
          secret:
            secretName: ocir-pull-secret
            items:
              - key: .dockerconfigjson
                path: config.json
EOF

echo "==> Waiting for Kaniko job (up to 15 min)..."
kubectl wait --for=condition=complete "job/${JOB}" -n "${NS}" --timeout=900s || {
  echo "Job failed — logs:"
  kubectl logs -n "${NS}" "job/${JOB}" -c kaniko --tail=40 2>/dev/null || true
  kubectl logs -n "${NS}" "job/${JOB}" -c git-clone --tail=20 2>/dev/null || true
  exit 1
}

echo "==> Build OK: ${IMAGE}"
CONSOLE_IMAGE="${IMAGE}" bash "$(dirname "$0")/40-deploy-console-safe.sh"
