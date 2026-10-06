# self-hosted GitHub Actions runner (Linux) for private repositories.
# Provides the tools the CI jobs use that a bare Ubuntu image lacks.
# Build: bash docker/actions-runner/setup.sh build
FROM ubuntu:24.04

ARG TARGETARCH
ARG RUNNER_VERSION=2.337.0
ARG SWIFTLINT_VERSION=0.65.1
ARG GITLEAKS_VERSION=8.30.1

ENV DEBIAN_FRONTEND=noninteractive \
    RUNNER_TOOL_CACHE=/runner/.cache/toolcache \
    AGENT_TOOLSDIRECTORY=/runner/.cache/toolcache \
    PIP_BREAK_SYSTEM_PACKAGES=1

# PIP_BREAK_SYSTEM_PACKAGES: Ubuntu 24.04 marks system python as externally managed (PEP 668),
# which makes `pip install` (e.g. pre-commit/action) fail for the non-root runner user.
# Tools used by the CI jobs: git/gh/curl/jq/zip, python (pre-commit hooks), node,
# shellcheck, and the shared libraries some Python tests load (libegl1 etc.).
RUN apt-get update \
 && apt-get install -y --no-install-recommends \
      ca-certificates curl git gnupg jq unzip zip perl build-essential \
      python3 python3-pip python3-venv nodejs npm shellcheck libegl1 libxkbcommon0 \
      libicu74 libssl3t64 \
 && curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg \
      -o /usr/share/keyrings/githubcli-archive-keyring.gpg \
 && echo "deb [arch=${TARGETARCH} signed-by=/usr/share/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" \
      > /etc/apt/sources.list.d/github-cli.list \
 && apt-get update && apt-get install -y --no-install-recommends gh \
 && rm -rf /var/lib/apt/lists/*

# uv, gitleaks, SwiftLint (Linux binary, so the lint job does not need docker)
RUN curl -LsSf https://astral.sh/uv/install.sh | env UV_INSTALL_DIR=/usr/local/bin UV_NO_MODIFY_PATH=1 sh \
 && case "${TARGETARCH}" in amd64) GL=x64; SL=amd64;; arm64) GL=arm64; SL=arm64;; *) echo "unsupported arch ${TARGETARCH}" >&2; exit 1;; esac \
 && curl -fsSL "https://github.com/gitleaks/gitleaks/releases/download/v${GITLEAKS_VERSION}/gitleaks_${GITLEAKS_VERSION}_linux_${GL}.tar.gz" \
      | tar -xz -C /usr/local/bin gitleaks \
 && curl -fsSL "https://github.com/realm/SwiftLint/releases/download/${SWIFTLINT_VERSION}/swiftlint_linux_${SL}.zip" -o /tmp/swiftlint.zip \
 && unzip -q /tmp/swiftlint.zip -d /tmp/swiftlint \
 && install -m 755 "$(find /tmp/swiftlint -type f -name swiftlint | head -1)" /usr/local/bin/swiftlint \
 && rm -rf /tmp/swiftlint /tmp/swiftlint.zip

# Runner binaries live in the image (/opt/runner); the entrypoint copies them into the
# volume-backed runner directory so registration state survives container re-creation.
RUN case "${TARGETARCH}" in amd64) RA=x64;; arm64) RA=arm64;; esac \
 && mkdir -p /opt/runner \
 && curl -fsSL "https://github.com/actions/runner/releases/download/v${RUNNER_VERSION}/actions-runner-linux-${RA}-${RUNNER_VERSION}.tar.gz" \
      | tar -xz -C /opt/runner \
 && echo "${RUNNER_VERSION}" > /opt/runner/.image-version

# Non-root user without sudo.
RUN useradd -m -d /runner -s /bin/bash runner \
 && mkdir -p /runner/actions-runner /runner/.cache \
 && chown -R runner:runner /runner

COPY entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod 755 /usr/local/bin/entrypoint.sh

USER runner
WORKDIR /runner/actions-runner
ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
