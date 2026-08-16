# Rust runner: rustup toolchain + cargo + clippy + rustfmt, plus the usual native build deps.
# Build:  docker build -f images/rust.Dockerfile -t gha-runner:rust .
# Standalone builds use the public base; canonical publication overrides its exact digest.
ARG VERJSON_BASE_IMAGE=ghcr.io/verjson/gha-runner@sha256:d97a218b5c7834f1a34fc4e13760ad16b692504dc79c38f92a1a8bb3b286db85
FROM ${VERJSON_BASE_IMAGE}

USER root
RUN apt-get update && apt-get install -y --no-install-recommends \
      build-essential pkg-config libssl-dev \
    && rm -rf /var/lib/apt/lists/*

USER runner
ENV RUSTUP_HOME=/home/runner/.rustup \
    CARGO_HOME=/home/runner/.cargo \
    PATH=/home/runner/.cargo/bin:${PATH}
RUN curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs \
      | sh -s -- -y --profile minimal -c clippy -c rustfmt \
    && rustc --version && cargo --version
