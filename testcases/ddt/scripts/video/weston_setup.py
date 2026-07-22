#!/usr/bin/env python3
import configparser
import sys

WESTON_INI = "/etc/xdg/weston/weston.ini"

def configure_weston(connector):
    cfg = configparser.ConfigParser()
    cfg.optionxform = str  # preserve key case (panel-position, not panel_position)
    cfg.read(WESTON_INI)

    if connector:
        cfg.setdefault("output", {})
        cfg["output"]["name"] = connector
        cfg["output"]["mode"] = "1920x1080@60"

    cfg.setdefault("shell", {})
    cfg["shell"]["panel-position"] = "none"
    cfg["shell"]["panel-location"] = '""'

    with open(WESTON_INI, "w") as f:
        cfg.write(f, space_around_delimiters=False)

if __name__ == "__main__":
    configure_weston(sys.argv[1] if len(sys.argv) > 1 else None)