#!/bin/bash
# ─────────────────────────────────────────────────────────────
#  StreamFab Launcher (läuft als User 'fab')
#  - Ersteinrichtung des Wine-Prefix
#  - Installation aus /config/installer
#  - Startet StreamFab und startet es nach dem Schließen neu
# ─────────────────────────────────────────────────────────────
set -u

export WINEPREFIX="${WINEPREFIX:-/config/wine}"
export WINEDEBUG="${WINEDEBUG:--all}"
INSTALLER_DIR=/config/installer
LOG=/config/launcher.log

# Log klein halten
if [ -f "$LOG" ] && [ "$(stat -c %s "$LOG")" -gt 5242880 ]; then
    mv -f "$LOG" "$LOG.1"
fi
log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" | tee -a "$LOG"; }

find_exe() {
    find "$WINEPREFIX/drive_c" -maxdepth 6 -type f \
        \( -iname 'StreamFab64.exe' -o -iname 'StreamFab.exe' \) 2>/dev/null | sort | head -1
}

# ── Ersteinrichtung ──────────────────────────────────────────
init_prefix() {
    log "Initialisiere Wine-Prefix in $WINEPREFIX ..."
    (
        echo "# Wine-Umgebung wird eingerichtet …"
        WINEDLLOVERRIDES="mscoree=;mshtml=" wineboot -u
        wineserver -w
        echo "# Windows-Version wird auf Windows 10 gesetzt …"
        wine winecfg -v win10
        echo "# Laufzeitbibliotheken werden installiert (vcrun2022, corefonts, d3dcompiler_47) — das dauert ein paar Minuten …"
        winetricks -q vcrun2022 corefonts d3dcompiler_47
        wineserver -w
        touch "$WINEPREFIX/.fab-initialized"
        echo "# Fertig."
    ) 2>&1 | tee -a "$LOG" | grep --line-buffered '^#' | \
        zenity --progress --pulsate --no-cancel --auto-close \
               --title="StreamFab — Ersteinrichtung" --width=520 2>/dev/null
    log "Prefix-Einrichtung abgeschlossen."
}

# ── Installation ─────────────────────────────────────────────
ensure_installed() {
    while :; do
        EXE="$(find_exe)"
        [ -n "$EXE" ] && return 0

        INST="$(find "$INSTALLER_DIR" -maxdepth 1 -type f -iname '*.exe' 2>/dev/null | sort | tail -1)"
        if [ -n "$INST" ]; then
            log "Starte Installer: $INST"
            wine "$INST" >>"$LOG" 2>&1
            wineserver -w
            mv -f "$INST" "$INST.installed"
            EXE="$(find_exe)"
            if [ -z "$EXE" ]; then
                zenity --error --width=420 --title="StreamFab" \
                    --text="Die Installation wurde beendet, aber StreamFab wurde nicht gefunden.\n\nLege den Installer erneut nach\n<b>config/installer/</b>\nund klicke auf OK." 2>/dev/null
            fi
        else
            zenity --info --width=460 --title="StreamFab — Installation" \
                --text="StreamFab ist noch nicht installiert.\n\nLege den StreamFab-Installer (.exe) auf der NAS in den Ordner\n<b>/volume1/docker/streamfab/config/installer/</b>\nund klicke dann auf <b>OK</b>." 2>/dev/null
        fi
    done
}

# ── Main ─────────────────────────────────────────────────────
if [ ! -f "$WINEPREFIX/.fab-initialized" ]; then
    init_prefix
fi

# Laufwerk D: → Download-Ordner
ln -sfn /downloads "$WINEPREFIX/dosdevices/d:"

# Optional: Skalierung (96 = 100 %, 120 = 125 %, 144 = 150 %)
if [ -n "${WINE_DPI:-}" ]; then
    wine reg add 'HKCU\Control Panel\Desktop' /v LogPixels /t REG_DWORD /d "$WINE_DPI" /f >/dev/null 2>&1
fi

while :; do
    ensure_installed
    log "Starte StreamFab: $EXE"
    cd "$(dirname "$EXE")" || cd /config/home
    wine "$EXE" >>"$LOG" 2>&1
    # Auf alle Wine-Prozesse warten (z. B. StreamFab-Selbstupdate)
    wineserver -w
    log "StreamFab beendet — Neustart in 3 s."
    sleep 3
done
