#!/bin/sh

if [ "$(eww get cc_open)" = "true" ]; then
    eww update cc_open=false unrevealer_open=false
else
    eww update unrevealer_open=true nc_open=false cc_open=true
    sleep 0.3 && ydotool mousemove -a -x 1548 -y 764
fi
