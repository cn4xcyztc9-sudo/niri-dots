#!/usr/bin/env bash

CALENDAR_SCRIPT="$HOME/.config/eww/scripts/calmanager.py"
LOCKFILE="/tmp/eww-sync.pid"
LOGFILE="/tmp/eww-sync.log"
CALDAV_LOG_FILE="/tmp/eww-caldav.log"

if [ -f "$LOCKFILE" ] && kill -0 "$(cat "$LOCKFILE")" 2>/dev/null; then
    exit 0
fi

echo $$ >"$LOCKFILE"
eww update syncing=true sync_angle=0 >/dev/null 2>&1

spinner() {
    local angle=0
    while true; do
        angle=$(((angle + 15) % 360))
        percent=$(awk "BEGIN {print ($angle/360)*100}")
        eww update sync_angle="$percent" >/dev/null 2>&1
        sleep 0.06
    done
}

spinner &
SPINNER_PID=$!

cleanup() {
    kill "${SPINNER_PID:-0}" >/dev/null 2>&1
    rm -f "$LOCKFILE"
    eww update sync_angle=0 syncing=false >/dev/null 2>&1
}
trap cleanup EXIT

if PYTHONDONTWRITEBYTECODE=1 python3 "$CALENDAR_SCRIPT" fetch --all >>"$LOGFILE" 2>&1; then
    notify-send -e "Calendar Sync Complete" "Remote calendars have been synchronized"
else
    EXIT_CODE=$?
    cat "$CALDAV_LOG_FILE" >>"$LOGFILE" 2>/dev/null
    notify-send -e "Calendar Sync Failed" "Exit $EXIT_CODE — check $LOGFILE"
fi
