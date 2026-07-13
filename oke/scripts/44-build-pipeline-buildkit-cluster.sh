#!/usr/bin/env bash
# Build enlight-pipeline:v10 (BuildKit) on OKE and update Kestra flow default.
# Uses a privileged BuildKit Job (no local Docker required on Cloud Shell).
set -euo pipefail

NS="${NS:-enlight-platform}"
TAG="${PIPELINE_TAG:-v10}"
IMAGE="ap-mumbai-1.ocir.io/bmitpaosivqx/enlight-pipeline:${TAG}"
GIT_REPO="${GIT_REPO:-https://github.com/kirtiprasadranasingh/Devops-localstack.git}"
BRANCH="${PIPELINE_GIT_BRANCH:-github-clean}"
JOB="enlight-pipeline-build-${TAG//./-}"
BUILDER="docker.io/moby/buildkit:v0.20.2"

echo "=========================================="
echo " Build pipeline image ${TAG} (BuildKit)"
echo " Branch: ${BRANCH}"
echo " Image:  ${IMAGE}"
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
              echo "==> Clone ${BRANCH}"
              rm -rf /work
              git clone --depth 1 -b "${BRANCH}" "${GIT_REPO}" /work
              CTX=/work/oke/pipeline-runner
              test -f "\${CTX}/Dockerfile"
              test -f "\${CTX}/run.sh"
              mkdir -p /run/buildkit /root/.docker
              cp /ocir/config.json /root/.docker/config.json
              echo "==> Start buildkitd"
              buildkitd --addr unix:///run/buildkit/buildkitd.sock >/tmp/buildkitd.log 2>&1 &
              for i in \$(seq 1 45); do
                buildctl --addr unix:///run/buildkit/buildkitd.sock debug workers >/dev/null 2>&1 && break
                sleep 1
              done
              echo "==> Build & push ${IMAGE}"
              buildctl --addr unix:///run/buildkit/buildkitd.sock build \\
                --frontend dockerfile.v0 \\
                --local context="\${CTX}" \\
                --local dockerfile="\${CTX}" \\
                --opt filename=Dockerfile \\
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
  kubectl logs -n "${NS}" "job/${JOB}" -c build --tail=80 2>/dev/null || true
  kubectl describe pod -n "${NS}" -l job-name="${JOB}" | tail -30
  exit 1
}

echo "==> Build OK: ${IMAGE}"
echo ""
echo "Next:"
echo "  1) Re-import Kestra flow (defaults now point at ${IMAGE})"
echo "  2) Or trigger deploy with input pipeline_image=${IMAGE}"
echo "  3) Console: set PIPELINE_IMAGE=${IMAGE} on enlight-console"
