#!/usr/bin/python

# juminai @ github

import sys
sys.dont_write_bytecode = True

import gi
import datetime
import os
import typing
import json
import subprocess
import dbus
import dbus.service
from iconfetch import fetch

gi.require_version("GdkPixbuf", "2.0")
gi.require_version("Gtk", "3.0")

# Taken from Juminai (and slightly modified)
# Hi I'm Failed and I just stole this from tokyobot
# Same lol

from dbus.mainloop.glib import DBusGMainLoop
from gi.repository import GLib # type: ignore
from gi.repository import Gtk, GdkPixbuf # type: ignore
from html.parser import HTMLParser

log_file = os.path.expandvars("/tmp/eww/notifications.json")
cache_dir = os.path.expandvars("/tmp/eww/notifications_img")

os.makedirs(cache_dir, exist_ok=True)

active_popups = {}
MAX_NOTIFICATIONS = 50

def clean_text(text):
    class HTMLTagStripper(HTMLParser):
        def __init__(self):
            super().__init__()
            self.reset()
            self.strict = False
            self.convert_charrefs = True
            self.text = []

        def handle_data(self, data):
            self.text.append(data)

        def get_text(self):
            return "".join(self.text)

    stripper = HTMLTagStripper()
    stripper.feed(text)
    return stripper.get_text().strip()

def resize_image(path, id, max_size=512):
    try:
        cached = f"{cache_dir}/{id}_img.png"
        pixbuf = GdkPixbuf.Pixbuf.new_from_file_at_scale(path, max_size, max_size, True)
        pixbuf.savev(cached, "png")
        return cached
    except Exception:
        return path

class NotificationDaemon(dbus.service.Object):
    def __init__(self):
        bus_name = dbus.service.BusName("org.freedesktop.Notifications", dbus.SessionBus())
        dbus.service.Object.__init__(self, bus_name, "/org/freedesktop/Notifications")
        self.dnd = self.read_log_file()["dnd"]

    @dbus.service.method("org.freedesktop.Notifications", in_signature="susssasa{sv}i", out_signature="u")
    def Notify(self, app_name, replaces_id, app_icon, summary, body, actions, hints, timeout=-1):
        current = self.read_log_file()
        notifications = current.get("notifications", [])

        if int(replaces_id) != 0:
            id = int(replaces_id)
            notifications = [n for n in notifications if n["id"] != id]
            
            # Clean up old popup and timer if replacing
            current["popups"] = [n for n in current.get("popups", []) if n["id"] != id]
            if id in active_popups:
                GLib.source_remove(active_popups.pop(id))
        else:
            id = notifications[0]["id"] + 1 if notifications else 1

        actions = list(actions)
        acts = [[str(actions[i]), str(actions[i + 1])] for i in range(0, len(actions), 2)]

        details = {
            "id": id,
            "app": app_name or None,
            "summary": clean_text(summary) or None,
            "body": clean_text(body) or None,
            "time": datetime.datetime.now().strftime("%H:%M"),
            "actions": acts,
            "icon": fetch(app_name),
        }

        if app_icon.strip():
            if os.path.isfile(app_icon) or app_icon.startswith("file://"):
                details["image"] = app_icon
            else:
                details["image"] = self.get_gtk_icon(app_icon)
        else:
            details["image"] = None

        if "image-data" in hints:
            details["image"] = f"{cache_dir}/{details['id']}.png"
            self.save_img_byte(hints["image-data"], details["image"])
        elif "image-path" in hints:
            raw_path = str(hints["image-path"])
            if os.path.isfile(raw_path) or raw_path.startswith("file://"):
                details["image"] = resize_image(raw_path, details["id"])
            else:
                details["image"] = None

        is_transient = bool(hints.get("transient", False))

        if not is_transient:
            notifications.insert(0, details)
            if len(notifications) > MAX_NOTIFICATIONS:
                evicted = notifications[MAX_NOTIFICATIONS:]
                notifications = notifications[:MAX_NOTIFICATIONS]
                for old in evicted:
                    self._cleanup_image_cache(old["id"])
            current["notifications"] = notifications
            current["count"] = len(notifications)

        if not self.dnd:
            popups = current.get("popups", [])
            if len(popups) >= 3:
                oldest = popups.pop()
                if oldest["id"] in active_popups:
                    GLib.source_remove(active_popups.pop(oldest["id"]))
            popups.insert(0, details)
            current["popups"] = popups

        self.write_log_file(current)

        if not self.dnd:
            active_popups[id] = GLib.timeout_add_seconds(6, self.DismissPopup, id)

        return id

    @dbus.service.method("org.freedesktop.Notifications", in_signature="", out_signature="ssss")
    def GetServerInformation(self):
        return ("eww notification daemon", "klyn", "1.0", "1.2")
    
    @dbus.service.method("org.freedesktop.Notifications", in_signature="", out_signature="as")
    def GetCapabilities(self):
        return ('actions', 'body', 'icon-static', 'persistence')
    
    @dbus.service.signal("org.freedesktop.Notifications", signature="us")
    def ActionInvoked(self, id, action):
        return (id, action)

    @dbus.service.method("org.freedesktop.Notifications", in_signature="us", out_signature="")
    def InvokeAction(self, id, action):
        self.ActionInvoked(id, action)
        self.CloseNotification(id)

    @dbus.service.signal("org.freedesktop.Notifications", signature="uu")
    def NotificationClosed(self, id, reason):
        return (id, reason)

    @dbus.service.method("org.freedesktop.Notifications", in_signature="u", out_signature="")
    def CloseNotification(self, id):
        current = self.read_log_file()
        current["notifications"] = [n for n in current["notifications"] if n["id"] != id]
        current["count"] = len(current["notifications"])
        current["popups"] = [n for n in current.get("popups", []) if n["id"] != id]

        self.write_log_file(current)
        self.NotificationClosed(id, 2)
        
        if id in active_popups:
            GLib.source_remove(active_popups.pop(id))
        self._cleanup_image_cache(id)

    @dbus.service.method("org.freedesktop.Notifications", in_signature="", out_signature="")
    def ToggleDND(self):
        self.dnd = not self.dnd
        self.update_dnd_state()

    @dbus.service.method("org.freedesktop.Notifications", in_signature="", out_signature="")
    def GetDNDState(self):
        return self.dnd

    def update_dnd_state(self):
        current = self.read_log_file()
        current["dnd"] = self.dnd
        self.write_log_file(current)

    def get_gtk_icon(self, icon_name):
        theme = Gtk.IconTheme.get_default()
        icon_info = theme.lookup_icon(icon_name, 128, 0)
        if icon_info is not None:
            return icon_info.get_filename()

    def save_img_byte(self, px_args: typing.Sequence, save_path: str):
        GdkPixbuf.Pixbuf.new_from_bytes(
            width=px_args[0],
            height=px_args[1],
            has_alpha=px_args[3],
            data=GLib.Bytes(px_args[6]),
            colorspace=GdkPixbuf.Colorspace.RGB,
            rowstride=px_args[2],
            bits_per_sample=px_args[4],
        ).savev(save_path, "png")

    def _cleanup_image_cache(self, notif_id):
        for suffix in ("", "_img"):
            path = os.path.join(cache_dir, f"{notif_id}{suffix}.png")
            try:
                os.remove(path)
            except FileNotFoundError:
                pass

    def write_log_file(self, data):
        output_json = json.dumps(data)
        print(output_json)

        tmp = log_file + ".tmp"
        with open(tmp, "w") as f:
            f.write(output_json)
        os.replace(tmp, log_file)

    def read_log_file(self):
        try:
            with open(log_file, "r") as log:
                return json.load(log)
        except (FileNotFoundError, json.JSONDecodeError):
            with open(log_file, "w") as log:
                initial_data = {"count": 0, "dnd": False, "notifications": [], "popups": []}
                json.dump(initial_data, log)
            return initial_data

    @dbus.service.method("org.freedesktop.Notifications", in_signature="", out_signature="")
    def ClearAll(self):
        for notify in self.read_log_file()["notifications"]:
            self.NotificationClosed(notify["id"], 2)
            self._cleanup_image_cache(notify["id"])
            
        for timer_id in active_popups.values():
            GLib.source_remove(timer_id)
        active_popups.clear()
        
        empty = {"count": 0, "dnd": self.dnd, "notifications": [], "popups": []}
        self.write_log_file(empty)

    @dbus.service.method("org.freedesktop.Notifications", in_signature="u", out_signature="")
    def DismissPopup(self, id):
        global active_popups

        current = self.read_log_file()
        current["popups"] = [n for n in current["popups"] if n["id"] != id]
        self.write_log_file(current)

        active_popups.pop(id, None)

def main():
    DBusGMainLoop(set_as_default=True)
    loop = GLib.MainLoop()
    NotificationDaemon()
    try:
        loop.run()
    except KeyboardInterrupt:
        exit(0)

if __name__ == "__main__":
    main()
