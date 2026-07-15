"""Run a webgl demo on Chromium and capture the FPS"""

import argparse
import atexit
import os
import pathlib
import re
import subprocess
import sys
import time

from PIL import Image
import pytesseract

BACKENDS = ("gles-egl", "vulkan")
DESKTOP_PATH = pathlib.Path("/usr/share/wayland-sessions/weston.desktop")
OLD_DESKTOP_PATH = DESKTOP_PATH.with_suffix(DESKTOP_PATH.suffix + ".old")
TEST_URL = "https://webglsamples.org/aquarium/aquarium.html"
CHROMIUM_PACKAGE = "chromium-ozone-wayland"


def test_setup():
    """Restart weston in debug mode and set up enviroment variables"""
    # backup and modify the session entry for weston-screenshoter
    DESKTOP_PATH.copy(OLD_DESKTOP_PATH)
    atexit.register(clean_up)

    sed = subprocess.run(
        f"sed -i 's|Exec=.*|& --debug|' {DESKTOP_PATH}", shell=True, check=False
    )
    if sed.returncode != 0:
        print("Unable to switch weston into debug mode")
        sys.exit(1)

    restart = subprocess.run("systemctl restart emptty", shell=True, check=False)
    if restart.returncode != 0:
        print("Failed to restart emptty")
        sys.exit(1)

    # this may fail depending on the sources configured
    # we care more about the next command
    subprocess.run("opkg update", shell=True, check=False)

    install = subprocess.run(
        f"opkg install {CHROMIUM_PACKAGE}", shell=True, check=False
    )
    if install.returncode != 0:
        print("Failed to install chromium")
        sys.exit(1)


def take_screenshots(backend):
    """Take screenshots utilizing weston-screenshoter"""
    os.environ["WAYLAND_DISPLAY"] = "/run/user/1000/wayland-1"
    # do not use single quotes in this string
    cmd_sub = "; ".join(
        (
            "export https_proxy=http://webproxy.ext.ti.com:80",
            "export XDG_RUNTIME_DIR=/run/user/1000",
            "export WAYLAND_DISPLAY=wayland-1",
            f'chromium --use-angle={backend} "{TEST_URL}" --start-fullscreen --no-first-run',
        )
    )
    cmd = f"su -l weston -c '{cmd_sub}'"

    with subprocess.Popen(cmd, shell=True) as chrome:
        try:
            chrome.wait(timeout=1)
        except subprocess.TimeoutExpired:
            pass
        if chrome.returncode is not None:
            sys.exit(1)

        time.sleep(15)
        print("Taking screenshots")
        for _ in range(0, 10):
            wss = subprocess.run("weston-screenshooter", shell=True, check=False)
            if wss.returncode != 0:
                print("Failed to take screenshot")
            time.sleep(1)
        print("Finished taking screenshots")

        chrome.terminate()


def process_images(png_files):
    """Use pytesseract wrapper to find fps values from the screenshots"""
    # Total seen fps
    total_fps = 0
    # Number of times fps was not found
    fps_not_found = 0
    # Number of times the fps was found
    fps_found = 0

    for image in png_files:
        with Image.open(image) as image:
            image = image.crop((20, 20, 100, 100))
            text = pytesseract.image_to_string(image, config="--psm 1")
            try:
                fps_value = int(re.search(r"fps:\s(\d+)", text).group(1))
            except (AttributeError, TypeError):
                print("No FPS value found")
                fps_not_found += 1
            else:
                print("fps seen: " + str(fps_value))
                total_fps += fps_value
                fps_found += 1

    if fps_found == 0:
        average_fps = 0
    else:
        average_fps = total_fps / fps_found

    print(f"FPS_AVERAGE: {average_fps} FPS_AVERAGE")
    print(f"The number of successful fps detections: {fps_found}")
    print(f"The number of unsuccessful fps detections: {fps_not_found}")

    get_test_execution_result(fps_not_found)


def get_test_execution_result(fps_not_found):
    """See if the test results are reliable or not"""
    # Test result to unreliable fail in order notify team team something needs to be checked
    # manually
    if fps_not_found > 2:
        print(
            "Test execution failure, unreliable results. Too many fps values not found"
        )
        sys.exit(1)


def clean_up():
    """Delete the .png screenshots and restore the weston session file"""
    png_files = pathlib.Path(".").glob("*.png")
    print("Cleaning up")
    for file in png_files:
        file.unlink()

    OLD_DESKTOP_PATH.move(DESKTOP_PATH)
    subprocess.run("systemctl restart emptty", shell=True, check=False)


def main():
    """Main function"""

    parser = argparse.ArgumentParser()
    parser.add_argument(
        "backend", help="specify the chromium backend to use", choices=BACKENDS
    )

    args = parser.parse_args()

    test_setup()

    print("Start waiting for Chromium and the benchmark to stabilize")

    take_screenshots(args.backend)

    # Get list of .png pictures
    png_files = pathlib.Path(".").glob("*.png")

    process_images(png_files)


if __name__ == "__main__":
    main()
