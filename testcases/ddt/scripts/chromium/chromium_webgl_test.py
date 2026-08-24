#!/usr/bin/env python3
import argparse
import atexit
import subprocess
import sys

from chromium_cdp_util import chromium_cdp, measure_webgl_fps
from chromium_common import setup, cleanup, launch_chromium, BACKENDS, CHROMIUM_LAUNCH_WAIT

TEST_URL        = "https://webglsamples.org/aquarium/aquarium.html"
MEASURE_SECONDS = 10
NUM_SAMPLES     = 50
FPS_MIN         = 30


def measure_fps(backend):
    """Launch Chromium, measure WebGL FPS via CDP, return average FPS."""
    chrome = launch_chromium(TEST_URL, extra_args=f"--use-angle={backend}", proxy=True)
    try:
        chrome.wait(timeout=1)
    except subprocess.TimeoutExpired:
        pass
    if chrome.returncode is not None:
        print("Chromium failed to start")
        sys.exit(1)

    try:
        with chromium_cdp() as cdp:
            return measure_webgl_fps(cdp, CHROMIUM_LAUNCH_WAIT, MEASURE_SECONDS, NUM_SAMPLES)
    except Exception as e:
        print(f"ERROR: Failed to measure FPS: {e}")
        sys.exit(1)
    finally:
        chrome.terminate()


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("backend", help="specify the chromium backend to use", choices=BACKENDS)
    args = parser.parse_args()

    setup(configure_weston=False)
    atexit.register(cleanup)

    avg_fps = measure_fps(args.backend)
    print(f"FPS_AVERAGE: {avg_fps:.1f} FPS_AVERAGE")

    if avg_fps < FPS_MIN:
        print(f"FAIL: {avg_fps:.1f} fps below threshold {FPS_MIN}")
        sys.exit(1)

    print("PASS")


if __name__ == "__main__":
    main()
