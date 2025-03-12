""" Required modules for test """
import re
import time
import subprocess
import os
import sys
import json
import pathlib
from PIL import Image
import pytesseract


def get_platform_data(platform):
    """Get info about the platform being tested and min fps value for a test pass"""
    platform_data_path = pathlib.Path("platforms.json")
    data = json.loads(platform_data_path.read_text())
    desired_fps = int(data.get(platform))

    if desired_fps is None:
        print(f"The platform {platform} is missing from the platform file")
        sys.exit(1)
    return desired_fps

def test_setup():
    """Restart weston in debug mode and set up enviroment variables"""    
    subprocess.run("systemctl stop weston", shell=True, check = True)
    cmd = "sed -i 's|ExecStart=.*|& --debug|' /lib/systemd/system/weston.service"
    subprocess.run(cmd, shell=True, check = True)
    subprocess.run("systemctl daemon-reload", shell=True, check = True)
    subprocess.run("systemctl start weston", shell=True, check = True)

    subprocess.run("opkg update", shell=True)
    subprocess.run("opkg install chromium-ozone-wayland", shell=True, check = True)


def take_screenshots():
    """Take screenshots utilizing weston-screenshoter"""
    os.environ['https_proxy'] = 'http://webproxy.ext.ti.com:80'
    cmd = "su weston -c 'chromium \"https://webglsamples.org/aquarium/aquarium.html\" \
        --start-fullscreen --no-first-run'"
    with subprocess.Popen(cmd, shell=True) as chrome:
        try:
            chrome.wait(timeout=1)
        except subprocess.TimeoutExpired:
            pass
        if chrome.returncode is not None:
            sys.exit(1)

        print("Taking screenshots")
        for _ in range(0,10):
            subprocess.run("weston-screenshooter", shell=True, check = True)
            time.sleep(1)
        print("Finished taking screenshots")

        chrome.terminate()

def process_images(png_files,desired_fps):
    """Use pytesseract wrapper to find fps values from the screenshots"""
    total_fps = 0 #Total seen fps
    fps_not_found = 0 #Number of times fps was not found
    fps_found = 0 #number of times the fps was found

    for image in png_files:
        with Image.open(image) as image:
            image = image.crop((20, 20, 100, 100))
            text = pytesseract.image_to_string(image, config='--psm 12')
            try:
                fps_value = int(re.search(r'fps:\s(\d+)', text).group(1))
            except (AttributeError, TypeError):
                print("No FPS value found")
                fps_not_found += 1
            else:
                if fps_value < desired_fps:
                    print(f"FPS value is bellow threshold: {fps_value}")
                print("fps seen: " + str(fps_value))
                total_fps += fps_value
                fps_found += 1

    if fps_found == 0:
        average_fps = 0
    else:
        average_fps = total_fps / fps_found

    print(f"The average fps is: {average_fps}, with {fps_found} succesful fps detections")
    print(f"The number of unsuccesful fps detections: {fps_not_found}")

    get_test_result(desired_fps, average_fps,fps_not_found)
    return average_fps

def get_test_result(desired_fps, average_fps,fps_not_found):
    """See if the test results are reliable or not and clean up"""
    
    png_files = pathlib.Path(".").glob("*.png")
    clean_up(png_files)
    
    if fps_not_found >= 2:  #Test result to unreliable,
                            #fail in order notify team team something needs to be checked manually
        print("Test Failure")
        sys.exit(1)
    elif average_fps >= desired_fps:
        print("Successful Test !")
        sys.exit(0)
    else:
        print("Test Failure")
        sys.exit(0)

def clean_up(png_files):
    """Delete the .png screenshots"""
    print("Cleaning up: ")
    for file in png_files:
        file.unlink()

def main():
    """Main function"""

    platform = sys.argv[1] #Get platform name

    desired_fps = get_platform_data(platform)

    test_setup()

    print("Start waiting for Chromium and the benchmark itself to stabolize")
    time.sleep(15)

    take_screenshots()

    # Get list of .png pictures
    png_files = pathlib.Path(".").glob("*.png")

    process_images(png_files,desired_fps)


if __name__ == '__main__':
    main()
