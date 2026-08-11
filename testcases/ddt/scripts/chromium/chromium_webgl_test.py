import argparse
import atexit
import pathlib
import shutil
import subprocess
import sys
import time

import chromium_cdp_util

BACKENDS         = ("gles-egl", "vulkan")
DESKTOP_PATH     = pathlib.Path("/usr/share/wayland-sessions/weston.desktop")
OLD_DESKTOP_PATH = DESKTOP_PATH.with_suffix(DESKTOP_PATH.suffix + ".old")
TEST_URL         = "https://webglsamples.org/aquarium/aquarium.html"
CHROMIUM_PACKAGE = "chromium-ozone-wayland"
STARTUP_DELAY    = 20
MEASURE_SECONDS  = 10
NUM_SAMPLES      = 50
FPS_MIN          = 30


def _run(cmd, error):
    if subprocess.run(cmd, shell=True, check=False).returncode != 0:
        print(error)
        sys.exit(1)


def test_setup(register_cleanup=True):
    """Restart weston in debug mode and install chromium"""
    shutil.copy2(DESKTOP_PATH, OLD_DESKTOP_PATH)

    if register_cleanup:
        atexit.register(clean_up)

    _run(f"sed -i 's|Exec=.*|& --debug|' {DESKTOP_PATH}", "Unable to switch weston into debug mode")
    _run("systemctl restart emptty", "Failed to restart emptty")
    subprocess.run("opkg update", shell=True, check=False)
    _run(f"opkg install {CHROMIUM_PACKAGE}", "Failed to install chromium")


def measure_fps(backend):
    """Launch Chromium, measure WebGL FPS via CDP, return average FPS."""
    cmd_sub = "; ".join((
        "export https_proxy=http://webproxy.ext.ti.com:80",
        "export WAYLAND_DISPLAY=/run/user/1000/wayland-1",
        f'chromium --use-angle={backend} "{TEST_URL}" --start-fullscreen --no-first-run --remote-debugging-port=9222 --remote-allow-origins=*',
    ))

    with subprocess.Popen(f"su -l weston -c '{cmd_sub}'", shell=True) as chrome:
        try:
            chrome.wait(timeout=1)
        except subprocess.TimeoutExpired:
            pass
        if chrome.returncode is not None:
            print("Chromium failed to start")
            sys.exit(1)

        try:
            ws_url = chromium_cdp_util.get_page_ws_url()
            with chromium_cdp_util.CDPClient(ws_url) as cdp:
                return chromium_cdp_util.measure_webgl_fps(cdp, STARTUP_DELAY, MEASURE_SECONDS, NUM_SAMPLES)
        except Exception as e:
            print(f"ERROR: Failed to measure FPS: {e}")
            sys.exit(1)
        finally:
            chrome.terminate()


def clean_up():
    """Restore the weston session files"""
    print("Cleaning up")
    shutil.move(OLD_DESKTOP_PATH, DESKTOP_PATH)
    subprocess.run("systemctl restart emptty", shell=True, check=False)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("backend", help="specify the chromium backend to use", choices=BACKENDS)
    args = parser.parse_args()

    test_setup()

    avg_fps = measure_fps(args.backend)
    print(f"FPS_AVERAGE: {avg_fps:.1f} FPS_AVERAGE")

    if avg_fps < FPS_MIN:
        print(f"FAIL: {avg_fps:.1f} fps below threshold {FPS_MIN}")
        sys.exit(1)

    print("PASS")


if __name__ == "__main__":
    main()
