#!/usr/bin/env bash

#############################################################
# Volume
#############################################################

_volume_level() {
    pactl get-sink-volume "$(pactl get-default-sink)" | grep -oP '\d+(?=%)' | head -n1
}

_volume_muted() {
    pactl get-sink-mute "$(pactl get-default-sink)" | grep -q "yes" && echo "yes" || echo "no"
}

volume() {
    case "$1" in
    listen)
        _volume_level
        pactl subscribe 2>/dev/null | grep --line-buffered -E "on sink|on server" | while IFS= read -r _; do
            _volume_level
        done
        ;;
    listen-muted)
        _volume_muted
        pactl subscribe 2>/dev/null | grep --line-buffered -E "on sink|on server" | while IFS= read -r _; do
            _volume_muted
        done
        ;;
    esac
}

#############################################################
# Brightness
#############################################################

BRIGHTNESS_CACHE="$HOME/.cache/eww-brightness"
BRIGHTNESS_PENDING="/tmp/eww-brightness.pending"
BRIGHTNESS_SETTING="/tmp/eww-brightness.setting"
BRIGHTNESS_BUS_CACHE="$HOME/.cache/eww-brightness.bus"
_brightness_buses() {
    if [ -f "$BRIGHTNESS_BUS_CACHE" ]; then
        cat "$BRIGHTNESS_BUS_CACHE"
        return
    fi
    local buses
    buses=$(ddcutil detect 2>/dev/null |
        grep -oP 'I2C bus:\s+/dev/i2c-\K[0-9]+')
    if [ -z "$buses" ]; then
        echo "Error: ddcutil could not detect any display bus" >&2
        return 1
    fi
    echo "$buses" >"$BRIGHTNESS_BUS_CACHE"
    echo "$buses"
}
brightness() {
    case "$1" in
    set)
        local val buses
        buses=$(_brightness_buses) || return 1
        val=$(printf '%.0f' "$2")
        echo "$val" >"$BRIGHTNESS_CACHE"
        echo "$val" >"$BRIGHTNESS_PENDING"
        [ -f "$BRIGHTNESS_SETTING" ] && return
        touch "$BRIGHTNESS_SETTING"
        (
            trap 'rm -f "$BRIGHTNESS_SETTING"' EXIT
            while true; do
                local v
                v=$(cat "$BRIGHTNESS_PENDING")
                while IFS= read -r bus; do
                    ddcutil --bus "$bus" setvcp 10 "$v"
                done <<<"$buses"
                new=$(cat "$BRIGHTNESS_PENDING")
                [ "$new" = "$v" ] && break
            done
        ) &
        ;;
    daemon)
        while true; do
            if [ ! -f "$BRIGHTNESS_SETTING" ]; then
                local buses first_bus val
                buses=$(_brightness_buses) || { sleep 5; continue; }
                first_bus=$(echo "$buses" | head -1)
                val=$(ddcutil --bus "$first_bus" getvcp 10 --json 2>/dev/null |
                    grep -oP '"current":\s*\K[0-9]+')
                [ -n "$val" ] && echo "$val" >"$BRIGHTNESS_CACHE"
            fi
            sleep 30
        done
        ;;
    save)
        cp "$BRIGHTNESS_CACHE" "${BRIGHTNESS_CACHE}.saved" 2>/dev/null
        ;;
    restore)
        local val
        val=$(cat "${BRIGHTNESS_CACHE}.saved" 2>/dev/null) || return 1
        echo "$val" >"$BRIGHTNESS_CACHE"
        brightness set "$val"
        echo "$val"
        ;;
    detect)
        rm -f "$BRIGHTNESS_BUS_CACHE"
        _brightness_buses
        ;;
    get | *)
        cat "$BRIGHTNESS_CACHE" 2>/dev/null || echo "50"
        ;;
    esac
}

#############################################################
# Wifi
#############################################################

wifi() {
    local hour minute signal
    hour=$(date +%H)
    minute=$(date +%M)

    if [[ ("$hour" == "04" || "$hour" == "16") && "$minute" == "20" ]]; then
        printf ""
        return
    fi

    if ! nmcli radio wifi | grep -q "enabled"; then
        printf ""
        return
    fi

    signal=$(nmcli -t -f IN-USE,SIGNAL dev wifi list --rescan no |
        awk -F: '$1 == "*" { print $2 }')
    signal=${signal:-0}

    if ((signal <= 33)); then
        printf ""
    elif ((signal <= 66)); then
        printf ""
    else
        printf ""
    fi
}

#############################################################
# Bluelight
#############################################################

BLUELIGHT_STATUS_FILE="/tmp/gammastep-active"

bluelight_toggle() {
    if pgrep -x "gammastep" >/dev/null; then
        pkill -x "gammastep"
        echo "off" >"$BLUELIGHT_STATUS_FILE"
    else
        gammastep -O 5500 &
        echo "on" >"$BLUELIGHT_STATUS_FILE"
    fi
}

bluelight_status() {
    pgrep -x "gammastep" >/dev/null && echo "on" || echo "off"
}

bluelight() {
    case "$1" in
    --toggle) bluelight_toggle ;;
    --status) bluelight_status ;;
    *)
        echo "Usage: sysinfo.sh bluelight [--toggle|--status]"
        exit 1
        ;;
    esac
}

#############################################################
# Systray
#############################################################

systray_count() {
    busctl --user get-property org.kde.StatusNotifierWatcher \
        /StatusNotifierWatcher \
        org.kde.StatusNotifierWatcher \
        RegisteredStatusNotifierItems 2>/dev/null |
        grep -o '"[^"]*"' | wc -l
}

systray() {
    trap 'kill -- -$$ 2>/dev/null' EXIT TERM INT
    systray_count
    dbus-monitor --session \
        "type='signal',interface='org.kde.StatusNotifierWatcher'" 2>/dev/null |
        grep --line-buffered \
            "member=StatusNotifierItemRegistered\|member=StatusNotifierItemUnregistered" |
        while IFS= read -r _; do
            systray_count
        done
}

#############################################################
# Usage
#############################################################

usage() {
    cat <<EOF
Usage: sysinfo.sh <module> [subcommand] [args]
Modules:
  bluelight  --toggle | --status
  brightness get | set <0-100> | daemon | save | restore | detect
  volume     listen | listen-muted
  wifi
  systray
EOF
    exit 1
}

#############################################################
# Dispatch
#############################################################

case "$1" in
bluelight)
    shift
    bluelight "$@"
    ;;
brightness)
    shift
    brightness "$@"
    ;;
volume)
    shift
    volume "$@"
    ;;
wifi) wifi ;;
systray) systray ;;
*) usage ;;
esac
