# Base GitHub Actions self-hosted runner image.
# Every language "kind" (rust/node/python/go) builds FROM this via images/<kind>.Dockerfile.
# Build from the repo root so entrypoint.sh is in the build context:
#   docker build -f images/base.Dockerfile -t gha-runner:base .
FROM ubuntu:24.04

ARG RUNNER_VERSION=2.335.1
ARG GH_VERSION=2.96.0
ARG GH_SHA256_AMD64=83d5c2ccad5498f58bf6368acb1ab32588cf43ab3a4b1c301bf36328b1c8bd60
ARG GH_SHA256_ARM64=06f86ec7103d41993b76cd78072f43595c34aaa56506d971d9860e67140bf909
ARG NODE_VERSION=24.18.0
ARG NODE_SHA256_AMD64=55aa7153f9d88f28d765fcdad5ae6945b5c0f98a36881703817e4c450fa76742
ARG NODE_SHA256_ARM64=58c9520501f6ae2b52d5b210444e24b9d0c029a58c5011b797bc1fe7105886f6
ARG TARGETARCH
ENV DEBIAN_FRONTEND=noninteractive

# Install every standard utility exercised by the portable ci admission contract.
RUN apt-get update && apt-get install -y --no-install-recommends \
      bash ca-certificates coreutils curl findutils gawk git grep gzip jq sed \
      sudo tar util-linux xz-utils \
    && rm -rf /var/lib/apt/lists/*

# GitHub CLI release archives are pinned and verified against GitHub's published checksums.
RUN case "${TARGETARCH}" in \
      amd64) GH_SHA256="${GH_SHA256_AMD64}" ;; \
      arm64) GH_SHA256="${GH_SHA256_ARM64}" ;; \
      *) echo "Unsupported architecture: ${TARGETARCH}" >&2; exit 1 ;; \
    esac; \
    GH_ARCHIVE="gh_${GH_VERSION}_linux_${TARGETARCH}.tar.gz"; \
    curl -fsSL -o "/tmp/${GH_ARCHIVE}" \
      "https://github.com/cli/cli/releases/download/v${GH_VERSION}/${GH_ARCHIVE}"; \
    echo "${GH_SHA256}  /tmp/${GH_ARCHIVE}" | sha256sum -c -; \
    tar -xzf "/tmp/${GH_ARCHIVE}" -C /tmp; \
    install -m 0755 "/tmp/gh_${GH_VERSION}_linux_${TARGETARCH}/bin/gh" /usr/local/bin/gh; \
    rm -rf "/tmp/${GH_ARCHIVE}" "/tmp/gh_${GH_VERSION}_linux_${TARGETARCH}"

# Node.js 24 includes npm. Pin and verify official archives instead of using the
# distro-default Node.js major, which is not the shared ci contract.
RUN case "${TARGETARCH}" in \
      amd64) NODE_ARCH=x64; NODE_SHA256="${NODE_SHA256_AMD64}" ;; \
      arm64) NODE_ARCH=arm64; NODE_SHA256="${NODE_SHA256_ARM64}" ;; \
      *) echo "Unsupported architecture: ${TARGETARCH}" >&2; exit 1 ;; \
    esac; \
    NODE_ARCHIVE="node-v${NODE_VERSION}-linux-${NODE_ARCH}.tar.xz"; \
    curl -fsSL -o "/tmp/${NODE_ARCHIVE}" \
      "https://nodejs.org/dist/v${NODE_VERSION}/${NODE_ARCHIVE}"; \
    echo "${NODE_SHA256}  /tmp/${NODE_ARCHIVE}" | sha256sum -c -; \
    tar -xJf "/tmp/${NODE_ARCHIVE}" -C /usr/local --strip-components=1; \
    rm -f "/tmp/${NODE_ARCHIVE}"; \
    node --version; \
    npm --version

# Docker CLI + buildx + compose plugins, so runners can run `docker build --secret`
# (needs BuildKit/buildx) and `docker compose` against the mounted host socket.
# The daemon stays the host's (dockerx MountSock -> /var/run/docker.sock) — only the
# client and its plugins live in the image, which every kind inherits from base.
RUN install -m 0755 -d /etc/apt/keyrings \
    && curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc \
    && chmod a+r /etc/apt/keyrings/docker.asc \
    && echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu $(. /etc/os-release && echo "$VERSION_CODENAME") stable" \
         > /etc/apt/sources.list.d/docker.list \
    && apt-get update \
    && apt-get install -y --no-install-recommends \
         docker-ce-cli docker-buildx-plugin docker-compose-plugin \
    && rm -rf /var/lib/apt/lists/*

# The runner refuses to run as root -> dedicated user
RUN useradd -m -s /bin/bash runner \
    && echo "runner ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/runner

WORKDIR /home/runner/actions-runner

# TARGETARCH is set automatically by BuildKit (amd64 on x64, arm64 on Apple Silicon / ARM).
# This makes the image build & run natively on both, no emulation.
RUN case "${TARGETARCH}" in \
      amd64) RUNNER_ARCH=x64 ;; \
      arm64) RUNNER_ARCH=arm64 ;; \
      *) echo "Unsupported architecture: ${TARGETARCH}" >&2; exit 1 ;; \
    esac; \
    curl -fsSL -o runner.tar.gz \
      "https://github.com/actions/runner/releases/download/v${RUNNER_VERSION}/actions-runner-linux-${RUNNER_ARCH}-${RUNNER_VERSION}.tar.gz" \
    && tar xzf runner.tar.gz && rm runner.tar.gz \
    && ./bin/installdependencies.sh \
    && chown -R runner:runner /home/runner

COPY --chmod=755 entrypoint.sh /entrypoint.sh

USER runner
ENTRYPOINT ["/entrypoint.sh"]
