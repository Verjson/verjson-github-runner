# Node runner: Node.js LTS + npm, pnpm, yarn.
# Build:  docker build -f images/node.Dockerfile -t gha-runner:node .
# Standalone builds use the public base; canonical publication overrides its exact digest.
ARG VERJSON_BASE_IMAGE=ghcr.io/verjson/gha-runner@sha256:3343542727e3bd7bef6918281b5c06ef3afacb1ae08cf1c5767cf8a9d3dcfa18
FROM ${VERJSON_BASE_IMAGE}

USER root
RUN curl -fsSL https://deb.nodesource.com/setup_lts.x | bash - \
    && apt-get install -y --no-install-recommends nodejs \
    && npm install -g pnpm yarn \
    && rm -rf /var/lib/apt/lists/* \
    && node --version && npm --version

USER runner
