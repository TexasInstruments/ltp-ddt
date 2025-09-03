""" Required modules for test """
import re
import time
import subprocess
import os
import sys
import pathlib
from PIL import Image
import pytesseract


def test_setup():
    """Restart weston in debug mode and set up enviroment variables"""    
    cmd = "sed -i 's|Exec=.*|& --debug|' /usr/share/wayland-sessions/weston.desktop"
    subprocess.run(cmd, shell=True, check = True)
    subprocess.run("systemctl restart emptty", shell=True, check = True)

    subprocess.run("opkg update", shell=True)
    subprocess.run("opkg install chromium-ozone-wayland", shell=True, check = True)


def take_screenshots(backend):
    """Take screenshots utilizing weston-screenshoter"""
    os.environ['WAYLAND_DISPLAY'] = '/run/user/1000/wayland-1'
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
        for _ in range(0,10):
            subprocess.run("weston-screenshooter", shell=True, check = True)
            time.sleep(1)
        print("Finished taking screenshots")

        chrome.terminate()

def process_images(png_files):
    """Use pytesseract wrapper to find fps values from the screenshots"""
    total_fps = 0 #Total seen fps
    fps_not_found = 0 #Number of times fps was not found
    fps_found = 0 #number of times the fps was found

    for image in png_files:
        with Image.open(image) as image:
            image = image.crop((20, 20, 100, 100))
            text = pytesseract.image_to_string(image, config='--psm 1')
            try:
                fps_value = int(re.search(r'fps:\s(\d+)', text).group(1))
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
    print(f"The number of succesful fps detections: {fps_found}")
    print(f"The number of unsuccesful fps detections: {fps_not_found}")

    get_test_execution_result(fps_not_found)

def get_test_execution_result(fps_not_found):
    """See if the test results are reliable or not and clean up"""
    
    png_files = pathlib.Path(".").glob("*.png")
    clean_up(png_files)
    
    if fps_not_found > 2:   #Test result to unreliable,
                            #fail in order notify team team something needs to be checked manually
        print("Test execution failure, unreliable results. Too many fps values not found")
        sys.exit(1)

def clean_up(png_files):
    """Delete the .png screenshots"""
    print("Cleaning up: ")
    for file in png_files:
        file.unlink()

def main():
    """Main function"""

    try:
        backend = sys.argv[1] # Specify the backend as an argument : vulkan or gles-egl (default)
    except IndexError:
        sys.stderr.write("Error: Backend argument is missing\n")
        sys.exit(1)

    test_setup()

    print("Start waiting for Chromium and the benchmark itself to stabolize")

    take_screenshots(backend)

    # Get list of .png pictures
    png_files = pathlib.Path(".").glob("*.png")

    process_images(png_files)


if __name__ == '__main__':
    main()