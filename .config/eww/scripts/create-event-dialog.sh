#!/usr/bin/env bash

set -euo pipefail

CALENDAR_SCRIPT="$HOME/.config/eww/scripts/calmanager.py"
LOG="/tmp/eww-calendar.log"

log() {
    echo "[$(date --iso-8601=seconds)] $*" >>"$LOG"
}

DATE_EXAMPLES=$(
    cat <<'EOF'
e.g. 2026-06-01 • 6/1/2026 • June 1, 2026 • tomorrow • next Friday
EOF
)

parse_date() {
    date -d "$*" "+%Y-%m-%d" 2>/dev/null
}

validate_time() {
    local input="$1"

    [[ -z "$input" ]] && return 0

    input="${input#"${input%%[![:space:]]*}"}"
    input="${input%"${input##*[![:space:]]}"}"

    if [[ "$input" =~ ^([01]?[0-9]|2[0-3]):[0-5][0-9](:[0-5][0-9])?$ ]]; then
        return 0
    fi

    if [[ "$input" =~ ^([0-9]|1[0-2]):[0-5][0-9](:[0-5][0-9])?(\ ?[AaPp][Mm])$ ]]; then
        return 0
    fi

    if [[ "$input" =~ ^([0-9]|1[0-2])(\ ?[AaPp][Mm])$ ]]; then
        return 0
    fi

    return 1
}

eww update nc_open=false unrevealer_open=false 2>/dev/null

resolve_date() {
    local input="$1"

    local parsed
    parsed=$(parse_date "$input") || return 1

    IFS='-' read -r YEAR MONTH DAY <<<"$parsed"
}

if [[ $# -gt 0 ]]; then
    if ! resolve_date "$*"; then
        zenity --error \
            --title="Calendar Error" \
            --text="Invalid date format. $DATE_EXAMPLES"
        exit 1
    fi

elif [[ -f /tmp/eww-selected-date ]]; then
    read -r saved </tmp/eww-selected-date

    if ! resolve_date "$saved"; then
        zenity --error \
            --text="Saved date is invalid, please try again." \
            --title="Calendar Error" \
            --width=400
        exit 1
    fi

else
    DATE_INPUT=$(
        zenity --entry \
            --text="$DATE_EXAMPLES"
    ) || exit 0

    if ! resolve_date "$DATE_INPUT"; then
        zenity --error --text="$DATE_EXAMPLES" \
            --title="Calendar Error" \
            --width=400
        exit 1
    fi
fi

FINAL_DATE="$YEAR-$MONTH-$DAY"
log "Opening event dialog for $FINAL_DATE"

COMBO_VALUES=$(
    python3 "$CALENDAR_SCRIPT" list-calendars 2>/dev/null |
        tr '\n' '|' |
        sed 's/|$//'
)

[[ -z "$COMBO_VALUES" ]] && COMBO_VALUES="Home"
FIRST_CAL=$(cut -d'|' -f1 <<<"$COMBO_VALUES")

SEP=$'\x1f'

EVENT_DATA=$(
    zenity --forms \
        --title="New Event on $FINAL_DATE" \
        --text="Enter event details" \
        --add-entry="Title" \
        --add-entry="Time" \
        --add-combo="Calendar" \
        --combo-values="$COMBO_VALUES" \
        --separator="$SEP" \
        --width=500
) || exit 0

[[ -z "$EVENT_DATA" ]] && exit 0

IFS="$SEP" read -r TITLE START_TIME CALENDAR <<<"$EVENT_DATA"
[[ -z "$TITLE" ]] && exit 0

CALENDAR=${CALENDAR:-$FIRST_CAL}

if ! validate_time "$START_TIME"; then
    zenity --error \
        --title="Calendar Error" \
        --width=300 \
        --text="Invalid time format.

e.g. 4:20am, 4:20 pm, 16:20, 9am, or leave blank for an all-day event."
    exit 1
fi

notify-send -e "Calendar" "Creating event '$TITLE'..."

if python3 "$CALENDAR_SCRIPT" create \
    "$YEAR" \
    "$MONTH" \
    "$DAY" \
    "$TITLE" \
    "$START_TIME" \
    "$CALENDAR"; then

    log "Event created: $TITLE on $FINAL_DATE"

    "$HOME/.config/eww/scripts/sync-events.sh" &

    notify-send \
        "New Event" \
        "'$TITLE' created successfully" \
        -a org.gnome.Calendar

else
    log "Event creation failed: $TITLE on $FINAL_DATE"

    zenity --notification \
        --text="Failed to create event"
fi
