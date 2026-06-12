#!/bin/sh

LOCK=/tmp/screenshot.lock

if ! mkdir "$LOCK" 2>/dev/null; then
  exit 1
fi

trap 'rmdir "$LOCK"' EXIT

BASE=~/Pictures/Screenshots/"Screenshot from $(date +"%Y-%m-%d %H-%M-%S")"
FILE="$BASE.png"
n=1

while [ -e "$FILE" ]; do
  FILE="$BASE-$n.png"
  n=$((n + 1))
done

if [ "$1" = "fullscreen" ]; then
  grim "$FILE"
else
  GEOM=$(slurp) || exit 1
  grim -g "$GEOM" "$FILE"
fi

rmdir "$LOCK"
trap - EXIT

wl-copy -t image/png <"$FILE"

ACTION=$(notify-send -i "$FILE" "Screenshot captured" "$FILE" \
  -A "default=View in Files" \
  -A "open=Open" \
  -A "delete=Delete")

if [ "$ACTION" = "default" ]; then
  gdbus call --session \
    --dest org.freedesktop.FileManager1 \
    --object-path /org/freedesktop/FileManager1 \
    --method org.freedesktop.FileManager1.ShowItems \
    "['file://$FILE']" ""
elif [ "$ACTION" = "open" ]; then
  xdg-open "$FILE"
elif [ "$ACTION" = "delete" ]; then
  rm "$FILE"
fi
