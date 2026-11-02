#!/bin/bash
# ─────────────────────────────────────────────────────────────
#  streamfab-docker — Auto Update Script
#  Für den Synology Aufgabenplaner (z. B. wöchentlich)
#  Baut das Image neu → aktuelles Wine Staging + winetricks.
#  StreamFab selbst aktualisiert sich innerhalb des Prefix.
# ─────────────────────────────────────────────────────────────

APP_DIR="/volume1/docker/streamfab"
LOG_FILE="/volume1/docker/streamfab/update.log"

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

log "════════════════════════════════════════"
log "  StreamFab Docker Update gestartet"
log "════════════════════════════════════════"

# ── 1. In App-Verzeichnis wechseln ───────────────────────────
cd "$APP_DIR" || { log "FEHLER: Verzeichnis $APP_DIR nicht gefunden."; exit 1; }

# Git ownership fix (Task Scheduler läuft als root)
git config --global --add safe.directory "$APP_DIR" 2>/dev/null || true

# ── 2. Änderungen aus GitHub holen (falls vorhanden) ─────────
log "→ Prüfe GitHub auf Änderungen..."
git fetch origin main >> "$LOG_FILE" 2>&1

LOCAL=$(git rev-parse HEAD)
REMOTE=$(git rev-parse origin/main)

if [ "$LOCAL" != "$REMOTE" ]; then
    log "→ Neue Version im Repo gefunden, aktualisiere..."
    git pull origin main >> "$LOG_FILE" 2>&1
else
    log "→ Kein Update im Repo – baue trotzdem neu (Wine-Update)."
fi

# ── 3. Image neu bauen ────────────────────────────────────────
log "→ Baue Image neu mit aktuellstem Wine Staging..."
docker compose build --no-cache >> "$LOG_FILE" 2>&1
if [ $? -ne 0 ]; then
    log "FEHLER: docker build fehlgeschlagen. Container läuft noch mit alter Version."
    exit 1
fi

# ── 4. Container neu starten ──────────────────────────────────
log "→ Starte Container mit neuem Image..."
docker compose up -d >> "$LOG_FILE" 2>&1
if [ $? -ne 0 ]; then
    log "FEHLER: docker compose up fehlgeschlagen."
    exit 1
fi

# ── 5. Alte Images aufräumen ──────────────────────────────────
log "→ Räume alte Images auf..."
docker image prune -f >> "$LOG_FILE" 2>&1

# ── 6. Fertig ─────────────────────────────────────────────────
log "✓ Update erfolgreich abgeschlossen!"
log "════════════════════════════════════════"
