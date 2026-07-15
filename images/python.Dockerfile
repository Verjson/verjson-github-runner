# Python runner: system Python 3 + pip/venv, plus the fast uv package manager.
# Build:  docker build -f images/python.Dockerfile -t gha-runner:python .
ARG BASE_IMAGE=gha-runner:base
FROM ${BASE_IMAGE}

USER root
RUN apt-get update && apt-get install -y --no-install-recommends \
      python3 python3-pip python3-venv python3-dev build-essential \
    && rm -rf /var/lib/apt/lists/*

USER runner
ENV PATH=/home/runner/.local/bin:${PATH}
RUN curl -LsSf https://astral.sh/uv/install.sh | sh \
    && python3 --version && uv --version
