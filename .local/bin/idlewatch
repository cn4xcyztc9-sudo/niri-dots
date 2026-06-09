#!/usr/bin/env bash

APPS=(
    "celluloid"
    "\.exe$"
)

INTERVAL=3
INHIBIT_PID=""

inhibit() {
    [[ -n "$INHIBIT_PID" ]] && return
    systemd-inhibit \
        --what=idle \
        --who="inhibit-idle" \
        --why="App or media playback active" \
        sleep infinity &
    INHIBIT_PID=$!
}

release() {
    [[ -z "$INHIBIT_PID" ]] && return
    kill "$INHIBIT_PID" 2>/dev/null
    wait "$INHIBIT_PID" 2>/dev/null
    INHIBIT_PID=""
}

cleanup() {
    release
    exit 0
}

trap cleanup SIGTERM SIGINT

while true; do
    should_inhibit=false

    for app in "${APPS[@]}"; do
        if pgrep "$app" &>/dev/null; then
            should_inhibit=true
            break
        fi
    done

    if ! $should_inhibit; then
        if playerctl --all-players status 2>/dev/null | grep -q "^Playing$"; then
            should_inhibit=true
        fi
    fi

    if $should_inhibit; then
        inhibit
    else
        release
    fi

    sleep "$INTERVAL"
done