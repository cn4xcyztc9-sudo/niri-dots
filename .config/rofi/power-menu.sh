#!/usr/bin/env bash

selection="${1:-}"
rofi_ret="${ROFI_RETV:-0}"
prev_selection="${ROFI_DATA:-}"

run_detached() {
    setsid "$@" >/dev/null 2>&1 &
}

needs_confirmation() {
    case "$1" in
    Logout | Suspend | Reboot | Shutdown) return 0 ;;
    *) return 1 ;;
    esac
}

if [ "$rofi_ret" = "1" ] && [ "$selection" = "Yes" ] && [ -n "$prev_selection" ]; then
    case "$prev_selection" in
    Logout) loginctl terminate-session "$XDG_SESSION_ID" ;;
    Suspend) systemctl suspend ;;
    Reboot) systemctl reboot ;;
    Shutdown) systemctl poweroff ;;
    esac
    exit 0
fi

if [ "$rofi_ret" = "1" ] && [ "$selection" = "No" ] && [ -n "$prev_selection" ]; then
    exit 0
fi

if [ "$rofi_ret" = "1" ]; then
    if needs_confirmation "$selection"; then
        echo -e "\0prompt\x1fConfirm $selection?"
        echo -e "\0message\x1fAre you sure you want to ${selection,,}?"
        echo -e "\0data\x1f$selection"
        echo -e "Yes\0icon\x1fdialog-ok"
        echo -e "No\0icon\x1fdialog-cancel"
    else
        case "$selection" in
        Lock) run_detached swaylock ;;
        System\ Resources) run_detached gtk-launch net.nokyan.Resources ;;
        esac
    fi
    exit 0
fi

echo -e "Lock\0icon\x1fsystem-lock-screen"
echo -e "Logout\0icon\x1fsystem-log-out"
echo -e "Reboot\0icon\x1fsystem-reboot"
echo -e "Shutdown\0icon\x1fsystem-shutdown"
echo -e "Suspend\0icon\x1fsystem-suspend"
echo -e "System Resources\0icon\x1futilities-system-monitor"
