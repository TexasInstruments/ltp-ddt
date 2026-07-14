"""Run a webgl demo on Chromium and capture the FPS"""

import argparse
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


def test_setup():
    """Restart weston in debug mode and set up enviroment variables"""
    # backup and modify the session entry for weston-screenshoter
    DESKTOP_PATH.copy(OLD_DESKTOP_PATH)
    subprocess.run(
        f"sed -i 's|Exec=.*|& --debug|' {DESKTOP_PATH}", shell=True, check=True
    )

    subprocess.run("systemctl restart emptty", shell=True, check=True)

    subprocess.run("opkg update", shell=True)
    subprocess.run("opkg install chromium-ozone-wayland", shell=True, check=True)


def take_screenshots(backend):
    """Take screenshots utilizing weston-screenshoter"""
    os.environ["WAYLAND_DISPLAY"] = "/run/user/1000/wayland-1"
    cmd = f"su -l weston -c 'export https_proxy=http://webproxy.ext.ti.com:80; \
            export XDG_RUNTIME_DIR=/run/user/1000;\
            export WAYLAND_DISPLAY=wayland-1; chromium --use-angle={backend} \"https://webglsamples.org/aquarium/aquarium.html\" --start-fullscreen --no-first-run' "

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
            subprocess.run("weston-screenshooter", shell=True, check=True)
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
    """See if the test results are reliable or not and clean up"""

    png_files = pathlib.Path(".").glob("*.png")
    clean_up(png_files)

    # Test result to unreliable fail in order notify team team something needs to be checked
    # manually
    if fps_not_found > 2:
        print(
            "Test execution failure, unreliable results. Too many fps values not found"
        )
        sys.exit(1)


def clean_up(png_files):
    """Delete the .png screenshots"""
    print("Cleaning up: ")
    for file in png_files:
        file.unlink()


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
