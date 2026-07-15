FROM ubuntu:24.04

ARG RUNNER_VERSION=2.335.1
ENV DEBIAN_FRONTEND=noninteractive

# Base tools (git/curl/jq for token fetch; the runner needs libicu etc. via installdependencies.sh)
RUN apt-get update && apt-get install -y --no-install-recommends \
      ca-certificates curl jq git sudo tar gzip \
    && rm -rf /var/lib/apt/lists/*

# The runner refuses to run as root -> dedicated user
RUN useradd -m -s /bin/bash runner \
    && echo "runner ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/runner

WORKDIR /home/runner/actions-runner

# TARGETARCH is set automatically by BuildKit (amd64 on x64, arm64 on Apple Silicon / ARM).
# This makes the image build & run natively on both, no emulation.
ARG TARGETARCH
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
