#!/usr/bin/env bash
# shellcheck disable=SC2086

# Taken from Juminai

dismiss() {
    dbus-send --session --type=method_call \
        --dest=org.freedesktop.Notifications \
        /org/freedesktop/Notifications \
        org.freedesktop.Notifications.DismissPopup \
        uint32:$1
}

close() {
    dbus-send --session --type=method_call \
        --dest=org.freedesktop.Notifications \
        /org/freedesktop/Notifications \
        org.freedesktop.Notifications.CloseNotification \
        uint32:$1
}

invoke() {
    dbus-send --session --type=method_call \
        --dest=org.freedesktop.Notifications \
        /org/freedesktop/Notifications \
        org.freedesktop.Notifications.InvokeAction \
        uint32:$1 string:$2
}

clear_all() {
    dbus-send --session --type=method_call \
        --dest=org.freedesktop.Notifications \
        /org/freedesktop/Notifications \
        org.freedesktop.Notifications.ClearAll
}

toggle_dnd() {
    dbus-send --session --type=method_call \
        --dest=org.freedesktop.Notifications \
        /org/freedesktop/Notifications \
        org.freedesktop.Notifications.ToggleDND
}

show() {
    local id=$1
    local path
    path=$(jq -r --argjson id "$id" '.notifications[] | select(.id == $id) | .file_path' /tmp/eww/notifications.json)
    if [[ "$path" != "null" && -n "$path" ]]; then
        gdbus call --session --dest org.freedesktop.FileManager1 \
            --object-path /org/freedesktop/FileManager1 \
            --method org.freedesktop.FileManager1.ShowItems \
            "[\"file://$path\"]" ""
    else
        dbus-send --session --type=method_call \
            --dest=org.freedesktop.Notifications \
            /org/freedesktop/Notifications \
            org.freedesktop.Notifications.InvokeAction \
            uint32:$id string:default
    fi
}

if [[ $1 == '--dismiss' ]]; then dismiss $2; fi
if [[ $1 == '--close' ]]; then close $2; fi
if [[ $1 == '--invoke' ]]; then invoke $2 $3; fi
if [[ $1 == '--clear' ]]; then clear_all; fi
if [[ $1 == '--toggle' ]]; then toggle_dnd; fi
if [[ $1 == '--show' ]]; then show $2; fi
