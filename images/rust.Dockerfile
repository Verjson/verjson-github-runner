# Rust runner: rustup toolchain + cargo + clippy + rustfmt, plus the usual native build deps.
# Build:  docker build -f images/rust.Dockerfile -t gha-runner:rust .
ARG BASE_IMAGE=gha-runner:base
FROM ${BASE_IMAGE}

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
