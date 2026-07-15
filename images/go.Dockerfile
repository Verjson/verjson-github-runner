# Go runner: official Go toolchain installed under /usr/local/go.
# Build:  docker build -f images/go.Dockerfile -t gha-runner:go .
ARG BASE_IMAGE=gha-runner:base
FROM ${BASE_IMAGE}

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
