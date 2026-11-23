# Workspace image for the shared Coder template: Docker Engine, Rust, Node, Python with pip, bun,
# Playwright with a headless Chromium, Claude Code, the Infisical CLI, the GitHub CLI, Git LFS,
# cron, Blender, Godot, ffmpeg, ImageMagick, the FilmCraft CLI, and Cloudflare's Wrangler CLI.
#
# Everything is installed OUTSIDE the user's home, because the workspace's home volume is mounted
# over that directory at runtime and would hide anything put there at build time.
FROM ubuntu:24.04

# Every tool is the newest release at build time; nothing is pinned. TEMPLATE_VERSION, the Coder
# template version passed in by main.tf, is the only thing that triggers a rebuild: changing it
# invalidates the cache for every RUN below, so a workspace picks up new releases when its owner
# updates it to a newly pushed template version, and keeps its image until then.
ARG TEMPLATE_VERSION

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

# Node, the current release line, for Playwright, Claude Code, Wrangler and the Infisical CLI.
RUN curl -fsSL https://deb.nodesource.com/setup_current.x | bash - \
 && apt-get install -y --no-install-recommends nodejs \
 && rm -rf /var/lib/apt/lists/*

# Python, the newest stable release line in the deadsnakes PPA (it also carries the next release's
# alphas and betas, which are skipped), with pip from its bundled ensurepip.
# `python`, `python3`, `pip` and `pip3` in /usr/local/bin point at it; Ubuntu's own
# /usr/bin/python3 is left alone for the system tools that use it. Without sudo, `pip install`
# falls back to ~/.local, in the persistent home volume; or use a venv (`python -m venv`).
# The PPA's signing key is fetched from the Ubuntu keyserver by its full fingerprint.
RUN curl -fsSL "https://keyserver.ubuntu.com/pks/lookup?op=get&options=mr&search=0xF23C5A6CF475977595C89F51BA6932366A755776" \
    | gpg --dearmor -o /etc/apt/keyrings/deadsnakes.gpg \
 && echo "deb [signed-by=/etc/apt/keyrings/deadsnakes.gpg] https://ppa.launchpadcontent.net/deadsnakes/ppa/ubuntu $(. /etc/os-release && echo "$VERSION_CODENAME") main" \
      > /etc/apt/sources.list.d/deadsnakes.list \
 && apt-get update \
 && for py in $(apt-cache pkgnames python3. | grep -E '^python3\.[0-9]+$' | sort -V -r); do \
      case "$(apt-cache show --no-all-versions "${py}" | sed -n 's/^Version: //p')" in \
        *~*) ;; \
        *) break ;; \
      esac; \
    done \
 && apt-get install -y --no-install-recommends "${py}" "${py}-venv" "${py}-dev" \
 && rm -rf /var/lib/apt/lists/* \
 && "${py}" -m ensurepip --upgrade \
 && "${py}" -m pip install --no-cache-dir --upgrade pip \
 && for name in python python3; do ln -sf "/usr/bin/${py}" "/usr/local/bin/${name}"; done \
 && for name in pip pip3; do ln -sf "/usr/local/bin/pip${py#python}" "/usr/local/bin/${name}"; done

# Rust via rustup, installed system-wide. At runtime the template sets CARGO_HOME to
# ~/.cargo so the crate registry cache lives in the persistent home volume, while the
# toolchain and the cargo/rustc binaries stay here. Owned by UID 1000, the workspace user's UID
# whatever its name, so rustup can add components and toolchains; chowning here rather than in the
# per-user step keeps the toolchain in a layer every user's image shares.
RUN curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs \
    | CARGO_HOME=/usr/local/cargo sh -s -- -y --no-modify-path --profile minimal \
        --default-toolchain stable --component rustfmt,clippy \
 && chown -R 1000:1000 /usr/local/rustup /usr/local/cargo

# bun, for syntax-checking project JavaScript.
RUN curl -fsSL https://bun.sh/install | BUN_INSTALL=/usr/local bash

# Blender, for headless use (`blender -b`), from the official Linux build plus the X11/GL
# libraries it loads even without a display. Fetched from a download.blender.org mirror, since
# download.blender.org itself rejects plain curl: the newest Linux build in the newest release
# folder that has one.
RUN apt-get update && apt-get install -y --no-install-recommends \
      xz-utils libx11-6 libxi6 libxxf86vm1 libxfixes3 libxrender1 libxkbcommon0 libsm6 \
      libgl1 libegl1 \
 && rm -rf /var/lib/apt/lists/* \
 && mirror=https://mirrors.ocf.berkeley.edu/blender/release \
 && for dir in $(curl -fsSL "${mirror}/" | grep -o 'Blender[0-9.]*/' | sort -uV -r); do \
      file="$(curl -fsSL "${mirror}/${dir}" | grep -o 'blender-[0-9.]*-linux-x64\.tar\.xz' | sort -uV | tail -n1)"; \
      [ -n "${file}" ] && break; \
    done \
 && curl -fsSL -o /tmp/blender.tar.xz "${mirror}/${dir}${file}" \
 && mkdir -p /opt/blender \
 && tar -xJf /tmp/blender.tar.xz -C /opt/blender --strip-components=1 \
 && rm /tmp/blender.tar.xz \
 && ln -s /opt/blender/blender /usr/local/bin/blender

# Godot, for headless use (`godot --headless`: scripts, imports, exports), the official Linux
# editor build from GitHub's latest stable release. Export templates are not included (over 1 GB);
# install them per project if you need to export. Here and below, the download is picked from the
# latest release's assets by a loose name pattern, so a renamed asset doesn't break the build.
RUN url="$(curl -fsSL https://api.github.com/repos/godotengine/godot/releases/latest \
      | jq -r '[.assets[] | select(.name | test("_linux\\.x86_64\\.zip$"))][0].browser_download_url')" \
 && curl -fsSL -o /tmp/godot.zip "${url}" \
 && unzip -q /tmp/godot.zip -d /tmp/godot \
 && install -m 0755 /tmp/godot/Godot_*_linux.x86_64 /usr/local/bin/godot \
 && rm -rf /tmp/godot.zip /tmp/godot

# ffmpeg.
RUN apt-get update && apt-get install -y --no-install-recommends ffmpeg \
 && rm -rf /var/lib/apt/lists/*

# ImageMagick 7, the official Linux AppImage, unpacked into /opt/imagemagick since containers
# have no FUSE to mount it (Ubuntu's own package is still ImageMagick 6, without `magick`). The
# AppImage bundles ImageMagick's own libraries but loads fontconfig from the system, and reads PDF
# and PostScript through Ghostscript. /usr/local/bin/magick is a wrapper that runs the AppImage's
# launcher; the classic tool names link to it, and the launcher picks the tool by the name it was
# called with.
RUN apt-get update && apt-get install -y --no-install-recommends libfontconfig1 ghostscript \
 && rm -rf /var/lib/apt/lists/* \
 && url="$(curl -fsSL https://api.github.com/repos/ImageMagick/ImageMagick/releases/latest \
      | jq -r '[.assets[] | select(.name | test("x86_64\\.AppImage$")) | select(.name | test("clang") | not)][0].browser_download_url')" \
 && curl -fsSL -o /tmp/imagemagick.AppImage "${url}" \
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
# latest Linux release; it needs only libc.
RUN url="$(curl -fsSL https://api.github.com/repos/storytold/filmcraft/releases/latest \
      | jq -r '[.assets[] | select(.name | test("linux-x86_64\\.tar\\.gz$"))][0].browser_download_url')" \
 && curl -fsSL -o /tmp/filmcraft.tar.gz "${url}" \
 && tar -xzf /tmp/filmcraft.tar.gz -C /usr/local/bin --strip-components=2 --wildcards \
      '*/bin/filmcraft-cli' \
 && rm /tmp/filmcraft.tar.gz

# Claude Code, the Infisical CLI, Cloudflare's Wrangler CLI, and the Playwright MCP server, then
# Chromium with the system libraries it needs. The `playwright` command is the copy of Playwright
# that @playwright/mcp bundles, so the CLI and the MCP server use the one Chromium. Claude Code's
# auto-updater is off (DISABLE_AUTOUPDATER above): updating the workspace rebuilds the image with
# the newest release instead.
RUN npm install -g \
      @anthropic-ai/claude-code \
      @infisical/cli \
      wrangler \
      @playwright/mcp \
 && ln -s "$(npm root -g)/@playwright/mcp/node_modules/playwright/cli.js" /usr/local/bin/playwright \
 && playwright install --with-deps chromium \
 && chmod -R a+rX "${PLAYWRIGHT_BROWSERS_PATH}" \
 && npm cache clean --force \
 && rm -rf /var/lib/apt/lists/*

# kubectl, the latest stable release, and k3d.
RUN curl -fsSL -o /tmp/kubectl \
      "https://dl.k8s.io/release/$(curl -fsSL https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl" \
 && install -m 0755 /tmp/kubectl /usr/local/bin/kubectl \
 && rm /tmp/kubectl \
 && curl -fsSL https://raw.githubusercontent.com/k3d-io/k3d/main/install.sh | bash

# pnpm

RUN curl -fsSL https://get.pnpm.io | sh -

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
