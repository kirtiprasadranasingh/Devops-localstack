#!/usr/bin/env bash
# Build enlight-console on OKE using enlight-pipeline image (git + kaniko, OCIR only).
set -euo pipefail

NS="${NS:-enlight-platform}"
TAG="${CONSOLE_TAG:-v22}"
IMAGE="ap-mumbai-1.ocir.io/bmitpaosivqx/enlight-console:${TAG}"
BUILDER="ap-mumbai-1.ocir.io/bmitpaosivqx/enlight-pipeline:v9"
GIT_REPO="${GIT_REPO:-https://github.com/kirtiprasadranasingh/Devops-localstack.git}"
GIT_BRANCH="${GIT_BRANCH:-github-clean}"
JOB="enlight-console-build-${TAG//./-}"

echo "=========================================="
echo " Kaniko build console ${TAG} (OCIR only)"
echo "=========================================="

# Remove previous failed job if any
kubectl delete job "${JOB}" -n "${NS}" --ignore-not-found=true
sleep 2

kubectl apply -f - <<EOF
apiVersion: batch/v1
kind: Job
metadata:
  name: ${JOB}
  namespace: ${NS}
spec:
  backoffLimit: 0
  ttlSecondsAfterFinished: 1800
  activeDeadlineSeconds: 2400
  template:
    spec:
      serviceAccountName: kestra-runner
      restartPolicy: Never
      imagePullSecrets:
        - name: ocir-pull-secret
      containers:
        - name: build
          image: ${BUILDER}
          imagePullPolicy: Always
          command:
            - /bin/bash
            - -c
            - |
              set -euo pipefail
              echo "==> Clone ${GIT_BRANCH} from GitHub"
              git clone --depth 1 -b ${GIT_BRANCH} ${GIT_REPO} /workspace
              test -f /workspace/console/Dockerfile
              ls -la /workspace/console/
              echo "==> Kaniko build -> ${IMAGE}"
              export DOCKER_CONFIG=/kaniko/.docker
              /kaniko/executor \
                --dockerfile=/workspace/console/Dockerfile \
                --context=/workspace/console \
                --destination=${IMAGE} \
                --cache=false \
                --snapshot-mode=redo
              echo "==> DONE ${IMAGE}"
          volumeMounts:
            - name: docker-config
              mountPath: /kaniko/.docker
              readOnly: true
          resources:
            requests:
              cpu: 500m
              memory: 1Gi
            limits:
              cpu: 2000m
              memory: 3Gi
      volumes:
        - name: docker-config
          secret:
            secretName: ocir-pull-secret
            items:
              - key: .dockerconfigjson
                path: config.json
EOF

echo "==> Waiting for build job (up to 20 min)..."
kubectl wait --for=condition=complete "job/${JOB}" -n "${NS}" --timeout=1200s || {
  echo "Job failed — logs:"
  kubectl logs -n "${NS}" "job/${JOB}" -c build --tail=60 2>/dev/null || true
  kubectl describe pod -n "${NS}" -l job-name="${JOB}" | tail -25
  exit 1
}

echo "==> Build OK: ${IMAGE}"
CONSOLE_IMAGE="${IMAGE}" bash "$(dirname "$0")/40-deploy-console-safe.sh"
