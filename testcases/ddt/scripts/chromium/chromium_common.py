#!/usr/bin/env python3
import configparser
import pathlib
import re
import shutil
import subprocess
import sys

DESKTOP_PATH        = pathlib.Path("/usr/share/wayland-sessions/weston.desktop")
OLD_DESKTOP_PATH    = DESKTOP_PATH.with_suffix(DESKTOP_PATH.suffix + ".old")
WESTON_INI_PATH     = pathlib.Path("/etc/xdg/weston/weston.ini")
OLD_WESTON_INI_PATH = WESTON_INI_PATH.with_suffix(WESTON_INI_PATH.suffix + ".old")
CHROMIUM_PACKAGE     = "chromium-ozone-wayland"
CHROMIUM_LAUNCH_WAIT = 20  # seconds to wait after launch before checking/measuring
XDG_RUNTIME_DIR     = "/run/user/1000"
WAYLAND_DISPLAY     = "wayland-1"
CDP_PORT            = 9222
BACKENDS            = ("gles-egl", "vulkan")
PROXY               = "http://webproxy.ext.ti.com:80"


def launch_chromium(url, extra_args=None, proxy=False):
    """Launch Chromium as the weston user. Returns the Popen object."""
    env = [
        f"export XDG_RUNTIME_DIR={XDG_RUNTIME_DIR}",
        f"export WAYLAND_DISPLAY={WAYLAND_DISPLAY}",
    ]
    flags = [
        f"--proxy-server='{PROXY}'" if proxy else None,
        "--start-fullscreen",
        "--no-first-run",
        f"--remote-debugging-port={CDP_PORT}",
        "--remote-allow-origins=*",
        extra_args,
    ]
    cmd = f'chromium "{url}" ' + " ".join(f for f in flags if f)
    return subprocess.Popen(["su", "-l", "weston", "-c", "; ".join(env + [cmd])])


def _run(cmd, error):
    if subprocess.run(cmd, shell=True, check=False).returncode != 0:
        print(error, file=sys.stderr)
        sys.exit(1)


def _configure_weston():
    result = subprocess.run(["kmsprint"], capture_output=True, text=True)
    if result.returncode != 0:
        print("ERROR: Failed to run kmsprint", file=sys.stderr)
        sys.exit(1)
    match = re.search(r"Connector \d+ \(\d+\) (\S+) \(connected\)", result.stdout, re.IGNORECASE)
    if not match:
        print("ERROR: No connected display connector found", file=sys.stderr)
        sys.exit(1)
    connector = match.group(1)

    cfg = configparser.ConfigParser()
    cfg.optionxform = str  # preserve key case (panel-position, not panel_position)
    cfg.read(WESTON_INI_PATH)

    cfg.setdefault("output", {})
    cfg["output"]["name"] = connector
    cfg["output"]["mode"] = "1920x1080@60"

    cfg.setdefault("shell", {})
    cfg["shell"]["panel-position"] = "none"
    cfg["shell"]["panel-location"] = '""'

    with open(WESTON_INI_PATH, "w") as f:
        cfg.write(f, space_around_delimiters=False)


def setup(configure_weston=True):
    """Backup weston desktop, enable debug mode, restart emptty, and install chromium."""
    if configure_weston:
        _configure_weston()
    shutil.copy2(DESKTOP_PATH, OLD_DESKTOP_PATH)
    shutil.copy2(WESTON_INI_PATH, OLD_WESTON_INI_PATH)
    _run(f"sed -i 's|Exec=.*|& --debug|' {DESKTOP_PATH}", "Unable to switch weston into debug mode")
    _run("systemctl restart emptty", "Failed to restart emptty")
    subprocess.run("opkg update", shell=True, check=False)
    _run(f"opkg install {CHROMIUM_PACKAGE}", "Failed to install chromium")


def cleanup():
    """Kill chromium and restore the weston session files."""
    print("Cleaning up")
    subprocess.run(["pkill", "-f", "chromium-bin"], check=False)
    shutil.move(OLD_DESKTOP_PATH, DESKTOP_PATH)
    shutil.move(OLD_WESTON_INI_PATH, WESTON_INI_PATH)
    subprocess.run("systemctl restart emptty", shell=True, check=False)
