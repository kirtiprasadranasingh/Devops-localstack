# Enlight Lab pipeline runner — BuildKit in-cluster builds (Kaniko replacement).
# BuildKit is actively maintained (moby/buildkit); Google Kaniko is archived.
FROM moby/buildkit:v0.20.2

USER root
RUN apk add --no-cache bash git sed ca-certificates coreutils jq \
  && mkdir -p /pipeline /run/buildkit /root/.docker

WORKDIR /pipeline
COPY run.sh /pipeline/run.sh
RUN tr -d '\r' < /pipeline/run.sh > /tmp/run.sh \
    && mv /tmp/run.sh /pipeline/run.sh \
    && chmod +x /pipeline/run.sh \
    && head -1 /pipeline/run.sh | grep -q '#!/bin/bash'

ENV DOCKER_CONFIG="/root/.docker"
ENV BUILDKIT_HOST="unix:///run/buildkit/buildkitd.sock"
ENTRYPOINT ["/bin/bash", "/pipeline/run.sh"]
