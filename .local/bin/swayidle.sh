#!/bin/sh

exec swayidle -w \
    timeout 900 'swaylock -f' \
    timeout 915 'sysinfo.sh brightness save
                  eww update brightness=1
                  sysinfo.sh brightness set 1
                  powerprofilesctl set power-saver' \
    resume 'sysinfo.sh brightness restore
                  eww update brightness=$(sysinfo.sh brightness get)
                  powerprofilesctl set performance' \
    before-sleep 'swaylock -f'
