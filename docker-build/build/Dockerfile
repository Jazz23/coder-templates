# Workspace image for the shared Coder template: Docker Engine, Rust, Node, Python with pip, bun,
# Playwright with a headless Chromium, Claude Code, the Infisical CLI, the GitHub CLI, Git LFS,
# cron, Blender, Godot, ffmpeg, ImageMagick, and the FilmCraft CLI.
#
# Everything is installed OUTSIDE the user's home, because the workspace's home volume is mounted
# over that directory at runtime and would hide anything put there at build time.
FROM ubuntu:24.04

ARG RUST_VERSION=1.99.1
ARG NODE_MAJOR=24
ARG PYTHON_VERSION=3.15
# playwright is pinned to the build @playwright/mcp bundles, so both use the one Chromium;
# bump them together.
ARG PLAYWRIGHT_VERSION=1.64.0-alpha-1790635538000
ARG PLAYWRIGHT_MCP_VERSION=0.0.83
ARG BLENDER_VERSION=5.2.3
ARG BLENDER_SHA256=78486c018b4443efe5e75ab54c290ed8c15abafd249b862c2c9ce2530a918eec
ARG GODOT_VERSION=4.7.2
ARG GODOT_SHA512=9aa00f7a605200940bce3027a567b782f49bd8e940dd06ae9e987bd65aee1b1467edd56ed84fcdcbdd44354bf613bdbb4e5d2913e925850368e150c59ed54c65
ARG IMAGEMAGICK_VERSION=7.1.2-35
ARG IMAGEMAGICK_SHA256=f111044ed06b68cfb478df724c5a32d35145afa21073242f888d234a2f8cc002
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
      ca-certificates curl gnupg sudo git git-lfs tmux unzip jq less nano procps cron \
      build-essential pkg-config libssl-dev \
 && rm -rf /var/lib/apt/lists/*

# Git LFS hooks, set in /etc/gitconfig: a per-user `git lfs install` would write ~/.gitconfig,
# which the home volume hides at runtime.
RUN git lfs install --system

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

# Python, the newest release line, from the deadsnakes PPA, with pip from its bundled ensurepip.
# `python`, `python3`, `pip` and `pip3` in /usr/local/bin point at it; Ubuntu's own
# /usr/bin/python3 is left alone for the system tools that use it. Without sudo, `pip install`
# falls back to ~/.local, in the persistent home volume; or use a venv (`python -m venv`).
# The PPA's signing key is fetched from the Ubuntu keyserver by its full fingerprint.
RUN curl -fsSL "https://keyserver.ubuntu.com/pks/lookup?op=get&options=mr&search=0xF23C5A6CF475977595C89F51BA6932366A755776" \
    | gpg --dearmor -o /etc/apt/keyrings/deadsnakes.gpg \
 && echo "deb [signed-by=/etc/apt/keyrings/deadsnakes.gpg] https://ppa.launchpadcontent.net/deadsnakes/ppa/ubuntu $(. /etc/os-release && echo "$VERSION_CODENAME") main" \
      > /etc/apt/sources.list.d/deadsnakes.list \
 && apt-get update && apt-get install -y --no-install-recommends \
      "python${PYTHON_VERSION}" "python${PYTHON_VERSION}-venv" "python${PYTHON_VERSION}-dev" \
 && rm -rf /var/lib/apt/lists/* \
 && "python${PYTHON_VERSION}" -m ensurepip --upgrade \
 && "python${PYTHON_VERSION}" -m pip install --no-cache-dir --upgrade pip \
 && for name in python python3; do ln -sf "/usr/bin/python${PYTHON_VERSION}" "/usr/local/bin/${name}"; done \
 && for name in pip pip3; do ln -sf "/usr/local/bin/pip${PYTHON_VERSION}" "/usr/local/bin/${name}"; done

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

# Godot, for headless use (`godot --headless`: scripts, imports, exports), the official Linux
# editor build from GitHub; the checksum is the one in the release's SHA512-SUMS.txt. Export
# templates are not included (over 1 GB); install them per project if you need to export.
RUN curl -fsSL -o /tmp/godot.zip \
      "https://github.com/godotengine/godot/releases/download/${GODOT_VERSION}-stable/Godot_v${GODOT_VERSION}-stable_linux.x86_64.zip" \
 && echo "${GODOT_SHA512}  /tmp/godot.zip" | sha512sum -c - \
 && unzip -q /tmp/godot.zip -d /tmp/godot \
 && install -m 0755 "/tmp/godot/Godot_v${GODOT_VERSION}-stable_linux.x86_64" /usr/local/bin/godot \
 && rm -rf /tmp/godot.zip /tmp/godot

# ffmpeg.
RUN apt-get update && apt-get install -y --no-install-recommends ffmpeg \
 && rm -rf /var/lib/apt/lists/*

# ImageMagick 7, the official Linux AppImage, unpacked into /opt/imagemagick since containers
# have no FUSE to mount it (Ubuntu's own package is still ImageMagick 6, without `magick`). The
# checksum is the one GitHub lists for the asset. The AppImage bundles ImageMagick's own libraries
# but loads fontconfig from the system, and reads PDF and PostScript through Ghostscript. /usr/local/bin/magick is a wrapper that runs
# the AppImage's launcher; the classic tool names link to it, and the launcher picks the tool by
# the name it was called with.
RUN apt-get update && apt-get install -y --no-install-recommends libfontconfig1 ghostscript \
 && rm -rf /var/lib/apt/lists/* \
 && curl -fsSL -o /tmp/imagemagick.AppImage \
      "https://github.com/ImageMagick/ImageMagick/releases/download/${IMAGEMAGICK_VERSION}/ImageMagick-${IMAGEMAGICK_VERSION}-gcc-x86_64.AppImage" \
 && echo "${IMAGEMAGICK_SHA256}  /tmp/imagemagick.AppImage" | sha256sum -c - \
 && chmod +x /tmp/imagemagick.AppImage \
 && cd /tmp && ./imagemagick.AppImage --appimage-extract >/dev/null \
 && mv /tmp/squashfs-root /opt/imagemagick \
 && chmod -R a+rX /opt/imagemagick \
 && rm /tmp/imagemagick.AppImage \
 && printf '#!/bin/sh\nAPPIMAGE=/opt/imagemagick ARGV0="$(basename "$0")" exec /opt/imagemagick/AppRun "$@"\n' \
      > /usr/local/bin/magick \
 && chmod 0755 /usr/local/bin/magick \
 && for tool in convert identify mogrify composite compare montage stream conjure; do \
      ln -s magick "/usr/local/bin/${tool}"; \
    done

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

# ~/.local/bin, where `pip install --user` puts commands, on PATH for every shell, not only the
# login shells that ~/.profile covers.
ENV PATH=/home/${USER}/.local/bin:$PATH

USER ${USER}
WORKDIR /home/${USER}
