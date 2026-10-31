# Workspace image for the shared Coder template: Docker Engine, Rust, Node, bun, Playwright with
# a headless Chromium, Claude Code, the Infisical CLI, and the GitHub CLI.
#
# Everything is installed OUTSIDE the user's home, because the workspace's home volume is mounted
# over that directory at runtime and would hide anything put there at build time.
FROM ubuntu:24.04

# The workspace owner's Coder username, passed in by main.tf.
ARG USER=coder
ARG RUST_VERSION=1.99.1
ARG NODE_MAJOR=24
# playwright is pinned to the build @playwright/mcp bundles, so both use the one Chromium;
# bump them together.
ARG PLAYWRIGHT_VERSION=1.64.0-alpha-1790635538000
ARG PLAYWRIGHT_MCP_VERSION=0.0.83

ENV DEBIAN_FRONTEND=noninteractive \
    LANG=C.UTF-8 \
    RUSTUP_HOME=/usr/local/rustup \
    PATH=/usr/local/cargo/bin:$PATH \
    PLAYWRIGHT_BROWSERS_PATH=/opt/ms-playwright \
    DISABLE_AUTOUPDATER=1

# Base tools, plus what Rust crates commonly need to build (C toolchain, pkg-config, OpenSSL).
RUN apt-get update && apt-get install -y --no-install-recommends \
      ca-certificates curl gnupg sudo git tmux unzip jq less nano procps \
      build-essential pkg-config libssl-dev \
 && rm -rf /var/lib/apt/lists/*

# Docker Engine, CLI, Buildx and Compose. The daemon runs inside the workspace, which the Sysbox
# runtime allows without a privileged container.
RUN install -m 0755 -d /etc/apt/keyrings \
 && curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc \
 && echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu $(. /etc/os-release && echo "$VERSION_CODENAME") stable" \
      > /etc/apt/sources.list.d/docker.list \
 && apt-get update && apt-get install -y --no-install-recommends \
      docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin \
 && rm -rf /var/lib/apt/lists/*

# GitHub CLI.
RUN curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg \
      -o /etc/apt/keyrings/githubcli-archive-keyring.gpg \
 && chmod go+r /etc/apt/keyrings/githubcli-archive-keyring.gpg \
 && echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" \
      > /etc/apt/sources.list.d/github-cli.list \
 && apt-get update && apt-get install -y --no-install-recommends gh \
 && rm -rf /var/lib/apt/lists/*

# Node (LTS line) for Playwright, Claude Code and the Infisical CLI.
RUN curl -fsSL "https://deb.nodesource.com/setup_${NODE_MAJOR}.x" | bash - \
 && apt-get install -y --no-install-recommends nodejs \
 && rm -rf /var/lib/apt/lists/*

# Rust via rustup, installed system-wide. At runtime the template sets CARGO_HOME to
# ~/.cargo so the crate registry cache lives in the persistent home volume, while the
# toolchain and the cargo/rustc binaries stay here.
RUN curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs \
    | CARGO_HOME=/usr/local/cargo sh -s -- -y --no-modify-path --profile minimal \
        --default-toolchain "${RUST_VERSION}" --component rustfmt,clippy

# bun, for syntax-checking project JavaScript.
RUN curl -fsSL https://bun.sh/install | BUN_INSTALL=/usr/local bash

# Claude Code, the Infisical CLI, Playwright and its MCP server, then Chromium with the system
# libraries it needs. Claude Code's auto-updater is off (DISABLE_AUTOUPDATER above): rebuild the
# image to update it, so every workspace runs the same version.
RUN npm install -g \
      @anthropic-ai/claude-code \
      @infisical/cli \
      "playwright@${PLAYWRIGHT_VERSION}" \
      "@playwright/mcp@${PLAYWRIGHT_MCP_VERSION}" \
 && playwright install --with-deps chromium \
 && chmod -R a+rX "${PLAYWRIGHT_BROWSERS_PATH}" \
 && npm cache clean --force \
 && rm -rf /var/lib/apt/lists/*

# The workspace user, named after the Coder workspace owner. Ubuntu's image ships a "ubuntu" user
# with UID 1000; replace it with ours at the same UID. The user gets passwordless sudo (needed to
# start dockerd), membership in the docker group, and ownership of the Rust toolchain so rustup can
# add components and toolchains.
RUN userdel -r ubuntu 2>/dev/null || true \
 && useradd --create-home --shell /bin/bash --uid 1000 "${USER}" \
 && usermod -aG docker "${USER}" \
 && echo "${USER} ALL=(ALL) NOPASSWD:ALL" > "/etc/sudoers.d/${USER}" \
 && chmod 0440 "/etc/sudoers.d/${USER}" \
 && chown -R "${USER}:${USER}" /usr/local/rustup /usr/local/cargo

USER ${USER}
WORKDIR /home/${USER}
