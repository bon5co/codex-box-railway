#!/usr/bin/env bash
# Boot sequence for Codex Box on Railway.
#
#   1. Require the persistent volume. Without it every Codex login, repo and installed
#      tool is lost on the next deploy, and the failure is silent, so refuse to start.
#   2. Repair volume ownership (Railway mounts volumes as uid 0) and relocate $HOME onto
#      the volume.
#   3. Seed Codex authentication from OPENAI_API_KEY if one was supplied. The Codex CLI
#      does NOT read that environment variable at request time (measured on 0.147.0: it
#      sends no bearer at all and retries five times before reporting a 401), so the key
#      has to be written into $CODEX_HOME/auth.json for the box to be usable on arrival.
#   4. Hand the container over to a process that keeps it alive for SSH sessions.
set -euo pipefail

DATA_DIR=${DATA_DIR:-/data}
USER_HOME=/home/user
PERSIST_HOME=$DATA_DIR/home/user
CODEX_HOME=${CODEX_HOME:-$PERSIST_HOME/.codex}
WORKSPACE=$DATA_DIR/workspace

log() { printf '[codex-box] %s\n' "$*"; }

if ! grep -qs " $DATA_DIR " /proc/mounts; then
    echo "[codex-box] FATAL: no persistent volume mounted at $DATA_DIR." >&2
    echo "[codex-box] Attach a volume at $DATA_DIR — without it your Codex login, repositories" >&2
    echo "[codex-box] and installed tools are erased on every redeploy." >&2
    exit 1
fi

sudo chown user:user "$DATA_DIR"
log "volume owner=$(stat -c %u:%g "$DATA_DIR")"

mkdir -p "$PERSIST_HOME" "$CODEX_HOME" "$WORKSPACE" \
         "$PERSIST_HOME/.local/bin" "$PERSIST_HOME/.config" "$PERSIST_HOME/.cache" \
         "$PERSIST_HOME/.ssh"
chmod 700 "$PERSIST_HOME/.ssh"

# Seed the persisted home from the image's home, first boot only. Files the deployer
# already has always win, so an image upgrade never clobbers their settings.
if [ -d "$USER_HOME" ] && [ ! -L "$USER_HOME" ]; then
    shopt -s dotglob nullglob
    for item in "$USER_HOME"/*; do
        target="$PERSIST_HOME/$(basename "$item")"
        [ -e "$target" ] || [ -L "$target" ] || cp -a "$item" "$target"
    done
    shopt -u dotglob nullglob
fi

# /home/user and /root both point at the persisted home so tools behave the same whether
# a session runs as the user or escalates with sudo.
sudo rm -rf "$USER_HOME" && sudo ln -s "$PERSIST_HOME" "$USER_HOME"
sudo rm -rf /root && sudo ln -s "$PERSIST_HOME" /root

if [ ! -f "$CODEX_HOME/config.toml" ] && [ -f /opt/codex-defaults/config.toml ]; then
    cp /opt/codex-defaults/config.toml "$CODEX_HOME/config.toml"
fi

if [ -n "${OPENAI_API_KEY:-}" ]; then
    if [ -s "$CODEX_HOME/auth.json" ] && ! grep -q '"auth_mode": *"apikey"' "$CODEX_HOME/auth.json"; then
        log "auth.json exists from an interactive login; leaving it alone"
    else
        printf '%s' "$OPENAI_API_KEY" | codex login --with-api-key >/dev/null 2>&1 \
            && log "Codex authenticated from OPENAI_API_KEY (auth_mode=apikey)" \
            || log "WARNING: could not write Codex credentials from OPENAI_API_KEY"
        chmod 600 "$CODEX_HOME/auth.json" 2>/dev/null || true
    fi
else
    log "no OPENAI_API_KEY set — run 'codex login' inside the box before first use"
fi

# Git works out of the box on a volume that other uids have touched.
git config --global --add safe.directory '*' || true
git config --global init.defaultBranch main || true

log "codex $(codex --version 2>/dev/null || echo unknown) ready; workspace=$WORKSPACE"
cd "$WORKSPACE"
exec sleep infinity
