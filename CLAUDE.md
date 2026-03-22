# GameServers

Game servers running on turtleServer (ssh turtleServer) via Podman + Quadlet.

## Architecture

- **Minecraft**: Java Edition using `itzg/minecraft-server` with AUTOPAUSE (pauses JVM when no players connected)
- **Don't Starve Together**: Using `jamesits/dst-server` with `pause_when_empty = true`
- **Infrastructure**: Podman containers managed as systemd user services via Quadlet files
- **CI/CD**: GitHub Actions with self-hosted runner on turtleServer

## Deployment

Push to `main` triggers deploy via GitHub Actions:

1. Self-hosted runner pulls latest code
2. Copies quadlet files to `~/.config/containers/systemd/`
3. Substitutes `__ENV_FILE__` with actual path
4. Reloads systemd and restarts services

Manual deploy: `bash deploy.sh`

## Secrets (GitHub Actions)

| Secret | Purpose |
|--------|---------|
| `GS_MINECRAFT_RCON_PASSWORD` | RCON remote admin password |
| `GS_MINECRAFT_OPS` | Comma-separated operator usernames |
| `GS_DST_CLUSTER_TOKEN` | Klei account cluster token |
| `GS_DST_CLUSTER_PASSWORD` | Server password (optional, empty = public) |

## Quick Setup Secrets (required)

Only two secrets are strictly required to deploy:
- `GS_MINECRAFT_RCON_PASSWORD` - generate with `openssl rand -hex 16`
- `GS_DST_CLUSTER_TOKEN` - from Klei account page

## Ports

| Service | Port | Protocol |
|---------|------|----------|
| Minecraft | 25565 | TCP |
| Minecraft RCON | 25575 | TCP |
| DST Master | 11000 | UDP |
| DST Caves | 11001 | UDP |

## Monitoring

```bash
# Check service status
systemctl --user status gameservers-minecraft
systemctl --user status gameservers-dst

# View logs
journalctl --user -u gameservers-minecraft -f
journalctl --user -u gameservers-dst -f

# Minecraft RCON
podman exec -i gameservers-minecraft rcon-cli
```

## File Structure

```
quadlet/               # Systemd Quadlet files
  gameservers.network
  gameservers-minecraft.container
  gameservers-minecraft-data.volume
  gameservers-dst.container
  gameservers-dst-data.volume
config/
  dst/
    cluster.ini        # DST cluster configuration
    Master/server.ini  # DST Master shard config
    Caves/server.ini   # DST Caves shard config
deploy.sh              # Deployment script
.github/workflows/     # CI/CD
```
