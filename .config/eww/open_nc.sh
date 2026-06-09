#!/bin/sh

if [ "$(eww get nc_open)" = "true" ]; then
    eww update nc_open=false unrevealer_open=false
else
    eww update unrevealer_open=true cc_open=false nc_open=true
    sleep 0.3 && ydotool mousemove -a -x 1548 -y 674
fi
