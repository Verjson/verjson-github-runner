# Node runner: Node.js LTS + npm, pnpm, yarn.
# Build:  docker build -f images/node.Dockerfile -t gha-runner:node .
# Standalone builds use the public base; canonical publication overrides its exact digest.
ARG VERJSON_BASE_IMAGE=ghcr.io/verjson/gha-runner@sha256:d1a77bc538ffd3b07f02c7495e28ca11ce020ad676063ab660b420afb1f4b23b
FROM ${VERJSON_BASE_IMAGE}

USER root
RUN curl -fsSL https://deb.nodesource.com/setup_lts.x | bash - \
    && apt-get install -y --no-install-recommends nodejs \
    && npm install -g pnpm yarn \
    && rm -rf /var/lib/apt/lists/* \
    && node --version && npm --version

USER runner
