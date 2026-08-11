#!/usr/bin/env python3
import argparse
import subprocess
import sys
import time
from pathlib import Path

from chromium_common import setup, cleanup, launch_chromium, CHROMIUM_LAUNCH_WAIT
from chromium_cdp_util import chromium_cdp, wait_for_stable_playback, parse_video_state

ERR_GENERAL              = 1
ERR_INVALID_PARAM        = 2
ERR_CHROMIUM_NOT_STARTED = 4
ERR_PLAYBACK_FAILED      = 5
ERR_DOWNLOAD_FAILED      = 6
ERR_COMPARISON_FAILED    = 7

HIGH_FPS_THRESHOLD = 40

# (normal, high_fps) thresholds per device
_CPU_THRESHOLDS = {
    "am62pxx-evm": (30, 45),
    "j722s-evm":   (30, 45),
    "j742s2-evm":  (15, 20),
    "j784s4-evm":  ( 7, 10),
}

BASE_VIDEO_URL  = "http://gtopentest-server.gt.design.ti.com/anonymous/common/Multimedia/ti-img-encode-decode-testvecs/decoder"
VALID_QUALITIES = ("240p", "360p", "540p", "720p", "1080p", "2k", "4k")
MAX_FRAMES      = 20


def build_chromium_url(platform, media_id, quality):
    if platform == "HTML":
        return f"{BASE_VIDEO_URL}/{media_id}", False
    elif platform == "VIMEO":
        if quality not in VALID_QUALITIES:
            print(f"ERROR: Invalid quality '{quality}' for VIMEO. Must be one of: {' '.join(VALID_QUALITIES)}", file=sys.stderr)
            sys.exit(ERR_INVALID_PARAM)
        return f"https://player.vimeo.com/video/{media_id}?quality={quality}&autoplay=1&loop=1", True
    elif platform == "YOUTUBE":
        return f"https://www.youtube.com/embed/{media_id}?autoplay=1&loop=1", True
    else:
        print(f"ERROR: Invalid platform '{platform}'. Must be 'HTML', 'VIMEO' or 'YOUTUBE'.", file=sys.stderr)
        sys.exit(ERR_INVALID_PARAM)


def get_cpu_threshold(fps):
    device = subprocess.run(["uname", "-n"], capture_output=True, text=True).stdout.strip()
    if device not in _CPU_THRESHOLDS:
        print(f"ERROR: Unsupported platform: {device}", file=sys.stderr)
        sys.exit(ERR_GENERAL)
    normal, high = _CPU_THRESHOLDS[device]
    return high if fps > HIGH_FPS_THRESHOLD else normal


def download_reference_video(url):
    if not url.startswith(('http://', 'https://')):
        return url
    dest = Path(url.split('?')[0]).name
    print(f"Downloading reference video to {dest}...", file=sys.stderr)
    if subprocess.run(["wget", "-q", "-O", dest, url]).returncode != 0:
        Path(dest).unlink(missing_ok=True)
        print(f"ERROR: Failed to download {url}", file=sys.stderr)
        sys.exit(ERR_DOWNLOAD_FAILED)
    size_mb = Path(dest).stat().st_size // 1048576
    print(f"Download complete ({size_mb} MB)", file=sys.stderr)
    return dest


def verify_video_playback():
    print("Verifying video playback via CDP...")
    try:
        with chromium_cdp() as cdp:
            v = wait_for_stable_playback(cdp)
    except Exception as e:
        print(f"ERROR: {e}", file=sys.stderr)
        sys.exit(ERR_PLAYBACK_FAILED)

    if not isinstance(v, dict):
        print("ERROR: No video element found within timeout", file=sys.stderr)
        sys.exit(ERR_PLAYBACK_FAILED)

    fps, ct, duration, paused, error = parse_video_state(v)

    if error:
        print(f"ERROR: Media error {error}", file=sys.stderr)
        sys.exit(ERR_PLAYBACK_FAILED)

    if not (duration > 0 and ct > 0 and not paused):
        print("ERROR: Video is not playing", file=sys.stderr)
        sys.exit(ERR_PLAYBACK_FAILED)

    return fps


def chromium_playback(platform, media_id, quality):
    setup()

    url, proxy = build_chromium_url(platform, media_id, quality)
    print("Starting Chromium...")
    launch_chromium(url, proxy=proxy,
                    extra_args="--hide-crash-restore-bubble --enable-logging=stderr --mute-audio")
    print(f"Waiting {CHROMIUM_LAUNCH_WAIT}s for Chromium launch...")
    time.sleep(CHROMIUM_LAUNCH_WAIT)

    if subprocess.run(["pgrep", "-f", "chromium-bin"], capture_output=True).returncode != 0:
        print("ERROR: Failed to detect Chromium processes", file=sys.stderr)
        sys.exit(ERR_CHROMIUM_NOT_STARTED)

    fps = verify_video_playback()
    print("Video playback verified successfully")
    print(f"CPU_THRESHOLD:{get_cpu_threshold(fps)}")


def chromium_playback_with_comparison(platform, media_id, quality, golden=None):
    if platform == "VIMEO":
        video_reference = f"{BASE_VIDEO_URL}/chromium/vimeo/{golden}"
    else:
        video_reference = f"{BASE_VIDEO_URL}/{media_id}"

    local_video = download_reference_video(video_reference)
    try:
        print("Starting Chromium playback...")
        chromium_playback(platform, media_id, quality)

        print("Starting playback comparison test...")
        script = Path(__file__).parent / "chromium_playback_compare.py"
        result = subprocess.run([
            "python3", str(script),
            "--video", local_video,
            "--output-dir", "playback_comparison",
            "--max-frames", str(MAX_FRAMES),
        ])
        if result.returncode != 0:
            print("Test FAILED: Video quality below thresholds", file=sys.stderr)
            sys.exit(ERR_COMPARISON_FAILED)

        print("Test PASSED: Video quality meets thresholds (SSIM > 0.85, PSNR > 25 dB)")
    finally:
        Path(local_video).unlink(missing_ok=True)


def main():
    parser = argparse.ArgumentParser()
    sub = parser.add_subparsers(dest='command', required=True)

    sub.add_parser('cleanup')

    playback = sub.add_parser('playback')
    playback.add_argument('platform')
    playback.add_argument('media_id')
    playback.add_argument('quality', nargs='?', default='1080p')

    compare = sub.add_parser('compare')
    compare.add_argument('platform')
    compare.add_argument('media_id')
    compare.add_argument('quality', nargs='?', default='1080p')
    compare.add_argument('golden', nargs='?', default=None)

    args = parser.parse_args()

    if args.command == 'cleanup':
        cleanup()
    elif args.command == 'compare':
        chromium_playback_with_comparison(args.platform, args.media_id,
                                          args.quality, args.golden)
    elif args.command == 'playback':
        chromium_playback(args.platform, args.media_id, args.quality)


if __name__ == "__main__":
    main()
