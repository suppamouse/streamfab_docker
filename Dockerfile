# ── Stage 1: wireguard-go (Userspace-WireGuard, Synology-Kernel hat kein WireGuard-Modul) ──
FROM golang:1-bookworm AS wireguard
RUN CGO_ENABLED=0 go install golang.zx2c4.com/wireguard@latest

# ── Stage 2: StreamFab Desktop ───────────────────────────────────────────────
FROM debian:bookworm-slim

LABEL maintainer="streamfab-docker"
LABEL description="StreamFab (Windows) via Wine + noVNC browser access, with built-in WireGuard country switcher"

ENV DEBIAN_FRONTEND=noninteractive \
    DISPLAY=:1 \
    SCREEN_WIDTH=1600 \
    SCREEN_HEIGHT=900 \
    SCREEN_DEPTH=24 \
    VNC_PORT=5900 \
    NOVNC_PORT=6080 \
    VNC_PASSWORD=changeme \
    SESSION_TIMEOUT=0 \
    WINEPREFIX=/config/wine \
    WINEDEBUG=-all \
    LANG=de_DE.UTF-8

# ── System, Display, VPN-Tools ───────────────────────────────────────────────
RUN dpkg --add-architecture i386 && \
    apt-get update && apt-get install -y --no-install-recommends \
    # Core utils
    curl wget ca-certificates gnupg procps jq locales gosu \
    # Virtual framebuffer + VNC + Window manager
    xvfb x11vnc openbox xdotool xclip \
    # noVNC / websockify
    python3 python3-pip python3-numpy \
    # Dialoge für die Ersteinrichtung
    zenity \
    # winetricks-Abhängigkeiten
    cabextract unzip p7zip-full \
    # Fonts
    fonts-liberation fonts-dejavu-core \
    # WireGuard / Routing
    wireguard-tools iproute2 \
    && sed -i 's/# de_DE.UTF-8/de_DE.UTF-8/' /etc/locale.gen && locale-gen \
    && rm -rf /var/lib/apt/lists/*

# ── Wine (WineHQ Staging, aktuellste Version) ────────────────────────────────
RUN mkdir -pm755 /etc/apt/keyrings && \
    wget -qO /etc/apt/keyrings/winehq-archive.key https://dl.winehq.org/wine-builds/winehq.key && \
    wget -qNP /etc/apt/sources.list.d/ https://dl.winehq.org/wine-builds/debian/dists/bookworm/winehq-bookworm.sources && \
    apt-get update && \
    apt-get install -y --install-recommends winehq-staging && \
    rm -rf /var/lib/apt/lists/*

# ── winetricks (aktuell von GitHub statt Debian-Paket) ───────────────────────
RUN wget -qO /usr/local/bin/winetricks https://raw.githubusercontent.com/Winetricks/winetricks/master/src/winetricks && \
    chmod +x /usr/local/bin/winetricks

# ── noVNC ────────────────────────────────────────────────────────────────────
RUN curl -fsSL https://github.com/novnc/noVNC/archive/refs/tags/v1.4.0.tar.gz \
    | tar -xz -C /opt && \
    mv /opt/noVNC-1.4.0 /opt/novnc && \
    pip3 install websockify --break-system-packages

# ── wireguard-go aus Stage 1 ─────────────────────────────────────────────────
COPY --from=wireguard /go/bin/wireguard /usr/local/bin/wireguard-go

# ── App-User (UID/GID werden beim Start auf PUID/PGID gesetzt) ───────────────
RUN groupadd -g 1000 fab && \
    useradd -u 1000 -g fab -d /config/home -s /bin/bash fab

# ── Openbox: StreamFab-Hauptfenster automatisch maximieren ───────────────────
RUN sed -i 's#</applications>#  <application class="streamfab*" type="normal"><maximized>yes</maximized></application>\n  <application name="streamfab*" type="normal"><maximized>yes</maximized></application>\n</applications>#' \
    /etc/xdg/openbox/rc.xml

# ── Eigene Dateien ───────────────────────────────────────────────────────────
COPY web/fab.html /opt/novnc/fab.html
COPY scripts/fab-server.py /opt/fab-server.py
COPY scripts/launcher.sh /opt/launcher.sh
COPY scripts/vpnctl /usr/local/bin/vpnctl
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /opt/fab-server.py /opt/launcher.sh /usr/local/bin/vpnctl /entrypoint.sh

VOLUME ["/config", "/downloads"]

EXPOSE ${NOVNC_PORT}

ENTRYPOINT ["/entrypoint.sh"]
