# Toolbox image for the takehome harness.
# Contains: k3d (cluster provisioning), kubectl, helm, terraform, k6, git, curl, jq
# Multi-arch: resolves arch from the standard ARG TARGETARCH build arg.
FROM debian:bookworm-slim AS base

ARG TARGETARCH
ARG KUBECTL_VERSION=stable
ARG HELM_VERSION=v3.16.4
ARG K3D_VERSION=v5.9.0
ARG TERRAFORM_VERSION=1.9.8
ARG K6_VERSION=v0.54.0

RUN apt-get update && apt-get install -y --no-install-recommends \
      ca-certificates curl git jq bash-completion unzip \
    && rm -rf /var/lib/apt/lists/*

# docker CLI (build/push from inside the container; daemon = host docker.sock)
RUN case "$TARGETARCH" in \
      arm64)  ARCH_DOCKER=aarch64 ;; \
      *)      ARCH_DOCKER=x86_64 ;; \
    esac \
    && curl -fsSL "https://download.docker.com/linux/static/stable/${ARCH_DOCKER}/docker-27.5.1.tgz" \
      | tar xz -C /tmp --strip-components 1 docker/docker \
    && install -m 0755 /tmp/docker /usr/local/bin/docker

# kubectl (latest stable, resolved via stable.txt)
RUN KUBECTL_STABLE=$(curl -fsSL "https://dl.k8s.io/release/stable.txt") \
    && curl -fsSL "https://dl.k8s.io/release/${KUBECTL_STABLE}/bin/linux/${TARGETARCH}/kubectl" \
      -o /usr/local/bin/kubectl && chmod +x /usr/local/bin/kubectl

# helm
RUN curl -fsSL "https://get.helm.sh/helm-${HELM_VERSION}-linux-${TARGETARCH}.tar.gz" \
      | tar xz -C /tmp && install -m 0755 /tmp/linux-${TARGETARCH}/helm /usr/local/bin/helm

# k3d
RUN curl -fsSL "https://github.com/k3d-io/k3d/releases/download/${K3D_VERSION}/k3d-linux-${TARGETARCH}" \
      -o /usr/local/bin/k3d && chmod +x /usr/local/bin/k3d

# terraform
RUN curl -fsSL "https://releases.hashicorp.com/terraform/${TERRAFORM_VERSION}/terraform_${TERRAFORM_VERSION}_linux_${TARGETARCH}.zip" \
      -o /tmp/tf.zip && unzip -o /tmp/tf.zip -d /usr/local/bin && chmod +x /usr/local/bin/terraform

# k6
RUN curl -fsSL "https://github.com/grafana/k6/releases/download/${K6_VERSION}/k6-${K6_VERSION}-linux-${TARGETARCH}.tar.gz" \
      | tar xz -C /tmp && install -m 0755 /tmp/k6-${K6_VERSION}-linux-${TARGETARCH}/k6 /usr/local/bin/k6

# non-root user (also fine to run as root for docker-sock work; we use root to keep scripture simple)
ENV HOME=/root
WORKDIR /work
CMD ["/bin/bash"]
