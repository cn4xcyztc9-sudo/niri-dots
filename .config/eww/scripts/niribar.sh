#!/usr/bin/env bash

MONITOR="${NIRI_MONITOR:-DP-2}"

state_snapshot() {
    local raw_workspaces raw_window workspaces active_ws title icon
    raw_workspaces=$(niri msg -j workspaces 2>/dev/null)
    raw_window=$(niri msg -j focused-window 2>/dev/null)

    workspaces=$(printf '%s' "$raw_workspaces" | jq -c --arg mon "$MONITOR" '
        [ .[]
          | select(.output == $mon)
          | { id:    .idx,
              name:  (.idx | tostring),
              empty: .active_window_id }
        ] | sort_by(.id)
    ' 2>/dev/null)
    [[ -z "$workspaces" ]] && workspaces="[]"

    active_ws=$(printf '%s' "$raw_workspaces" | jq -r --arg mon "$MONITOR" \
        '[ .[] | select(.output == $mon and .is_active) | .idx ] | .[0] // 0' \
        2>/dev/null)
    [[ -z "$active_ws" ]] && active_ws=0

    title=$(printf '%s' "$raw_window" | jq -r '.title // ""' 2>/dev/null)
    icon=$(printf '%s' "$raw_window" | jq -r '.app_id // "application-x-executable"' 2>/dev/null)
    [[ -z "$icon" ]] && icon="application-x-executable"

    jq -cn \
        --argjson workspaces "$workspaces" \
        --argjson active_ws "$active_ws" \
        --arg title "$title" \
        --arg icon "$icon" \
        '{
            workspaces:       $workspaces,
            active_workspace: $active_ws,
            title:            $title,
            icon:             $icon
        }'
}

state() {
    local LAST="" SNAP
    SNAP=$(state_snapshot)
    echo "$SNAP"
    LAST="$SNAP"

    niri msg event-stream | while IFS= read -r _event; do
        SNAP=$(state_snapshot)
        if [[ "$SNAP" != "$LAST" ]]; then
            echo "$SNAP"
            LAST="$SNAP"
        fi
    done
}

change_window() {
    case "$1" in
    up) niri msg action focus-column-left ;;
    down) niri msg action focus-column-right ;;
    *)
        exit 1
        ;;
    esac
}

case "$1" in
state) state ;;
change-window)
    shift
    change_window "$@"
    ;;
*) ;;
esac
