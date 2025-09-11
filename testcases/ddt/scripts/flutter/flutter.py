""" Required modules for test """
import subprocess
import sys
import os
import time
import glob


def get_flutter_version():
    """Get flutter engine and demo versions, and check if they match"""

    engine_path = "/usr/share/flutter/*/release/lib"
    engine_version_glob = glob.glob(engine_path)
    engine_versions = [path.split("/")[-3] for path in engine_version_glob]

    try:
        assert len(engine_versions) == 1, "The array must be of length 1, as only \
              one version should be present"
    except AssertionError as e:
        print(f"Error: {e}")
        print("Test failed, multiple different versions of flutter engine found")
        sys.exit(1)

    print(f"Flutter engine version: {engine_versions[0]}")

    demo_path = "/usr/share/flutter/flutter-samples-material-3-demo/*/release"
    demo_version_glob = glob.glob(demo_path)
    demo_versions = [path.split("/")[-2] for path in demo_version_glob]

    try:
        assert len(demo_versions) == 1, "The array must be of length 1, as only one \
            version should be present"
    except AssertionError as e:
        print(f"Error: {e}")
        print("Test failed, multiple different versions of flutter demo found")
        sys.exit(1)

    print(f"Flutter demo version: {demo_versions[0]}")

    try:
        assert demo_versions[0] == engine_versions[0], "The demo and engine versions must match"
    except AssertionError as e:
        print(f"Error: {e}")
        print("Test failed, flutter engine and demo versions do not match")
        sys.exit(1)

    return demo_versions[0]


def test_setup(flutter_version):
    """Restart emptty, download flutter ipk packages and set up enviroment variables"""    
    subprocess.run("systemctl restart emptty", shell=True, check=True)
    subprocess.run("systemctl status emptty", shell=True, check=False)

    subprocess.run("opkg update", shell=True, check=False)

    cmd = "opkg install libuv1 flutter-engine flutter-wayland-client \
           flutter-samples-material-3-demo"
    subprocess.run(cmd, shell=True, check=True)

    os.environ['WAYLAND_DISPLAY'] = '/run/user/1000/wayland-1'

    # Set LD_LIBRARY_PATH to flutter lib path
    os.environ['LD_LIBRARY_PATH'] = f"/usr/share/flutter/{flutter_version}/release/lib"

    # Print environment variables
    for key, value in os.environ.items():
        print(f'{key}: {value}')


def run_flutter_app(flutter_version):
    """Run flutter app"""

    demo_path = f"/usr/share/flutter/flutter-samples-material-3-demo/{flutter_version}/release"
    cmd = f"flutter-client -b {demo_path}"
    print(f"Running command: {cmd}")

    with subprocess.Popen(cmd, shell=True) as flutter:
        time.sleep(20)

        # Send ginal SIGTERM (15)
        flutter.terminate()
        flutter.wait(timeout=60)

        # Check return code, expected is 15
        # Negative return value (-N) indicates the child was terminal by signal N
        if flutter.returncode == -15:
            print("Test passed")
            sys.exit(0)
        else:
            print("Test failed")
            print(f"Return code: {flutter.returncode}")
            sys.exit(1)


def main():
    """ Main function """

    flutter_version = get_flutter_version()

    test_setup(flutter_version)

    run_flutter_app(flutter_version)

if __name__ == '__main__':
    main()
