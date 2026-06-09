#!/usr/bin/env bash

set -euo pipefail

CACHE="$HOME/.cache/cover_art"
LINK="$CACHE/cover.png"
MUSIC_DIR="$HOME/Music"
CACHE_FILE="$CACHE/current_track"

mkdir -p "$CACHE"

get_player() {
    if playerctl -p playerctld status &>/dev/null; then
        echo "playerctld"
        return
    fi

    local player=""

    player=$(
        playerctl -l 2>/dev/null | grep -vi firefox | while read -r p; do
            status=$(playerctl -p "$p" status 2>/dev/null || true)
            [[ "$status" == "Playing" ]] && echo "$p"
        done | head -n1
    )

    [[ -z "$player" ]] &&
        player=$(playerctl -l 2>/dev/null | grep -vi firefox | head -n1)

    echo "$player"
}

process_artwork() {
    local url="$1"
    local title="$2"

    if [[ $url == http* ]]; then
        curl -sfL "$url" -o "$LINK" 2>/dev/null || true

    elif [[ $url == file://* ]]; then
        local file_path="${url#file://}"
        file_path=$(printf '%b' "${file_path//%/\\x}")

        if [[ -f "$file_path" ]]; then
            cp "$file_path" "$LINK" 2>/dev/null || true
        fi

    else
        local music_file
        music_file=$(
            find "$MUSIC_DIR" -type f \
                \( -iname "*.mp3" -o -iname "*.m4a" -o -iname "*.flac" \) \
                -iname "*$title*" \
                -print -quit 2>/dev/null
        )

        if [[ -n "$music_file" && -f "$music_file" ]]; then
            ffmpeg -loglevel quiet \
                -i "$music_file" \
                -an \
                -vf scale=200:200 \
                -y "$LINK" 2>/dev/null || true
        fi
    fi
}

follow_track() {
    playerctl --follow metadata \
        --format '{{playerName}}|{{mpris:artUrl}}|{{title}}|{{artist}}' 2>/dev/null |
        while IFS='|' read -r player url title artist; do

            if [[ "$player" =~ [Ff]irefox ]]; then

                if ! playerctl -l 2>/dev/null | grep -qvi firefox; then
                    printf '{"artUrl":"","title":"","artist":""}\n'
                fi
                continue
            fi

            local cached_track=""
            [[ -f "$CACHE_FILE" ]] && cached_track=$(<"$CACHE_FILE")

            local current_track="$url|$title"

            if [[ "$current_track" != "$cached_track" || ! -f "$LINK" ]]; then
                process_artwork "$url" "$title"
                echo "$current_track" >"$CACHE_FILE"
            fi

            printf '{"artUrl":"%s","title":"%s","artist":"%s"}\n' \
                "$LINK" "${title:-}" "${artist:-}"
        done
}

player_cmd() {
    local player
    player=$(get_player)
    [[ -z "$player" ]] && exit 0
    playerctl -p "$player" "$@"
}

follow_player_state() {
    local last=""

    while true; do
        local player status shuffle

        player=$(playerctl -l 2>/dev/null | grep -vi firefox | head -n1)

        if [[ -n "$player" ]]; then
            status=$(playerctl -p "$player" status 2>/dev/null || echo "Stopped")
            shuffle=$(playerctl -p "$player" shuffle 2>/dev/null || echo "Off")
        else
            status="Stopped"
            shuffle="Off"
        fi

        local current
        current=$(printf '{"status":"%s","shuffle":"%s"}' "$status" "$shuffle")

        [[ "$current" != "$last" ]] && {
            echo "$current"
            last="$current"
        }

        sleep 1
    done
}

follow_timeline() {
    playerctl --follow metadata \
        --format '{{playerName}}|{{duration(position)}} / {{duration(mpris:length)}}' |
        while IFS='|' read -r player timeline; do
            [[ "$player" =~ [Ff]irefox ]] && continue
            echo "$timeline"
        done
}

cmd="${1:-track}"

case "$cmd" in
player)
    get_player
    ;;

track)
    follow_track
    ;;

player-state)
    follow_player_state
    ;;

timeline)
    follow_timeline
    ;;

play-pause | previous | next)
    player_cmd "$cmd"
    ;;

shuffle-toggle)
    player_cmd shuffle toggle
    ;;

*)
    printf \
        'Usage: %s [player|track|player-state|timeline|play-pause|previous|next|shuffle-toggle]\n' \
        "${0##*/}" >&2

    exit 1
    ;;
esac
