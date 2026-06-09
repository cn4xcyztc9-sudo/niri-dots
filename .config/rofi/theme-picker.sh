#!/usr/bin/env bash

THEMES=(untitled nord nord-light everforest everforest-light)

CHOSEN=$(
  printf '%s\n' "${THEMES[@]}" |
    rofi -dmenu -config ~/.config/rofi/theme.rasi
)

[[ -z "$CHOSEN" ]] && exit 0

theme-switcher "$CHOSEN"