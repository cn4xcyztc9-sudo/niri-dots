#!/usr/bin/env python3

import os
import json
import argparse
import calendar
from datetime import datetime, date, timedelta
import sys
import ctypes, struct, select

SELECTED_DATE_FILE = "/tmp/eww-selected-date"
CURRENT_MONTH_FILE = "/tmp/eww-calendar-month"
EVENTS_CACHE_FILE = os.path.expanduser("~/.config/eww/calendar-events.json")
CALENDAR_NAMES_FILE = os.path.expanduser("~/.config/eww/calendar-names.json")
CALDAV_LOG_FILE = "/tmp/eww-caldav.log"
CALDAV_CREDS_FILE = os.path.expanduser("~/Documents/caldav.txt")

IN_CLOSE_WRITE = 0x00000008
IN_MOVED_TO = 0x00000080


def log(msg):
    with open(CALDAV_LOG_FILE, "a") as f:
        f.write(f"[{datetime.now().isoformat()}] {msg}\n")


def load_caldav_config():
    config = {}
    try:
        with open(CALDAV_CREDS_FILE) as f:
            for line in f:
                if "=" in line:
                    key, _, value = line.partition("=")
                    config[key.strip()] = value.strip()
    except FileNotFoundError:
        log(f"CalDAV config file not found: {CALDAV_CREDS_FILE}")
        raise
    except Exception as e:
        log(f"Error reading CalDAV config: {e}")
        raise
    try:
        return config["email"], config["password"], config["url"]
    except KeyError as e:
        log(f"Missing key in iCloud config: {e}")
        raise


def get_state():
    try:
        with open(CURRENT_MONTH_FILE) as f:
            y, m = map(int, f.read().strip().split("-"))
    except:
        now = datetime.now()
        y, m = now.year, now.month
    try:
        with open(SELECTED_DATE_FILE) as f:
            sy, sm, sd = map(int, f.read().strip().split("-"))
            sel = (sy, sm, sd)
    except:
        sel = None
    return y, m, sel


def set_state(year, month, sel_date=None):
    with open(CURRENT_MONTH_FILE, "w") as f:
        f.write(f"{year:04d}-{month:02d}\n")
    if sel_date:
        with open(SELECTED_DATE_FILE, "w") as f:
            f.write(f"{sel_date[0]:04d}-{sel_date[1]:02d}-{sel_date[2]:02d}\n")


def _supports_events(cal):
    try:
        return "VEVENT" in cal.get_supported_components()
    except Exception:
        return True


def fetch_events(fetch_all=False):
    try:
        import caldav

        email, password, url = load_caldav_config()
        client = caldav.DAVClient(url=url, username=email, password=password)  # type: ignore
        principal = client.principal()

        start = (
            (datetime.now() - timedelta(days=365)).replace(day=1)
            if fetch_all
            else datetime.now().replace(day=1)
        )
        end = start + timedelta(days=730 if fetch_all else 365)

        calendars = [c for c in principal.calendars() if _supports_events(c)]

        cal_names = [c.name for c in calendars if c.name]
        tmp_names = CALENDAR_NAMES_FILE + ".tmp"
        with open(tmp_names, "w") as f:
            json.dump(cal_names, f)
        os.replace(tmp_names, CALENDAR_NAMES_FILE)

        events_data = {}
        for cal in calendars:
            for event in cal.date_search(start, end, expand=True):
                vevent = event.vobject_instance.vevent
                dt = vevent.dtstart.value
                summary = (
                    str(vevent.summary.value) if hasattr(vevent, "summary") else "Event"
                )

                event_time = None
                if isinstance(dt, datetime):
                    event_time = dt.strftime("%I:%M %p").lstrip("0")
                    dt = dt.date()

                month_key = f"{dt.year}-{dt.month:02d}"
                day_key = str(dt.day)

                events_data.setdefault(month_key, {}).setdefault(day_key, []).append(
                    {"title": summary, "time": event_time}
                )

        tmp = EVENTS_CACHE_FILE + ".tmp"
        with open(tmp, "w") as f:
            json.dump(events_data, f)
        os.replace(tmp, EVENTS_CACHE_FILE)
        return events_data

    except Exception as e:
        log(f"Fetch error: {e}")
        return None


def get_upcoming_events(raw, days=30):
    today = date.today()
    result = []
    for i in range(days + 1):
        d = today + timedelta(days=i)
        month_key = f"{d.year}-{d.month:02d}"
        day_key = str(d.day)
        for evt in raw.get(month_key, {}).get(day_key, []):
            date_str = "Today" if d == today else d.strftime("%A - %b %-d")
            result.append(
                {
                    "date": date_str,
                    "title": evt["title"] if isinstance(evt, dict) else evt,
                    "time": evt.get("time") if isinstance(evt, dict) else None,
                }
            )
    return result


def list_calendars():
    try:
        with open(CALENDAR_NAMES_FILE) as f:
            print("\n".join(json.load(f)))
    except FileNotFoundError:
        log("Calendar names cache missing — run fetch first")
        sys.exit(1)


def create_event(year, month, day, title, time_str, cal_name="Home"):
    try:
        import caldav

        email, password, url = load_caldav_config()
        client = caldav.DAVClient(url=url, username=email, password=password)  # type: ignore
        principal = client.principal()

        calendars = principal.calendars()
        target_cal = next(
            (c for c in calendars if cal_name.lower() in str(c).lower()), calendars[0]
        )

        start_dt = datetime(year, month, day)

        if time_str and ":" in time_str:
            time_str = time_str.lower()
            parts = time_str.replace("am", "").replace("pm", "").split(":")
            h, m = int(parts[0]), int(parts[1])
            if "pm" in time_str and h != 12:
                h += 12
            start_dt = start_dt.replace(hour=h, minute=m)
            end_dt = start_dt + timedelta(hours=1)
            vcal = f"""BEGIN:VCALENDAR
VERSION:2.0
BEGIN:VEVENT
DTSTAMP:{datetime.now().strftime('%Y%m%dT%H%M%SZ')}
DTSTART:{start_dt.strftime('%Y%m%dT%H%M%S')}
DTEND:{end_dt.strftime('%Y%m%dT%H%M%S')}
SUMMARY:{title}
END:VEVENT
END:VCALENDAR"""
        else:
            end_dt = start_dt + timedelta(days=1)
            vcal = f"""BEGIN:VCALENDAR
VERSION:2.0
BEGIN:VEVENT
DTSTAMP:{datetime.now().strftime('%Y%m%dT%H%M%SZ')}
DTSTART;VALUE=DATE:{start_dt.strftime('%Y%m%d')}
DTEND;VALUE=DATE:{end_dt.strftime('%Y%m%d')}
SUMMARY:{title}
END:VEVENT
END:VCALENDAR"""

        target_cal.add_event(vcal)
        return True
    except Exception as e:
        log(f"Create error: {e}")
        return False


def generate_json(year, month):
    raw = {}
    events = {}
    try:
        with open(EVENTS_CACHE_FILE) as f:
            raw = json.load(f)
            month_key = f"{year}-{month:02d}"
            if month_key in raw:
                for d, evt_list in raw[month_key].items():
                    events[(year, month, int(d))] = [
                        e["title"] if isinstance(e, dict) else e for e in evt_list
                    ]
    except:
        pass

    cal = calendar.Calendar(firstweekday=6)
    weeks = cal.monthdayscalendar(year, month)
    while len(weeks) < 6:
        weeks.append([0] * 7)

    prev_m = date(year, month, 1) - timedelta(days=1)
    next_m = (date(year, month, 28) + timedelta(days=4)).replace(day=1)
    prev_len = calendar.monthrange(prev_m.year, prev_m.month)[1]

    _, _, sel = get_state()
    today = date.today()

    out_weeks = []
    for w_i, week in enumerate(weeks):
        out_days = []
        for d_i, d in enumerate(week):
            if d == 0:
                if w_i == 0:
                    d_val = prev_len - (week[: d_i + 1].count(0) - 1)
                    curr_y, curr_m = prev_m.year, prev_m.month
                else:
                    d_val = week[: d_i + 1].count(0)
                    curr_y, curr_m = next_m.year, next_m.month
                is_filler = True
            else:
                d_val, curr_y, curr_m = d, year, month
                is_filler = False

            event_key = (curr_y, curr_m, d_val)
            has_evt = not is_filler and event_key in events
            titles = ""
            if has_evt:
                t_list = events[event_key]
                titles = "; ".join(t_list[:2]) + (
                    f" (+{len(t_list) - 2})" if len(t_list) > 2 else ""
                )

            out_days.append(
                {
                    "type": "filler" if is_filler else "day",
                    "day": d_val,
                    "is_today": (curr_y, curr_m, d_val)
                    == (today.year, today.month, today.day),
                    "has_event": has_evt,
                    "titles": titles,
                    "is_selected": (curr_y, curr_m, d_val) == sel,
                }
            )
        out_weeks.append(out_days)
    return json.dumps(
        {
            "year": year,
            "month": month,
            "weeks": out_weeks,
            "header": datetime(year, month, 1).strftime("%B %Y"),
            "upcoming": get_upcoming_events(raw),
        }
    )


_libc = ctypes.CDLL("libc.so.6", use_errno=True)


def _inotify_init():
    fd = _libc.inotify_init()
    if fd < 0:
        raise OSError(ctypes.get_errno(), "inotify_init failed")
    return fd


def _inotify_add_watch(fd, path, mask):
    wd = _libc.inotify_add_watch(fd, path.encode(), mask)
    if wd < 0:
        raise OSError(ctypes.get_errno(), f"add_watch failed: {path}")
    return wd


def _read_events(fd):
    select.select([fd], [], [])
    buf = os.read(fd, 4096)
    events, offset = [], 0
    while offset < len(buf):
        _, _, _, length = struct.unpack_from("iIII", buf, offset)
        name = buf[offset + 16 : offset + 16 + length].rstrip(b"\x00").decode()
        events.append(name)
        offset += 16 + length
    return events


def watch_mode():
    try:
        os.remove(CURRENT_MONTH_FILE)
        os.remove(SELECTED_DATE_FILE)
    except:
        pass

    print(generate_json(*get_state()[:2]), flush=True)

    fd = _inotify_init()
    mask = IN_CLOSE_WRITE | IN_MOVED_TO
    watched_basenames = {
        os.path.basename(p)
        for p in [CURRENT_MONTH_FILE, SELECTED_DATE_FILE, EVENTS_CACHE_FILE]
    }

    seen = set()
    for p in [CURRENT_MONTH_FILE, SELECTED_DATE_FILE, EVENTS_CACHE_FILE]:
        d = os.path.dirname(p)
        if d not in seen:
            os.makedirs(d, exist_ok=True)
            _inotify_add_watch(fd, d, mask)
            seen.add(d)

    while True:
        if any(name in watched_basenames for name in _read_events(fd)):
            print(generate_json(*get_state()[:2]), flush=True)


if __name__ == "__main__":
    p = argparse.ArgumentParser()
    s = p.add_subparsers(dest="cmd")
    s.add_parser("generate").add_argument("--watch", action="store_true")
    s.add_parser("fetch").add_argument("--all", action="store_true")
    s.add_parser("change-month").add_argument("dir")
    s.add_parser("list-calendars")
    sl = s.add_parser("select")
    sl.add_argument("y", type=int)
    sl.add_argument("m", type=int)
    sl.add_argument("d", type=int)
    cr = s.add_parser("create")
    cr.add_argument("y", type=int)
    cr.add_argument("m", type=int)
    cr.add_argument("d", type=int)
    cr.add_argument("t")
    cr.add_argument("time", nargs="?", default="")
    cr.add_argument("cal_name", nargs="?", default="Home")
    args = p.parse_args()

    if args.cmd == "generate":
        watch_mode() if args.watch else print(generate_json(*get_state()[:2]))
    elif args.cmd == "fetch":
        result = fetch_events(args.all)
        if result is None:
            sys.exit(1)
    elif args.cmd == "change-month":
        y, m, _ = get_state()
        m += -1 if args.dir == "up" else 1
        if m < 1:
            m, y = 12, y - 1
        elif m > 12:
            m, y = 1, y + 1
        set_state(y, m)
    elif args.cmd == "list-calendars":
        list_calendars()
    elif args.cmd == "select":
        set_state(args.y, args.m, (args.y, args.m, args.d))
    elif args.cmd == "create":
        create_event(args.y, args.m, args.d, args.t, args.time, args.cal_name)
