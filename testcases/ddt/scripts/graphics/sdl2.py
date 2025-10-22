""" Required modules for test """
import subprocess
import sys
import os
import time
import argparse

TEST_DIRECTORY = "/usr/libexec/installed-tests/SDL2"

def test_setup():
    """Restart emptty, and set up enviroment variable"""
    subprocess.run("systemctl restart emptty", shell=True, check=True)
    subprocess.run("systemctl status emptty", shell=True, check=False)

    os.environ['WAYLAND_DISPLAY'] = '/run/user/1000/wayland-1'


def run_infinite_test(testcase_path):
    """Run infinite runtime testcase"""

    with subprocess.Popen(testcase_path, cwd=TEST_DIRECTORY) as test:
        time.sleep(30)

        test.terminate()
        test.wait(timeout=60)

        if test.returncode == 0:
            print("Test passed")
            return True

        print("Test failed")
        print(f"Return code: {test.returncode}")
        return False


def run_finite_test(testcase_path):
    """Run finite runtime testcase"""

    with subprocess.Popen(testcase_path, cwd=TEST_DIRECTORY, shell=True) as test:
        test.wait()

        if test.returncode == 0:
            print("Test passed")
            return True

        print("Test failed")
        print(f"Return code: {test.returncode}")
        return False


def parse_arguments():
    """Parse command line arguments"""
    parser = argparse.ArgumentParser(
        description='Run SDL2 tests with specified runtime behavior.')

    parser.add_argument('test_type',
                        choices=['finite', 'infinite'],
                        help='Type of test to run: "finite" for tests that complete on their own, '
                             '"infinite" for tests that need to be terminated after a period')

    parser.add_argument('testcase',
                        help='Name of the testcase to run')

    return parser.parse_args()



def main():
    """ Main function """
    test_setup()

    args = parse_arguments()

    # Validate that the testcase exists
    testcase_path = os.path.join(TEST_DIRECTORY, args.testcase)
    if not os.path.exists(testcase_path):
        print(f"Testcase '{args.testcase}' not found in {TEST_DIRECTORY}")
        sys.exit(1)

    if args.test_type == "infinite":
        result = run_infinite_test(testcase_path)
    else:
        result = run_finite_test(testcase_path)

    sys.exit(0 if result else 1)

if __name__ == '__main__':
    main()
