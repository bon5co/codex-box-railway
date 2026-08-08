# Codex Box — a prebuilt, pinned remote development machine for the OpenAI Codex CLI,
# packaged for Railway.
#
# Design notes specific to Railway:
#   * Railway mounts volumes owned by uid 0. The entrypoint repairs ownership before
#     anything runs as the unprivileged user.
#   * Everything durable lives under the single volume mount (/data). $HOME is relocated
#     there so Codex auth, shell history, installed CLIs and cloned repos survive redeploys.
#   * The image is published prebuilt so a deploy is an image pull, not a source build,
#     and the Codex CLI version is pinned so a redeploy never silently upgrades the agent.

FROM ubuntu:24.04

ARG CODEX_VERSION=0.147.0

LABEL org.opencontainers.image.title="Codex Box" \
      org.opencontainers.image.description="Prebuilt, pinned remote dev machine for the OpenAI Codex CLI on Railway" \
      org.opencontainers.image.source="https://github.com/bon5co/codex-box-railway"

ENV DEBIAN_FRONTEND=noninteractive \
    SHELL=/bin/bash \
    LANG=C.UTF-8 \
    LC_ALL=C.UTF-8 \
    TZ=Etc/UTC

SHELL ["/bin/bash", "-o", "pipefail", "-c"]

RUN apt-get update && apt-get install -y --no-install-recommends \
        tini bubblewrap git git-lfs curl wget vim nano jq tmux zip unzip \
        ripgrep fd-find tree less sudo procps lsof htop rsync openssh-client \
        ca-certificates gnupg python3 python3-pip python3-venv build-essential \
    && curl -fsSL https://deb.nodesource.com/setup_22.x | bash - \
    && curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg \
        | dd of=/usr/share/keyrings/githubcli-archive-keyring.gpg \
    && echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" \
        > /etc/apt/sources.list.d/github-cli.list \
    && apt-get update && apt-get install -y --no-install-recommends nodejs gh \
    && ln -sf /usr/bin/fdfind /usr/local/bin/fd \
    && rm -rf /var/lib/apt/lists/*

# Unprivileged runtime user with passwordless sudo, so the environment can be extended
# from inside a session without rebuilding the image.
RUN useradd -m -s /bin/bash user \
    && printf '%s\n' "user ALL=(ALL) NOPASSWD: ALL" > /etc/sudoers.d/codex-box \
    && chmod 0440 /etc/sudoers.d/codex-box

# Codex CLI pinned to an exact version. Railway CLI (with agent support) for deploying
# from inside the box. uv for Python work, since pip alone is no longer the default.
RUN npm install -g "@openai/codex@${CODEX_VERSION}" \
    && curl -fsSL https://railway.com/install.sh | bash -s -- --yes --bin-dir /usr/local/bin \
    && curl -fsSL https://astral.sh/uv/install.sh | env UV_INSTALL_DIR=/usr/local/bin sh \
    && codex --version && railway --version && uv --version

# Defaults copied onto the volume on first boot only, so a later image upgrade never
# overwrites a deployer's own configuration.
COPY default-config.toml /opt/codex-defaults/config.toml

ENV CODEX_HOME=/data/home/user/.codex \
    NPM_CONFIG_PREFIX=/data/home/user/.local \
    PATH="/data/home/user/.local/bin:/usr/local/bin:/usr/local/sbin:/usr/sbin:/usr/bin:/sbin:/bin"

COPY railway-entrypoint.sh /usr/local/bin/codex-box-entrypoint
RUN chmod +x /usr/local/bin/codex-box-entrypoint

# Sessions (Railway SSH) land as the unprivileged user, which is what the Codex sandbox
# expects; the entrypoint uses passwordless sudo for the volume-ownership repair.
USER user
WORKDIR /data
ENTRYPOINT ["/usr/bin/tini", "--", "/usr/local/bin/codex-box-entrypoint"]
