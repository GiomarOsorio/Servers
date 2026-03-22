#!/usr/bin/env bash
set -euo pipefail

# ── GameServers Deploy Script ────────────────────────────────────────────────
# Deploys Minecraft and Don't Starve Together servers via Podman Quadlets.
# Can be run manually or via GitHub Actions (self-hosted runner).

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
QUADLET_DIR="$HOME/.config/containers/systemd"
ENV_FILE="$HOME/gameservers.env"

# ── Secrets: from CI environment or existing env file ────────────────────────
if [[ -n "${GS_MINECRAFT_RCON_PASSWORD:-}" ]]; then
    echo ">> Writing env file from CI secrets..."
    cat > "$ENV_FILE" <<'ENVEOF'
# Minecraft
RCON_PASSWORD=__GS_MINECRAFT_RCON_PASSWORD__
OPS=__GS_MINECRAFT_OPS__
MOTD=__GS_MINECRAFT_MOTD__
MAX_PLAYERS=__GS_MINECRAFT_MAX_PLAYERS__
DIFFICULTY=__GS_MINECRAFT_DIFFICULTY__
MODE=__GS_MINECRAFT_MODE__
MEMORY=__GS_MINECRAFT_MEMORY__

# Don't Starve Together
DST_CLUSTER_TOKEN=__GS_DST_CLUSTER_TOKEN__
DST_CLUSTER_NAME=__GS_DST_CLUSTER_NAME__
DST_CLUSTER_PASSWORD=__GS_DST_CLUSTER_PASSWORD__
DST_CLUSTER_DESCRIPTION=__GS_DST_CLUSTER_DESCRIPTION__
DST_MAX_PLAYERS=__GS_DST_MAX_PLAYERS__
ENVEOF

    # Substitute placeholders with actual values (with defaults)
    sed -i "s|__GS_MINECRAFT_RCON_PASSWORD__|${GS_MINECRAFT_RCON_PASSWORD}|g" "$ENV_FILE"
    sed -i "s|__GS_MINECRAFT_OPS__|${GS_MINECRAFT_OPS:-}|g" "$ENV_FILE"
    sed -i "s|__GS_MINECRAFT_MOTD__|${GS_MINECRAFT_MOTD:-TurtleServer Minecraft}|g" "$ENV_FILE"
    sed -i "s|__GS_MINECRAFT_MAX_PLAYERS__|${GS_MINECRAFT_MAX_PLAYERS:-10}|g" "$ENV_FILE"
    sed -i "s|__GS_MINECRAFT_DIFFICULTY__|${GS_MINECRAFT_DIFFICULTY:-normal}|g" "$ENV_FILE"
    sed -i "s|__GS_MINECRAFT_MODE__|${GS_MINECRAFT_MODE:-survival}|g" "$ENV_FILE"
    sed -i "s|__GS_MINECRAFT_MEMORY__|${GS_MINECRAFT_MEMORY:-4G}|g" "$ENV_FILE"
    sed -i "s|__GS_DST_CLUSTER_TOKEN__|${GS_DST_CLUSTER_TOKEN:-}|g" "$ENV_FILE"
    sed -i "s|__GS_DST_CLUSTER_NAME__|${GS_DST_CLUSTER_NAME:-TurtleServer DST}|g" "$ENV_FILE"
    sed -i "s|__GS_DST_CLUSTER_PASSWORD__|${GS_DST_CLUSTER_PASSWORD:-}|g" "$ENV_FILE"
    sed -i "s|__GS_DST_CLUSTER_DESCRIPTION__|${GS_DST_CLUSTER_DESCRIPTION:-Don't Starve Together on TurtleServer}|g" "$ENV_FILE"
    sed -i "s|__GS_DST_MAX_PLAYERS__|${GS_DST_MAX_PLAYERS:-6}|g" "$ENV_FILE"

    chmod 600 "$ENV_FILE"
elif [[ -f "$ENV_FILE" ]]; then
    echo ">> Using existing env file: $ENV_FILE"
else
    echo "ERROR: No secrets in environment and no $ENV_FILE found."
    echo "       Set GS_* environment variables or create $ENV_FILE manually."
    exit 1
fi

# ── Enable linger for user-level systemd services ────────────────────────────
loginctl enable-linger "$USER" 2>/dev/null || true

# ── Pull images ──────────────────────────────────────────────────────────────
echo ">> Pulling game server images..."
podman pull docker.io/itzg/minecraft-server:latest
podman pull docker.io/jamesits/dst-server:latest

# ── Install Quadlet files ────────────────────────────────────────────────────
echo ">> Installing quadlet files to $QUADLET_DIR..."
mkdir -p "$QUADLET_DIR"

for f in "$SCRIPT_DIR/quadlet/"*; do
    sed "s|__ENV_FILE__|${ENV_FILE}|g" "$f" > "$QUADLET_DIR/$(basename "$f")"
done

# ── Copy DST config into volume ─────────────────────────────────────────────
echo ">> Preparing DST configuration..."

# Ensure volume exists
podman volume inspect gameservers-dst-data >/dev/null 2>&1 || podman volume create gameservers-dst-data

DST_VOLUME_PATH=$(podman volume inspect gameservers-dst-data --format '{{.Mountpoint}}')
DST_CLUSTER_DIR="$DST_VOLUME_PATH/DoNotStarveTogether/Cluster_1"

mkdir -p "$DST_CLUSTER_DIR/Master"
mkdir -p "$DST_CLUSTER_DIR/Caves"

# Write cluster token
if grep -q "DST_CLUSTER_TOKEN=" "$ENV_FILE"; then
    DST_TOKEN=$(grep "DST_CLUSTER_TOKEN=" "$ENV_FILE" | cut -d= -f2-)
    if [[ -n "$DST_TOKEN" ]]; then
        echo "$DST_TOKEN" > "$DST_CLUSTER_DIR/cluster_token.txt"
    fi
fi

# Copy config files (don't overwrite if they already exist, preserving user customizations)
cp -n "$SCRIPT_DIR/config/dst/cluster.ini" "$DST_CLUSTER_DIR/cluster.ini" 2>/dev/null || true
cp -n "$SCRIPT_DIR/config/dst/Master/server.ini" "$DST_CLUSTER_DIR/Master/server.ini" 2>/dev/null || true
cp -n "$SCRIPT_DIR/config/dst/Caves/server.ini" "$DST_CLUSTER_DIR/Caves/server.ini" 2>/dev/null || true
cp -n "$SCRIPT_DIR/config/dst/Master/worldgenoverride.lua" "$DST_CLUSTER_DIR/Master/worldgenoverride.lua" 2>/dev/null || true
cp -n "$SCRIPT_DIR/config/dst/Caves/worldgenoverride.lua" "$DST_CLUSTER_DIR/Caves/worldgenoverride.lua" 2>/dev/null || true

# Update dynamic values from env
if grep -q "DST_CLUSTER_NAME=" "$ENV_FILE"; then
    DST_NAME=$(grep "DST_CLUSTER_NAME=" "$ENV_FILE" | cut -d= -f2-)
    sed -i "s|^cluster_name = .*|cluster_name = ${DST_NAME}|" "$DST_CLUSTER_DIR/cluster.ini"
fi
if grep -q "DST_CLUSTER_PASSWORD=" "$ENV_FILE"; then
    DST_PASS=$(grep "DST_CLUSTER_PASSWORD=" "$ENV_FILE" | cut -d= -f2-)
    sed -i "s|^cluster_password = .*|cluster_password = ${DST_PASS}|" "$DST_CLUSTER_DIR/cluster.ini"
fi
if grep -q "DST_CLUSTER_DESCRIPTION=" "$ENV_FILE"; then
    DST_DESC=$(grep "DST_CLUSTER_DESCRIPTION=" "$ENV_FILE" | cut -d= -f2-)
    sed -i "s|^cluster_description = .*|cluster_description = ${DST_DESC}|" "$DST_CLUSTER_DIR/cluster.ini"
fi
if grep -q "DST_MAX_PLAYERS=" "$ENV_FILE"; then
    DST_MAX=$(grep "DST_MAX_PLAYERS=" "$ENV_FILE" | cut -d= -f2-)
    sed -i "s|^max_players = .*|max_players = ${DST_MAX}|" "$DST_CLUSTER_DIR/cluster.ini"
fi

# ── Reload systemd and restart services ──────────────────────────────────────
echo ">> Reloading systemd daemon..."
systemctl --user daemon-reload

echo ">> Starting Minecraft server..."
systemctl --user restart gameservers-minecraft

echo ">> Starting Don't Starve Together server..."
systemctl --user restart gameservers-dst

# ── Verify ───────────────────────────────────────────────────────────────────
echo ""
echo "========================================="
echo "  GameServers deployed successfully!"
echo "========================================="
echo ""
echo "Minecraft:"
echo "  Status:  systemctl --user status gameservers-minecraft"
echo "  Logs:    journalctl --user -u gameservers-minecraft -f"
echo "  RCON:    podman exec -i gameservers-minecraft rcon-cli"
echo "  Connect: turtleServer:25565"
echo ""
echo "Don't Starve Together:"
echo "  Status:  systemctl --user status gameservers-dst"
echo "  Logs:    journalctl --user -u gameservers-dst -f"
echo "  Connect: turtleServer:11000"
echo ""
echo "Auto-pause:"
echo "  Minecraft: AUTOPAUSE enabled (pauses JVM after 5min idle)"
echo "  DST:       pause_when_empty = true (pauses world when empty)"
echo ""
