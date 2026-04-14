""" Required modules for test """
import subprocess
import sys
import os
import time
import glob
import logging

# Configure logging
logging.basicConfig(
    level=logging.INFO,
    format='%(levelname)s: %(message)s'
)
logger = logging.getLogger(__name__)

# Configuration constants
WAYLAND_DISPLAY = '/run/user/1000/wayland-1'
FLUTTER_ENGINE_PATH = "/usr/share/flutter"
DEMO_PACKAGE_NAME = "flutter-samples-material-3-demo"
FLUTTER_APP_TIMEOUT = 20  # seconds to let app run
WAIT_TIMEOUT = 60  # seconds to wait for graceful shutdown
SIGTERM_EXIT_CODE = -15  # Expected return code when terminated by SIGTERM


def test_setup():
    """Setup test environment: install packages, configure envs"""
    logger.info("Starting test setup...")

    # Update package lists
    logger.info("Updating package lists...")
    result = subprocess.run("opkg update", shell=True, check=False)

    # Install required packages
    logger.info("Installing flutter packages...")
    try:
        subprocess.run(
            "opkg install libuv1 flutter-engine flutter-wayland-client "
            "flutter-samples-material-3-demo",
            shell=True,
            check=True
        )
        logger.info("Packages installed successfully")
    except subprocess.CalledProcessError as e:
        raise RuntimeError(f"Failed to install packages: {e}") from e

    # Configure environment variables
    logger.info("Configuring environment variables...")
    os.environ['WAYLAND_DISPLAY'] = WAYLAND_DISPLAY

    flutter_version = get_flutter_version()
    flutter_lib_path = f"{FLUTTER_ENGINE_PATH}/{flutter_version}/release/lib"
    os.environ['LD_LIBRARY_PATH'] = flutter_lib_path

    # Log variables of interest
    logger.info("WAYLAND_DISPLAY=%s",WAYLAND_DISPLAY)
    logger.info("LD_LIBRARY_PATH=%s",flutter_lib_path)


def get_flutter_version():
    """Get flutter version,validate flutter engine and demo versions match."""
    logger.info("Checking flutter versions...")

    # Get engine version
    engine_path_pattern = f"{FLUTTER_ENGINE_PATH}/*/release/lib"
    engine_paths = glob.glob(engine_path_pattern)

    if not engine_paths:
        raise RuntimeError("No flutter engine installations found")

    engine_versions = [path.split("/")[-3] for path in engine_paths]

    if len(engine_versions) != 1:
        raise RuntimeError(
            (f"Expected 1 engine version, found {len(engine_versions)}: "
             f"{engine_versions}")
        )

    engine_version = engine_versions[0]
    logger.info("Flutter engine version: %s",engine_version)

    # Get demo version
    demo_path_pattern = (
        f"{FLUTTER_ENGINE_PATH}/{DEMO_PACKAGE_NAME}/*/release"
    )
    demo_paths = glob.glob(demo_path_pattern)

    if not demo_paths:
        raise RuntimeError(
            f"No {DEMO_PACKAGE_NAME} installations found"
        )

    demo_versions = [path.split("/")[-2] for path in demo_paths]

    if len(demo_versions) != 1:
        raise RuntimeError(
            (f"Expected 1 demo version, found {len(demo_versions)}: "
             f"{demo_versions}")
        )

    demo_version = demo_versions[0]
    logger.info("Flutter demo version: %s",demo_version)

    # Verify versions match
    if demo_version != engine_version:
        raise RuntimeError(
            (f"Version mismatch: engine={engine_version}, "
             f"demo={demo_version}")
        )

    return demo_version

def run_flutter_app(flutter_version):
    """Run flutter app"""
    demo_path = (
        f"{FLUTTER_ENGINE_PATH}/{DEMO_PACKAGE_NAME}/"
        f"{flutter_version}/release"
    )
    cmd = f"flutter-client -b {demo_path}"
    logger.info("Running: %s",cmd)

    with subprocess.Popen(cmd, shell=True) as flutter:
        time.sleep(20)

        # Send ginal SIGTERM (15)
        flutter.terminate()
        flutter.wait(timeout=60)

        # Check return code, expected is 15
        # Negative return value (-N) indicates the child was terminal by signal N
        if flutter.returncode == -15:
            logger.info("Test passed!")
            sys.exit(0)
        else:
            logger.error("Test failed!")
            logger.error("Return code: %s", flutter.returncode)
            sys.exit(1)

def main():
    """Main test execution"""

    logger.info("Flutter test starting...")

    test_setup()
    flutter_version = get_flutter_version()
    run_flutter_app(flutter_version)

if __name__ == '__main__':
    sys.exit(main())
