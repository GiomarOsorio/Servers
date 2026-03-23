#!/usr/bin/env bash
set -euo pipefail

# ── GameServers Backup Script ────────────────────────────────────────────────
# Creates compressed backups of Minecraft and DST server data
# and uploads them to MinIO on turtleStorage.
# Designed to run daily via systemd timer.

export XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"

MINIO_URL="${MINIO_URL:-http://192.168.8.189:9000}"
MINIO_ALIAS="storage"
MINIO_BUCKET="gameservers-backups"
BACKUP_DIR="/tmp/gameservers-backups"
DATE=$(date +%Y-%m-%d_%H-%M)
KEEP_DAYS=7

# ── Check mc CLI ─────────────────────────────────────────────────────────────
if ! command -v mc &>/dev/null; then
    echo "ERROR: mc CLI not found. Install with:"
    echo "  curl -fsSL https://dl.min.io/client/mc/release/linux-amd64/mc -o /usr/local/bin/mc && chmod +x /usr/local/bin/mc"
    exit 1
fi

# ── Configure MinIO alias ────────────────────────────────────────────────────
if ! mc alias list "$MINIO_ALIAS" &>/dev/null; then
    mc alias set "$MINIO_ALIAS" "$MINIO_URL" "${MINIO_ACCESS_KEY}" "${MINIO_SECRET_KEY}"
fi

# Ensure bucket exists
mc mb --ignore-existing "${MINIO_ALIAS}/${MINIO_BUCKET}"

# ── Prepare backup directory ─────────────────────────────────────────────────
rm -rf "$BACKUP_DIR"
mkdir -p "$BACKUP_DIR"

# ── Minecraft backup ────────────────────────────────────────────────────────
echo ">> Backing up Minecraft..."

# Save the world before backup
podman exec gameservers-minecraft rcon-cli save-all 2>/dev/null || true
sleep 3

MC_VOLUME=$(podman volume inspect gameservers-minecraft-data --format '{{.Mountpoint}}' 2>/dev/null || true)
if [[ -n "$MC_VOLUME" && -d "$MC_VOLUME" ]]; then
    tar czf "$BACKUP_DIR/minecraft_${DATE}.tar.gz" -C "$MC_VOLUME" .
    mc cp "$BACKUP_DIR/minecraft_${DATE}.tar.gz" "${MINIO_ALIAS}/${MINIO_BUCKET}/minecraft/"
    echo ">> Minecraft backup uploaded: minecraft_${DATE}.tar.gz"
else
    echo ">> WARN: Minecraft volume not found, skipping"
fi

# ── DST backup ───────────────────────────────────────────────────────────────
echo ">> Backing up DST..."

DST_VOLUME=$(podman volume inspect gameservers-dst-data --format '{{.Mountpoint}}' 2>/dev/null || true)
if [[ -n "$DST_VOLUME" && -d "$DST_VOLUME" ]]; then
    tar czf "$BACKUP_DIR/dst_${DATE}.tar.gz" -C "$DST_VOLUME" .
    mc cp "$BACKUP_DIR/dst_${DATE}.tar.gz" "${MINIO_ALIAS}/${MINIO_BUCKET}/dst/"
    echo ">> DST backup uploaded: dst_${DATE}.tar.gz"
else
    echo ">> WARN: DST volume not found, skipping"
fi

# ── Cleanup old backups ──────────────────────────────────────────────────────
echo ">> Cleaning up backups older than ${KEEP_DAYS} days..."
mc rm --recursive --force --older-than "${KEEP_DAYS}d" "${MINIO_ALIAS}/${MINIO_BUCKET}/minecraft/" 2>/dev/null || true
mc rm --recursive --force --older-than "${KEEP_DAYS}d" "${MINIO_ALIAS}/${MINIO_BUCKET}/dst/" 2>/dev/null || true

# ── Cleanup temp files ───────────────────────────────────────────────────────
rm -rf "$BACKUP_DIR"

echo ">> Backup complete!"
