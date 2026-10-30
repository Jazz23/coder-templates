terraform {
  required_providers {
    coder = {
      source  = "coder/coder"
      version = "~> 2.19"
    }
    docker = {
      source  = "kreuzwerker/docker"
      version = "~> 4.6"
    }
  }
}

locals {
  # Lowercased: Docker image tags and Linux usernames must be lowercase, Coder usernames needn't be.
  username = lower(data.coder_workspace_owner.me.name)
  home     = "/home/${local.username}"
}

variable "docker_socket" {
  default     = ""
  description = "(Optional) Docker socket URI"
  type        = string
}

provider "docker" {
  # Defaulting to null if the variable is an empty string lets us have an optional variable without having to set our own default
  host = var.docker_socket != "" ? var.docker_socket : null
}

data "coder_provisioner" "me" {}
data "coder_workspace" "me" {}
data "coder_workspace_owner" "me" {}

# Parameters chosen when the workspace is created.

data "coder_parameter" "repo_url" {
  type         = "string"
  name         = "repo_url"
  display_name = "Git repository"
  description  = "HTTPS URL of the repository to clone into this workspace."
  mutable      = false
  validation {
    regex = "^(https://.*)?$"
    error = "Use the repository's HTTPS URL."
  }
}

data "coder_parameter" "infisical_project_id" {
  type         = "string"
  name         = "infisical_project_id"
  display_name = "Infisical project ID"
  description  = "Leave empty to skip creating .env. Otherwise the project's secrets are written to .env at the repository root on every start."
  default      = ""
  mutable      = true
  validation {
    regex = "^[A-Za-z0-9-]*$"
    error = "Paste the project ID from Infisical's project settings."
  }
}

data "coder_parameter" "infisical_env" {
  type         = "string"
  name         = "infisical_env"
  display_name = "Infisical environment"
  description  = "Environment slug to export into .env."
  default      = "dev"
  mutable      = true
  validation {
    regex = "^[A-Za-z0-9_-]+$"
    error = "Use the environment's slug, such as dev."
  }
}

resource "coder_agent" "main" {
  arch           = data.coder_provisioner.me.arch
  os             = "linux"
  startup_script = <<-EOT
    set -e

    # Prepare user home with default files on first start.
    if [ ! -f ~/.init_done ]; then
      cp -rT /etc/skel ~
      touch ~/.init_done
    fi

    # Docker creates volume mount points as root; hand the shared per-user ones to this user.
    sudo chown "$(id -u):$(id -g)" ~/.claude-auth ~/.infisical-identity
    mkdir -p ~/.cargo

    # Start the workspace's own Docker daemon and wait until it answers.
    if ! pgrep -x dockerd >/dev/null; then
      sudo sh -c 'dockerd > /var/log/dockerd.log 2>&1 &'
    fi
    for i in $(seq 1 60); do
      docker info >/dev/null 2>&1 && break
      sleep 1
    done
  EOT

  shutdown_script = <<-EOT
    # Drop Docker images, containers and build cache unused for a week, keeping recent cache warm.
    docker system prune -f --filter "until=168h" || true
    sudo sh -c 'kill "$(cat /var/run/docker.pid)"' 2>/dev/null || true
  EOT

  env = {
    # Claude Code keeps its login and settings in the per-user volume, shared by all your workspaces.
    CLAUDE_CONFIG_DIR = "${local.home}/.claude-auth"

    # Crate registry cache in the persistent home volume; toolchain binaries stay in the image.
    CARGO_HOME = "${local.home}/.cargo"
  }

  # The following metadata blocks are optional. They are used to display
  # information about your workspace in the dashboard. You can remove them
  # if you don't want to display any information.
  # For basic resources, you can use the `coder stat` command.
  # If you need more control, you can write your own script.
  metadata {
    display_name = "CPU Usage"
    key          = "0_cpu_usage"
    script       = "coder stat cpu"
    interval     = 10
    timeout      = 1
  }

  metadata {
    display_name = "RAM Usage"
    key          = "1_ram_usage"
    script       = "coder stat mem"
    interval     = 10
    timeout      = 1
  }

  metadata {
    display_name = "Home Disk"
    key          = "3_home_disk"
    script       = "coder stat disk --path $${HOME}"
    interval     = 60
    timeout      = 1
  }

  metadata {
    display_name = "Docker Data"
    key          = "3b_docker_disk"
    script       = "sudo du -shx /var/lib/docker 2>/dev/null | cut -f1"
    interval     = 300
    timeout      = 30
  }

  metadata {
    display_name = "CPU Usage (Host)"
    key          = "4_cpu_usage_host"
    script       = "coder stat cpu --host"
    interval     = 10
    timeout      = 1
  }

  metadata {
    display_name = "Memory Usage (Host)"
    key          = "5_mem_usage_host"
    script       = "coder stat mem --host"
    interval     = 10
    timeout      = 1
  }

  metadata {
    display_name = "Load Average (Host)"
    key          = "6_load_host"
    # get load avg scaled by number of cores
    script   = <<EOT
      echo "`cat /proc/loadavg | awk '{ print $1 }'` `nproc`" | awk '{ printf "%0.2f", $1/$2 }'
    EOT
    interval = 60
    timeout  = 1
  }

  metadata {
    display_name = "Swap Usage (Host)"
    key          = "7_swap_host"
    script       = <<EOT
      free -b | awk '/^Swap/ { printf("%.1f/%.1f", $3/1024.0/1024.0/1024.0, $2/1024.0/1024.0/1024.0) }'
    EOT
    interval     = 10
    timeout      = 1
  }
}

module "git-config" {
  count    = data.coder_workspace.me.start_count
  source   = "registry.coder.com/coder/git-config/coder"
  version  = "~> 1.0"
  agent_id = coder_agent.main.id
}

# See https://registry.coder.com/modules/coder/git-clone
module "git-clone" {
  count    = data.coder_workspace.me.start_count
  source   = "registry.coder.com/coder/git-clone/coder"
  version  = "~> 2.0"
  agent_id = coder_agent.main.id
  url      = data.coder_parameter.repo_url.value
  base_dir = local.home
}

# See https://registry.coder.com/modules/coder/code-server
module "code-server" {
  count    = data.coder_workspace.me.start_count
  source   = "registry.coder.com/coder/code-server/coder"
  version  = "~> 1.0"
  agent_id = coder_agent.main.id
  order    = 1
  folder   = "${local.home}/${module.git-clone[0].folder_name}"
}

# Write the project's Infisical secrets to .env at the repository root, using the machine identity
# in ~/.infisical-identity/identity.env (created once per user). Runs on every start and from the
# "Refresh .env" button on the dashboard.
locals {
  refresh_env_path   = "${local.home}/.local/bin/refresh-env"
  refresh_env_script = <<-EOT
    #!/usr/bin/env bash
    set -euo pipefail

    REPO_DIR="${local.home}/${try(module.git-clone[0].folder_name, "")}"
    PROJECT_ID="${data.coder_parameter.infisical_project_id.value}"
    INF_ENV="${data.coder_parameter.infisical_env.value}"
    CREDS="$HOME/.infisical-identity/identity.env"

    if [ -z "$PROJECT_ID" ]; then
      echo "No Infisical project ID for this workspace; not creating .env."
      exit 0
    fi
    if [ ! -f "$CREDS" ]; then
      echo "Missing $CREDS. Create it once with the machine identity's client ID and secret, then restart or click Refresh .env."
      exit 0
    fi

    # git-clone runs at the same time as this script; wait for the repository.
    for i in $(seq 1 300); do
      [ -d "$REPO_DIR/.git" ] && break
      sleep 1
    done
    if [ ! -d "$REPO_DIR/.git" ]; then
      echo "Repository not cloned at $REPO_DIR; not creating .env."
      exit 0
    fi

    set -a; . "$CREDS"; set +a
    export INFISICAL_TOKEN="$(infisical login --method=universal-auth --silent --plain)"

    # Write to a temp file first so a failed export never wipes an existing .env.
    infisical export --projectId="$PROJECT_ID" --env="$INF_ENV" --format=dotenv > "$REPO_DIR/.env.tmp"
    chmod 600 "$REPO_DIR/.env.tmp"
    mv "$REPO_DIR/.env.tmp" "$REPO_DIR/.env"
    echo "Wrote $REPO_DIR/.env from Infisical ($INF_ENV)."
  EOT
}

resource "coder_script" "infisical_env" {
  count        = data.coder_workspace.me.start_count
  agent_id     = coder_agent.main.id
  display_name = "Infisical .env"
  run_on_start = true
  script       = <<-EOT
    #!/usr/bin/env bash
    set -euo pipefail
    mkdir -p "$(dirname "${local.refresh_env_path}")"
    echo "${base64encode(local.refresh_env_script)}" | base64 -d > "${local.refresh_env_path}"
    chmod 755 "${local.refresh_env_path}"
    exec "${local.refresh_env_path}"
  EOT
}

# Dashboard button that re-exports .env from Infisical without restarting the workspace.
resource "coder_app" "refresh_env" {
  count        = data.coder_workspace.me.start_count
  agent_id     = coder_agent.main.id
  slug         = "refresh-env"
  display_name = "Refresh .env"
  icon         = "/emojis/1f511.png"
  order        = 2
  command      = "bash -c '${local.refresh_env_path}; echo; read -rp \"Press Enter to close.\"'"
}

# Claude Code in Remote Control server mode, inside tmux in the repository. First time per user:
# `claude auth login`. First time per workspace: `tmux attach -t claude` to answer the one-time
# prompts, then detach with Ctrl-b d.
resource "coder_script" "claude_remote" {
  count        = data.coder_workspace.me.start_count
  agent_id     = coder_agent.main.id
  display_name = "Claude Remote Control"
  run_on_start = true
  script       = <<-EOT
    #!/usr/bin/env bash
    REPO_DIR="${local.home}/${module.git-clone[0].folder_name}"

    for i in $(seq 1 300); do
      [ -d "$REPO_DIR/.git" ] && break
      sleep 1
    done
    [ -d "$REPO_DIR" ] || REPO_DIR="$HOME"

    # Register the Playwright MCP server once; it's saved in the shared Claude config.
    claude mcp get playwright >/dev/null 2>&1 \
      || claude mcp add --scope user playwright -- playwright-mcp --browser chromium --headless \
      || true

    tmux has-session -t claude 2>/dev/null \
      || tmux new-session -d -s claude -c "$REPO_DIR" \
           "claude remote-control --name '${data.coder_workspace.me.name}'; exec bash"
  EOT
}

resource "docker_volume" "home_volume" {
  name = "coder-${data.coder_workspace.me.id}-home"
  # Protect the volume from being deleted due to changes in attributes.
  lifecycle {
    ignore_changes = all
  }
  # Add labels in Docker to keep track of orphan resources.
  labels {
    label = "coder.owner"
    value = data.coder_workspace_owner.me.name
  }
  labels {
    label = "coder.owner_id"
    value = data.coder_workspace_owner.me.id
  }
  labels {
    label = "coder.workspace_id"
    value = data.coder_workspace.me.id
  }
  # This field becomes outdated if the workspace is renamed but can
  # be useful for debugging or cleaning out dangling volumes.
  labels {
    label = "coder.workspace_name_at_creation"
    value = data.coder_workspace.me.name
  }
}

# The workspace's own Docker data (images, containers, volumes, build cache), kept across restarts.
resource "docker_volume" "docker_volume" {
  name = "coder-${data.coder_workspace.me.id}-docker"
  lifecycle {
    ignore_changes = all
  }
  labels {
    label = "coder.owner"
    value = data.coder_workspace_owner.me.name
  }
  labels {
    label = "coder.owner_id"
    value = data.coder_workspace_owner.me.id
  }
  labels {
    label = "coder.workspace_id"
    value = data.coder_workspace.me.id
  }
  labels {
    label = "coder.workspace_name_at_creation"
    value = data.coder_workspace.me.name
  }
}

# One image per user, shared by all of that user's workspaces and tagged by a hash of build/.
# Editing the Dockerfile produces a new tag; keep_locally stops a workspace deletion from removing
# an image the user's other workspaces still use.
resource "docker_image" "main" {
  name = "coder-${local.username}:${substr(sha1(join("", [for f in sort(fileset(path.module, "build/**")) : filesha1("${path.module}/${f}")])), 0, 12)}"
  build {
    context = "./build"
    build_args = {
      USER = local.username
    }
  }
  keep_locally = true
}

resource "docker_container" "workspace" {
  count = data.coder_workspace.me.start_count
  image = docker_image.main.image_id
  # Sysbox runs the workspace's own Docker daemon without a privileged container.
  runtime = "sysbox-runc"
  # Uses lower() to avoid Docker restriction on container names.
  name = "coder-${data.coder_workspace_owner.me.name}-${lower(data.coder_workspace.me.name)}"
  # Hostname makes the shell more user friendly: coder@my-workspace:~$
  hostname = data.coder_workspace.me.name
  # Use the docker gateway if the access URL is 127.0.0.1
  entrypoint = ["sh", "-c", replace(coder_agent.main.init_script, "/localhost|127\\.0\\.0\\.1/", "host.docker.internal")]
  env        = ["CODER_AGENT_TOKEN=${coder_agent.main.token}"]
  host {
    host = "host.docker.internal"
    ip   = "host-gateway"
  }

  # Optional resource limits; size these to your VPS.
  # memory  = 8192
  # cpu_set = "0-3"

  # Per workspace: home directory, including the cloned repo and build outputs.
  volumes {
    container_path = local.home
    volume_name    = docker_volume.home_volume.name
    read_only      = false
  }

  # Per workspace: the inner Docker daemon's data.
  volumes {
    container_path = "/var/lib/docker"
    volume_name    = docker_volume.docker_volume.name
    read_only      = false
  }

  # Per user, shared by all your workspaces: Claude Code login and settings. Deliberately not a
  # docker_volume resource, so deleting a workspace never deletes it.
  volumes {
    container_path = "${local.home}/.claude-auth"
    volume_name    = "coder-claude-${data.coder_workspace_owner.me.id}"
    read_only      = false
  }

  # Per user, shared by all your workspaces: Infisical machine identity credentials.
  volumes {
    container_path = "${local.home}/.infisical-identity"
    volume_name    = "coder-infisical-${data.coder_workspace_owner.me.id}"
    read_only      = false
  }

  # Add labels in Docker to keep track of orphan resources.
  labels {
    label = "coder.owner"
    value = data.coder_workspace_owner.me.name
  }
  labels {
    label = "coder.owner_id"
    value = data.coder_workspace_owner.me.id
  }
  labels {
    label = "coder.workspace_id"
    value = data.coder_workspace.me.id
  }
  labels {
    label = "coder.workspace_name"
    value = data.coder_workspace.me.name
  }
}
