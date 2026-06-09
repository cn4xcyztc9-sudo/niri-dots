#!/usr/bin/env bash

set -uo pipefail

ROFI_CONFIG="$HOME/.config/rofi/audio.rasi"
BT_CONNECT_TIMEOUT=8

is_audio_bt_device() {
    local mac="$1"
    local info
    info=$(bluetoothctl info "$mac" 2>/dev/null)

    local class_hex
    class_hex=$(awk '/Class:/{print $2}' <<<"$info")
    if [[ -n "$class_hex" ]]; then
        local major=$(((class_hex >> 8) & 0x1F))
        [[ $major -eq 4 ]] && return 0
    fi

    grep -qi "UUID:.*\(Advanced Audio\|Audio Sink\|Headset\|Hands-Free\)" <<<"$info"
}

bt_is_on() {
    rfkill list bluetooth 2>/dev/null | grep -q "Soft blocked: no"
}

get_sink_description() {
    local sink_id="$1"
    pactl list sinks 2>/dev/null |
        awk "/Sink #${sink_id}/{found=1} found && /Description:/{gsub(/.*Description:[[:space:]]*/,\"\"); print; exit}"
}

move_all_streams_to() {
    local target="$1"
    while read -r stream_id; do
        pactl move-sink-input "$stream_id" "$target" 2>/dev/null || true
    done < <(pactl list short sink-inputs | awk '{print $1}')
}

notify() {
    command -v notify-send &>/dev/null && notify-send "$1" "$2"
}

declare -A sink_map
declare -A bt_device_map
choices=()
separator="-------------------------------"

current_sink=$(pactl get-default-sink 2>/dev/null)

if bt_is_on; then
    choices+=("Disable Bluetooth")
else
    choices+=("Enable Bluetooth")
fi

if bt_is_on; then
    while IFS= read -r line; do
        mac=$(awk '{print $2}' <<<"$line")
        name=$(cut -d' ' -f3- <<<"$line")
        [[ -z "$mac" || -z "$name" ]] && continue

        is_audio_bt_device "$mac" || continue

        if bluetoothctl info "$mac" 2>/dev/null | grep -q "Connected: yes"; then
            label="Disconnect: $name"
        else
            label="Connect: $name"
        fi
        choices+=("$label")
        bt_device_map["$label"]="$mac"
    done < <(bluetoothctl devices Paired 2>/dev/null)
fi

choices+=("$separator")

while IFS= read -r line; do
    sink_id=$(awk '{print $1}' <<<"$line")
    sink_name=$(awk '{print $2}' <<<"$line")
    description=$(get_sink_description "$sink_id")
    [[ -z "$description" ]] && description="$sink_name"

    display_name="$description"
    [[ "$sink_name" == "$current_sink" ]] && display_name+="  ●"

    choices+=("$display_name")
    sink_map["$display_name"]="$sink_id"
done < <(pactl list short sinks 2>/dev/null)

if [[ ${#sink_map[@]} -eq 0 ]]; then
    notify "Audio Switcher" "No audio sinks found."
    exit 1
fi

selection=$(printf '%s\n' "${choices[@]}" |
    rofi -dmenu -p "Audio Output" -i -config "$ROFI_CONFIG")

[[ -z "$selection" ]] && exit 0

case "$selection" in

"$separator")
    exec "$(realpath "$0")"
    ;;

"Enable Bluetooth" | "Disable Bluetooth")
    if bt_is_on; then
        rfkill block bluetooth
    else
        rfkill unblock bluetooth
    fi
    exec "$(realpath "$0")"
    ;;

Connect:*)
    mac="${bt_device_map[$selection]}"
    device_name="${selection#Connect: }"

    if ! bluetoothctl connect "$mac" 2>/dev/null; then
        notify "Bluetooth" "Failed to connect to $device_name"
        exit 1
    fi

    for ((i = 0; i < BT_CONNECT_TIMEOUT * 2; i++)); do
        sleep 0.5
        bt_sink_name=$(pactl list short sinks 2>/dev/null |
            awk '/bluez/{print $2; exit}')
        if [[ -n "$bt_sink_name" ]]; then
            pactl set-default-sink "$bt_sink_name"
            move_all_streams_to "$bt_sink_name"
            notify "Audio" "Switched to $device_name"
            exit 0
        fi
    done

    notify "Audio" "Connected to $device_name but no audio sink appeared"
    exit 1
    ;;

Disconnect:*)
    mac="${bt_device_map[$selection]}"
    bluetoothctl disconnect "$mac" 2>/dev/null
    exit 0
    ;;

*)
    sink_id="${sink_map[$selection]}"
    if [[ -z "$sink_id" ]]; then
        notify "Audio Switcher" "Unknown selection: $selection"
        exit 1
    fi
    pactl set-default-sink "$sink_id"
    move_all_streams_to "$sink_id"
    exit 0
    ;;
esac
