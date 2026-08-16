# Node runner: Node.js LTS + npm, pnpm, yarn.
# Build:  docker build -f images/node.Dockerfile -t gha-runner:node .
# Standalone builds use the public base; canonical publication overrides its exact digest.
ARG VERJSON_BASE_IMAGE=ghcr.io/verjson/gha-runner@sha256:d97a218b5c7834f1a34fc4e13760ad16b692504dc79c38f92a1a8bb3b286db85
FROM ${VERJSON_BASE_IMAGE}

USER root
RUN curl -fsSL https://deb.nodesource.com/setup_lts.x | bash - \
    && apt-get install -y --no-install-recommends nodejs \
    && npm install -g pnpm yarn \
    && rm -rf /var/lib/apt/lists/* \
    && node --version && npm --version

USER runner
