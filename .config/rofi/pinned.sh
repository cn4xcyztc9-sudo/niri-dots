#!/usr/bin/env bash

PINNED=(
    "VS Code|code"
    "Firefox|firefox"
    "Files|org.gnome.Nautilus"
    "Lutris|net.lutris.Lutris"
    "Music|org.gnome.Lollypop"
)

get_icon() {
    local desktop="$1"
    local search_dirs=(
        "$HOME/.local/share/applications"
        "/usr/share/applications"
        "/var/lib/flatpak/exports/share/applications"
        "$HOME/.local/share/flatpak/exports/share/applications"
    )
    for dir in "${search_dirs[@]}"; do
        local file="$dir/$desktop.desktop"
        if [[ -f "$file" ]]; then
            grep -m1 "^Icon=" "$file" | cut -d= -f2
            return
        fi
    done
}

if [[ -n "$1" ]]; then
    for entry in "${PINNED[@]}"; do
        label="${entry%%|*}"
        desktop="${entry##*|}"
        if [[ "$label" == "$1" ]]; then
            setsid gtk-launch "$desktop" >/dev/null 2>&1 &
            exit 0
        fi
    done
    exit 1
fi

for entry in "${PINNED[@]}"; do
    label="${entry%%|*}"
    desktop="${entry##*|}"
    icon=$(get_icon "$desktop")
    if [[ -n "$icon" ]]; then
        echo -e "$label\0icon\x1f$icon"
    else
        echo "$label"
    fi
done
