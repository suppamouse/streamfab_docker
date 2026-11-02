# 🎬 streamfab-docker

> **StreamFab (Windows) in your browser** — Wine in a container, noVNC access, one-click VPN country switching. No Windows license, no VM.

Built on the same pattern as [signal-messenger](https://github.com/suppamouse/signal-messenger): `debian:bookworm-slim` + Xvfb + Openbox + x11vnc + noVNC, with a custom web page in front.

---

## ✨ Features

- 🍷 **WineHQ Staging** (latest) — rebuilt by `update.sh`, no Windows license needed
- 🖥️ **Browser access** via noVNC, password-protected, optional session lock
- 🧙 **First-run setup** — Wine prefix, `vcrun2022`, `corefonts`, `d3dcompiler_47` and the StreamFab installer run automatically
- 🌍 **VPN country buttons** in the top bar: `Direkt` · `🇬🇧 UK` · `🇺🇸 US` · `🇦🇺 AU` · `↻ Next server`
- 👤 **PUID/PGID** — downloads belong to your NAS user, not root
- 💾 Downloads go straight to the media share (drive `D:` inside StreamFab)

---

## 🚀 Quick Start (Synology)

```bash
cd /volume1/docker
git clone https://github.com/suppamouse/streamfab_docker.git streamfab
cd streamfab
cp .env.example .env && nano .env      # password, PUID/PGID
docker compose up -d --build
```

Open **`http://<nas-ip>:6090`** (or via Traefik, see below).

### First start

1. A progress dialog sets up the Wine prefix (a few minutes).
2. You'll be asked for the installer: put the StreamFab `.exe` into
   `/volume1/docker/streamfab/config/installer/` and click **OK**.
3. Run through the installer, start StreamFab, activate your license.
4. In StreamFab settings set the output folder to **`D:\`** (= `/volume1/media/downloads/streamfabs`).

From then on StreamFab starts directly. If you close it, it restarts automatically.

---

## 🌍 VPN (ProtonVPN WireGuard)

The container has its own WireGuard client (`wireguard-go`, works on the Synology kernel). Normally it runs **without VPN**.

1. In your Proton account → **Downloads → WireGuard configuration**, create configs for a few servers per country (platform: GNU/Linux).
2. Put them into the matching folders:
   ```
   config/vpn/uk/*.conf
   config/vpn/us/*.conf
   config/vpn/au/*.conf
   ```
   Any additional folder (e.g. `config/vpn/ca/`) automatically gets its own button.
3. Reload the page. Click a country to connect to a random server of that country; **↻ Next server** picks a different one (useful when a service blocks a server).

How it works: only StreamFab's container traffic goes through the tunnel. Local networks (Traefik, LAN) stay direct. The VPN buttons are protected by the VNC password.

`VPN_START=uk` in `.env` connects automatically on container start.

---

## ⚙️ Configuration (`.env`)

| Variable          | Default | Description                                   |
|-------------------|---------|-----------------------------------------------|
| `VNC_PASSWORD`    | –       | Browser login + protects the VPN API          |
| `SESSION_TIMEOUT` | `0`     | Auto-lock after N seconds (0 = off)           |
| `PUID` / `PGID`   | `1026` / `100` | Owner of downloads and config (`id <user>`) |
| `SCREEN_WIDTH/HEIGHT` | `1600x900` | Virtual display size                  |
| `WINE_DPI`        | `96`    | Scaling: 96 / 120 / 144                       |
| `VPN_START`       | `off`   | `off` or a folder name under `config/vpn/`    |

---

## 🌐 Traefik

See [`traefik/streamfab.yml.example`](traefik/streamfab.yml.example) — a single router is enough, the VPN API runs on the same port as noVNC.

---

## 🔄 Updates

`update.sh` (Synology Task Scheduler, e.g. weekly, as root) pulls the repo, rebuilds the image with the latest Wine Staging and restarts the container. StreamFab updates itself inside the prefix.

---

## 📁 Layout

```
config/
├── wine/          Wine prefix (StreamFab, settings, license, logins)
├── home/          Home of the app user
├── installer/     Drop the StreamFab installer here
├── vpn/{uk,us,au} WireGuard .conf files
└── launcher.log   Wine/StreamFab log
```

---

## 🏗️ How It Works

```
Browser → fab-server.py (6080: noVNC + websockify + /api/vpn) → x11vnc → Xvfb → Openbox → Wine → StreamFab
                                         └→ vpnctl → wireguard-go (wg0)
```
