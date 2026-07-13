#!/usr/bin/env bash
# Build enlight-console on OKE with BuildKit (Kaniko replacement).
set -euo pipefail

NS="${NS:-enlight-platform}"
TAG="${CONSOLE_TAG:-v41}"
IMAGE="ap-mumbai-1.ocir.io/bmitpaosivqx/enlight-console:${TAG}"
BUILDER="${CONSOLE_BUILDER:-docker.io/moby/buildkit:v0.20.2}"
GIT_REPO="${GIT_REPO:-https://github.com/kirtiprasadranasingh/Devops-localstack.git}"
# Use CONSOLE_GIT_BRANCH — not GIT_BRANCH (often set to main/master for pipeline runs)
BRANCH="${CONSOLE_GIT_BRANCH:-github-clean}"
JOB="enlight-console-build-${TAG//./-}"

echo "=========================================="
echo " BuildKit build console ${TAG} (OCIR only)"
echo " Branch: ${BRANCH}"
echo "=========================================="

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
          imagePullPolicy: IfNotPresent
          securityContext:
            privileged: true
          env:
            - name: DOCKER_CONFIG
              value: /root/.docker
          command:
            - /bin/sh
            - -c
            - |
              set -eu
              apk add --no-cache git bash >/dev/null
              echo "==> Clone ${BRANCH} from GitHub"
              rm -rf /work
              git clone --depth 1 -b ${BRANCH} ${GIT_REPO} /work
              BUILD_CTX=/work/console
              DOCKERFILE_NAME=Dockerfile.oke
              test -f "\${BUILD_CTX}/\${DOCKERFILE_NAME}" || DOCKERFILE_NAME=Dockerfile
              test -f "\${BUILD_CTX}/backend/requirements.txt"
              test -d "\${BUILD_CTX}/frontend/dist"
              test -f "\${BUILD_CTX}/frontend/dist/index.html"
              echo "==> Build context:"
              ls -la "\${BUILD_CTX}/"
              mkdir -p /run/buildkit /root/.docker
              cp /ocir/config.json /root/.docker/config.json
              echo "==> Start buildkitd"
              buildkitd --addr unix:///run/buildkit/buildkitd.sock >/tmp/buildkitd.log 2>&1 &
              for i in \$(seq 1 45); do
                buildctl --addr unix:///run/buildkit/buildkitd.sock debug workers >/dev/null 2>&1 && break
                sleep 1
              done
              echo "==> BuildKit build -> ${IMAGE} (\${DOCKERFILE_NAME})"
              buildctl --addr unix:///run/buildkit/buildkitd.sock build \\
                --frontend dockerfile.v0 \\
                --local context="\${BUILD_CTX}" \\
                --local dockerfile="\${BUILD_CTX}" \\
                --opt filename="\${DOCKERFILE_NAME}" \\
                --output type=image,name=${IMAGE},push=true
              echo "==> DONE ${IMAGE}"
          volumeMounts:
            - name: ocir-docker-config
              mountPath: /ocir
              readOnly: true
          resources:
            requests:
              cpu: 500m
              memory: 1Gi
            limits:
              cpu: 2000m
              memory: 3Gi
      volumes:
        - name: ocir-docker-config
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
