# Node runner: Node.js LTS + npm, pnpm, yarn.
# Build:  docker build -f images/node.Dockerfile -t gha-runner:node .
# Standalone builds use the public base; canonical publication overrides its exact digest.
ARG VERJSON_BASE_IMAGE=ghcr.io/verjson/gha-runner@sha256:74f1733a7a90a4798b29632881449800b30e47e9abaa8bcd049a94f5c483ed8e
FROM ${VERJSON_BASE_IMAGE}

# The base image carries the pin descriptor it was built from; copy this checkout's in
# so a variant bootstraps the exact per-architecture version this source tree pins.
COPY --chmod=0444 images/bubblewrap-provenance.json /usr/local/share/verjson-bubblewrap-pin.json
COPY --chmod=0555 scripts/ensure-bubblewrap.sh /usr/local/bin/ensure-bubblewrap
COPY --chmod=0555 scripts/install-bubblewrap.sh /usr/local/bin/install-bubblewrap
USER root
RUN ["/usr/local/bin/ensure-bubblewrap"]
RUN rm -f /usr/local/bin/ensure-bubblewrap /usr/local/bin/install-bubblewrap \
      /usr/local/share/verjson-bubblewrap-pin.json

RUN curl -fsSL https://deb.nodesource.com/setup_lts.x | bash - \
    && apt-get install -y --no-install-recommends nodejs \
    && node "$(command -v npm)" install -g pnpm yarn \
    && rm -rf /var/lib/apt/lists/* \
    && node --version && node "$(command -v npm)" --version

COPY --chmod=0444 images/bubblewrap-provenance.json /etc/verjson-bubblewrap-provenance.json
COPY --chmod=0555 scripts/bubblewrap-image-contract.py /usr/local/bin/bubblewrap-image-contract
USER runner
RUN ["/usr/local/bin/bubblewrap-image-contract"]
