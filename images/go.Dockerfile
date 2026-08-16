# Go runner: official Go toolchain installed under /usr/local/go.
# Build:  docker build -f images/go.Dockerfile -t gha-runner:go .
# Standalone builds use the public base; canonical publication overrides its exact digest.
ARG VERJSON_BASE_IMAGE=ghcr.io/verjson/gha-runner@sha256:d97a218b5c7834f1a34fc4e13760ad16b692504dc79c38f92a1a8bb3b286db85
FROM ${VERJSON_BASE_IMAGE}

ARG GO_VERSION=1.23.4
# TARGETARCH is provided by BuildKit (amd64 / arm64) and matches Go's download naming.
ARG TARGETARCH
USER root
RUN curl -fsSL "https://go.dev/dl/go${GO_VERSION}.linux-${TARGETARCH}.tar.gz" \
      | tar -C /usr/local -xz \
    && /usr/local/go/bin/go version
ENV PATH=/usr/local/go/bin:/home/runner/go/bin:${PATH} \
    GOPATH=/home/runner/go

USER runner
