#!/bin/sh

is_inhibiting() {
    pgrep -U "$USER" -f "systemd-inhibit --what=idle" >/dev/null 2>&1
}

case "${1:-status}" in
status)
    if is_inhibiting; then printf "on\n"; else printf "off\n"; fi
    ;;
toggle)
    if is_inhibiting; then
        pkill -U "$USER" -f "systemd-inhibit --what=idle"
        printf "off\n"
    else
        nohup systemd-inhibit --what=idle --mode=block sleep infinity \
            >/dev/null 2>&1 &
        printf "on\n"
    fi
    ;;
*)
    printf "Usage: %s [status|toggle]\n" "$0" >&2
    exit 1
    ;;
esac
