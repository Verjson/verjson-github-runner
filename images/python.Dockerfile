# Python runner: system Python 3 + pip/venv, plus the fast uv package manager.
# Build:  docker build -f images/python.Dockerfile -t gha-runner:python .
# Standalone builds use the public base; canonical publication overrides its exact digest.
ARG VERJSON_BASE_IMAGE=ghcr.io/verjson/gha-runner@sha256:d1a77bc538ffd3b07f02c7495e28ca11ce020ad676063ab660b420afb1f4b23b
FROM ${VERJSON_BASE_IMAGE}

USER root
RUN apt-get update && apt-get install -y --no-install-recommends \
      python3 python3-pip python3-venv python3-dev build-essential \
    && rm -rf /var/lib/apt/lists/*

USER runner
ENV PATH=/home/runner/.local/bin:${PATH}
RUN curl -LsSf https://astral.sh/uv/install.sh | sh \
  && python3 --version && uv --version
RUN ["/usr/local/bin/bubblewrap-image-contract"]
