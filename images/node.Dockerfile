# Node runner: Node.js LTS + npm, pnpm, yarn.
# Build:  docker build -f images/node.Dockerfile -t gha-runner:node .
ARG BASE_IMAGE=gha-runner:base
FROM ${BASE_IMAGE}

USER root
RUN curl -fsSL https://deb.nodesource.com/setup_lts.x | bash - \
    && apt-get install -y --no-install-recommends nodejs \
    && npm install -g pnpm yarn \
    && rm -rf /var/lib/apt/lists/* \
    && node --version && npm --version

USER runner
