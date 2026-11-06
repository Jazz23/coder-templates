# Workspace image for the shared Coder template: Docker Engine, Rust, Node, bun, Playwright with
# a headless Chromium, Claude Code, the Infisical CLI, the GitHub CLI, cron, Blender, ffmpeg,
# OpenAI Whisper, and the FilmCraft CLI.
#
# Everything is installed OUTSIDE the user's home, because the workspace's home volume is mounted
# over that directory at runtime and would hide anything put there at build time.
FROM ubuntu:24.04

ARG RUST_VERSION=1.99.1
ARG NODE_MAJOR=24
# playwright is pinned to the build @playwright/mcp bundles, so both use the one Chromium;
# bump them together.
ARG PLAYWRIGHT_VERSION=1.64.0-alpha-1790635538000
ARG PLAYWRIGHT_MCP_VERSION=0.0.83
ARG BLENDER_VERSION=5.2.3
ARG BLENDER_SHA256=78486c018b4443efe5e75ab54c290ed8c15abafd249b862c2c9ce2530a918eec
ARG WHISPER_VERSION=20250625
ARG FILMCRAFT_VERSION=0.17.1
ARG FILMCRAFT_SHA256=397ae9fece559b37863b4b076af46a63b6e4387c35f781709e4efad14fe71ebe

ENV DEBIAN_FRONTEND=noninteractive \
    LANG=C.UTF-8 \
    RUSTUP_HOME=/usr/local/rustup \
    PATH=/usr/local/cargo/bin:$PATH \
    PLAYWRIGHT_BROWSERS_PATH=/opt/ms-playwright \
    DISABLE_AUTOUPDATER=1

# Base tools, plus what Rust crates commonly need to build (C toolchain, pkg-config, OpenSSL).
RUN apt-get update && apt-get install -y --no-install-recommends \
      ca-certificates curl gnupg sudo git tmux unzip jq less nano procps cron \
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
# toolchain and the cargo/rustc binaries stay here. Owned by UID 1000, the workspace user's UID
# whatever its name, so rustup can add components and toolchains; chowning here rather than in the
# per-user step keeps the toolchain in a layer every user's image shares.
RUN curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs \
    | CARGO_HOME=/usr/local/cargo sh -s -- -y --no-modify-path --profile minimal \
        --default-toolchain "${RUST_VERSION}" --component rustfmt,clippy \
 && chown -R 1000:1000 /usr/local/rustup /usr/local/cargo

# bun, for syntax-checking project JavaScript.
RUN curl -fsSL https://bun.sh/install | BUN_INSTALL=/usr/local bash

# Blender, for headless use (`blender -b`), from the official Linux build plus the X11/GL
# libraries it loads even without a display. Fetched from a download.blender.org mirror, since
# download.blender.org itself rejects plain curl; the checksum is Blender's published one.
RUN apt-get update && apt-get install -y --no-install-recommends \
      xz-utils libx11-6 libxi6 libxxf86vm1 libxfixes3 libxrender1 libxkbcommon0 libsm6 \
      libgl1 libegl1 \
 && rm -rf /var/lib/apt/lists/* \
 && curl -fsSL -o /tmp/blender.tar.xz \
      "https://mirrors.ocf.berkeley.edu/blender/release/Blender${BLENDER_VERSION%.*}/blender-${BLENDER_VERSION}-linux-x64.tar.xz" \
 && echo "${BLENDER_SHA256}  /tmp/blender.tar.xz" | sha256sum -c - \
 && mkdir -p /opt/blender \
 && tar -xJf /tmp/blender.tar.xz -C /opt/blender --strip-components=1 \
 && rm /tmp/blender.tar.xz \
 && ln -s /opt/blender/blender /usr/local/bin/blender

# ffmpeg, plus Python for Whisper.
RUN apt-get update && apt-get install -y --no-install-recommends \
      ffmpeg python3 python3-venv \
 && rm -rf /var/lib/apt/lists/*

# OpenAI Whisper (the `whisper` CLI) in its own virtualenv, since Ubuntu's system Python refuses
# global pip installs. PyTorch comes from its CPU-only index: the workspace has no GPU, and the
# default CUDA build would add several GB to the image. Triton, which Whisper requires but only
# uses for CUDA kernels, is removed for the same reason (about 1 GB). Models download to
# ~/.cache/whisper on first use, in the persistent home volume.
RUN python3 -m venv /opt/whisper \
 && /opt/whisper/bin/pip install --no-cache-dir --index-url https://download.pytorch.org/whl/cpu torch \
 && /opt/whisper/bin/pip install --no-cache-dir "openai-whisper==${WHISPER_VERSION}" \
 && /opt/whisper/bin/pip uninstall -y triton \
 && ln -s /opt/whisper/bin/whisper /usr/local/bin/whisper

# The FilmCraft CLI (headless video editing and its MCP server), the prebuilt binary from the
# official Linux release; it needs only libc. The checksum is the one GitHub lists for the asset.
RUN curl -fsSL -o /tmp/filmcraft.tar.gz \
      "https://github.com/storytold/filmcraft/releases/download/v${FILMCRAFT_VERSION}/filmcraft-${FILMCRAFT_VERSION}-linux-x86_64.tar.gz" \
 && echo "${FILMCRAFT_SHA256}  /tmp/filmcraft.tar.gz" | sha256sum -c - \
 && tar -xzf /tmp/filmcraft.tar.gz -C /usr/local/bin --strip-components=2 \
      "filmcraft-${FILMCRAFT_VERSION}-linux-x86_64/bin/filmcraft-cli" \
 && rm /tmp/filmcraft.tar.gz

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
# start dockerd) and membership in the docker group.
#
# USER, the workspace owner's Coder username passed in by main.tf, is declared here rather than at
# the top: a changed build arg invalidates the cache for every RUN after its ARG line, so declaring
# it any earlier would make each new user rebuild the whole toolchain.
ARG USER=coder
RUN userdel -r ubuntu 2>/dev/null || true \
 && useradd --create-home --shell /bin/bash --uid 1000 "${USER}" \
 && usermod -aG docker "${USER}" \
 && echo "${USER} ALL=(ALL) NOPASSWD:ALL" > "/etc/sudoers.d/${USER}" \
 && chmod 0440 "/etc/sudoers.d/${USER}"

USER ${USER}
WORKDIR /home/${USER}
