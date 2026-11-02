#!/bin/bash
set -e

echo "─────────────────────────────────────────"
echo "  StreamFab / Wine / noVNC Container"
echo "─────────────────────────────────────────"

PUID="${PUID:-1000}"
PGID="${PGID:-1000}"

# ── 1. User auf PUID/PGID mappen ─────────────────────────────────────────────
echo "[1/7] Mapping user 'fab' to ${PUID}:${PGID}..."
groupmod -o -g "$PGID" fab
usermod -o -u "$PUID" -g "$PGID" fab

mkdir -p /config/home /config/installer /config/vpn/uk /config/vpn/us /config/vpn/au /downloads
chown fab:fab /config /config/home /config/installer /config/vpn /config/vpn/*
chmod 700 /config/vpn

# Bestehendes Prefix/Home gehören einem anderen User (z. B. nach PUID-Änderung) → einmalig korrigieren
for d in /config/wine /config/home; do
    if [ -d "$d" ] && [ "$(stat -c %u "$d")" != "$PUID" ]; then
        echo "      Fixing ownership of $d ..."
        chown -R fab:fab "$d"
    fi
done

if ! gosu fab test -w /downloads; then
    echo "      WARNUNG: /downloads ist für ${PUID}:${PGID} nicht beschreibbar — Rechte auf der NAS prüfen!"
fi

# ── 2. Netzwerk-Grundzustand sichern (für VPN aus) ───────────────────────────
echo "[2/7] Saving network defaults..."
mkdir -p /run/fab-vpn
cp /etc/resolv.conf /run/fab-vpn/resolv.conf.orig

rm -f /tmp/.X1-lock /tmp/.X11-unix/X1 2>/dev/null || true

# ── 3. VNC-Passwort ──────────────────────────────────────────────────────────
echo "[3/7] Setting VNC password..."
mkdir -p /root/.vnc
x11vnc -storepasswd "${VNC_PASSWORD}" /root/.vnc/passwd >/dev/null

# ── 4. Xvfb + Openbox ────────────────────────────────────────────────────────
echo "[4/7] Starting Xvfb (${SCREEN_WIDTH}x${SCREEN_HEIGHT}) + Openbox..."
Xvfb ${DISPLAY} -screen 0 ${SCREEN_WIDTH}x${SCREEN_HEIGHT}x${SCREEN_DEPTH} -ac +extension GLX +render -noreset &
sleep 2
openbox &
sleep 1

# ── 5. x11vnc (nur localhost — Zugriff ausschließlich über noVNC) ────────────
echo "[5/7] Starting x11vnc (localhost only)..."
x11vnc -display ${DISPLAY} -rfbauth /root/.vnc/passwd -rfbport ${VNC_PORT} -localhost -forever -shared -noxdamage -quiet &
sleep 1

# ── 6. noVNC + VPN-API ───────────────────────────────────────────────────────
echo "[6/7] Starting noVNC + VPN API on port ${NOVNC_PORT}..."
TIMEOUT_VALUE="${SESSION_TIMEOUT:-0}"
printf '<!DOCTYPE html>\n<html><head><meta charset="UTF-8"/>\n<script>window.location.replace("/fab.html?timeout=%s");</script>\n</head><body></body></html>\n' "${TIMEOUT_VALUE}" > /opt/novnc/index.html
python3 /opt/fab-server.py &
sleep 1

if [ -n "${VPN_START}" ] && [ "${VPN_START}" != "off" ]; then
    echo "      Connecting VPN: ${VPN_START} ..."
    /usr/local/bin/vpnctl up "${VPN_START}" >/dev/null 2>&1 || echo "      VPN-Start fehlgeschlagen — läuft direkt weiter."
fi

echo ""
echo "─────────────────────────────────────────"
echo "  ✓ Browser:  http://<nas-ip>:<port>"
echo "  ✓ User:     fab (${PUID}:${PGID})"
echo "  ✓ VPN:      ${VPN_START:-off}"
echo "─────────────────────────────────────────"
echo ""

# ── 7. StreamFab als App-User ────────────────────────────────────────────────
echo "[7/7] Starting StreamFab launcher..."
exec gosu fab env HOME=/config/home /opt/launcher.sh
