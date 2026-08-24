#!/usr/bin/env python3
"""
Chromium playback comparison - samples frames during natural playback
and compares against reference video using SSIM and PSNR.
"""

import argparse
import os
import shutil
import subprocess
import sys
import time
import traceback
from collections import Counter
from pathlib import Path

import numpy as np
from PIL import Image, ImageFilter
from chromium_cdp_util import chromium_cdp, get_video_state, pause_video
from chromium_common import XDG_RUNTIME_DIR, WAYLAND_DISPLAY

NEARBY_OFFSETS   = [-1, 1]  # Frame offsets to try for timing mismatch
SSIM_THRESHOLD   = 0.85     # Structural Similarity Index (0-1)
PSNR_THRESHOLD   = 25.0     # Peak Signal-to-Noise Ratio in dB
PAUSE_DELAY      = 2        # Max seconds to wait for frame to stabilize after seek
CENTER_CROP      = 0.7      # Fraction of center area to keep (discards edges)
PREPROCESS_SCALE = 0.5      # Downsample factor applied after center crop
BLUR_RADIUS      = 5        # Gaussian blur radius applied after downsample (PIL)
SSIM_K1          = 0.01     # SSIM stability constant (from Wang et al. 2004)
SSIM_K2          = 0.03     # SSIM stability constant (from Wang et al. 2004)

# Sort so closest offsets are tried first
_OFFSETS_BY_PROXIMITY = sorted(NEARBY_OFFSETS, key=abs)


def is_gray(color):
    if not (isinstance(color, tuple) and len(color) >= 3):
        return False
    r, g, b = color[:3]
    avg = (r + g + b) / 3
    return 80 < avg < 200 and all(abs(c - avg) < 30 for c in (r, g, b))


def dominant_color(img_half):
    """Returns the most common color and its pixel fraction in an image half."""
    pixels = img_half.getdata()
    color, count = Counter(pixels).most_common(1)[0]
    return color, count / len(pixels)


def detect_video_display_side(image_path):
    """Returns 'left', 'right', or None (single display or ambiguous detection)."""
    img = Image.open(image_path)
    w, h = img.size
    if w / h < 2.0:
        return None

    lc, lp = dominant_color(img.crop((0,      0, w // 2, h)))
    rc, rp = dominant_color(img.crop((w // 2, 0, w,      h)))

    left_is_gray  = is_gray(lc) and lp > 0.3
    right_is_gray = is_gray(rc) and rp > 0.3

    if left_is_gray and not right_is_gray:
        return 'right'
    if right_is_gray and not left_is_gray:
        return 'left'
    return None


def take_screenshot(output_path):
    """Captures a weston screenshot and moves it to output_path."""
    subprocess.run(["weston-screenshooter"], check=True, capture_output=True,
                   env=os.environ | {"XDG_RUNTIME_DIR": XDG_RUNTIME_DIR, "WAYLAND_DISPLAY": WAYLAND_DISPLAY})
    screenshots = list(Path.cwd().glob("wayland-screenshot-*.png"))
    if not screenshots:
        raise Exception("No screenshot found")
    shutil.move(str(max(screenshots, key=lambda p: p.stat().st_mtime)), output_path)


def preprocess(img):
    """Center-crops and downsamples. Returns processed image without saving."""
    iw, ih = img.size
    fw, fh = int(iw * CENTER_CROP), int(ih * CENTER_CROP)
    left, top = (iw - fw) // 2, (ih - fh) // 2
    return img.crop((left, top, left + fw, top + fh)).resize(
        (int(fw * PREPROCESS_SCALE), int(fh * PREPROCESS_SCALE)), Image.BOX)


def calculate_metrics(ref, test):
    """Returns (ssim, psnr) using numpy only, or (0.0, 0.0) on failure.
    Uses global statistics instead of a sliding window — valid because both
    images are pre-blurred before this call."""
    try:
        if not isinstance(ref, np.ndarray):
            ref  = np.array(Image.open(ref).convert('RGB'))
        if not isinstance(test, np.ndarray):
            test = np.array(Image.open(test).convert('RGB'))
        if ref.shape != test.shape:
            return 0.0, 0.0
        x = ref.astype(np.float64)
        y = test.astype(np.float64)
        # PSNR
        mse = np.mean((x - y) ** 2)
        psnr = 10 * np.log10(255.0 ** 2 / mse) if mse > 0 else float('inf')
        # SSIM: per-channel global stats (axis=(0,1)), averaged across channels
        C1  = (SSIM_K1 * 255) ** 2
        C2  = (SSIM_K2 * 255) ** 2
        ux  = x.mean(axis=(0, 1))
        uy  = y.mean(axis=(0, 1))
        vx  = x.var(axis=(0, 1))
        vy  = y.var(axis=(0, 1))
        vxy = ((x - ux) * (y - uy)).mean(axis=(0, 1))
        ssim = float(np.mean((2*ux*uy + C1) * (2*vxy + C2) / ((ux**2 + uy**2 + C1) * (vx + vy + C2))))
        return ssim, float(psnr)
    except Exception:
        return 0.0, 0.0


def get_video_info(video_file):
    try:
        result = subprocess.run(
            ["ffprobe", "-v", "error", "-select_streams", "v:0",
             "-show_entries", "stream=width,height,r_frame_rate,duration",
             "-of", "csv=p=0", video_file],
            capture_output=True, text=True, check=True)
        parts = result.stdout.strip().split(',')
        if len(parts) >= 3:
            w, h = int(parts[0]), int(parts[1])
            fp = parts[2].split('/')
            fps = float(fp[0]) / float(fp[1]) if len(fp) == 2 else float(parts[2])
            dur = float(parts[3]) if len(parts) >= 4 else None
            if dur is None:
                raise ValueError("Could not get video duration")
            if fps <= 0:
                raise ValueError("Invalid fps")
            return w, h, fps, dur
    except (subprocess.CalledProcessError, ValueError):
        raise
    except Exception as e:
        raise ValueError(f"Could not read video info from {video_file}") from e


def capture_chromium_frame(cdp, output_path, video_side, target_timestamp):
    """Seeks to target_timestamp twice for accuracy, screenshots, crops to video half.
    Returns actual timestamp."""
    for _ in range(2):
        cdp.evaluate(f"document.querySelector('video').currentTime = {target_timestamp}")
        deadline = time.monotonic() + PAUSE_DELAY
        while time.monotonic() < deadline:
            if get_video_state(cdp)['readyState'] >= 2:
                break
            time.sleep(0.1)
    timestamp = get_video_state(cdp)['currentTime']
    take_screenshot(output_path)
    if video_side:
        img = Image.open(output_path)
        w, h = img.size
        crop = (0, 0, w // 2, h) if video_side == 'left' else (w // 2, 0, w, h)
        img.crop(crop).save(output_path)
    return timestamp


def extract_reference_frames(video_url, timestamp, frame_duration, reference_frames_dir, frame_num,
                             target_w, target_h):
    """Extracts NEARBY_OFFSETS + exact frame in one keyframe-seek pass, pre-processed to
    match the chromium frame size (center-cropped and downsampled). Returns offset->Path dict."""
    all_offsets  = sorted(set(NEARBY_OFFSETS) | {0})
    earliest     = all_offsets[0]
    frame_prefix = reference_frames_dir / f"frame_{frame_num:04d}"
    # Center-crop and scale; blur is applied in PIL after extraction for consistency
    vf = (f"crop=iw*{CENTER_CROP}:ih*{CENTER_CROP}"
          f":(iw-iw*{CENTER_CROP})/2:(ih-ih*{CENTER_CROP})/2"
          f",scale={target_w}:{target_h}")
    result = subprocess.run(
        ["ffmpeg", "-nostdin", "-v", "error",
         "-ss", str(timestamp + earliest * frame_duration),
         "-i", video_url, "-frames:v", str(len(all_offsets)), "-vsync", "0",
         "-vf", vf, "-compression_level", "0", "-y", str(frame_prefix) + "_%d.png"],
        capture_output=True, text=True)
    if result.returncode != 0 or result.stderr.strip():
        print(f"  [ref frames] ffmpeg error (rc={result.returncode}): {result.stderr.strip()}")
    return {offset: frame_prefix.parent / f"{frame_prefix.name}_{i}.png"
            for i, offset in enumerate(all_offsets, start=1)}


def try_offset_frames(ref_frames, chromium_arr, ssim, psnr, blur):
    """Tries nearby offset frames when exact frame fails. Returns (ssim, psnr, status, offset)."""
    for offset in _OFFSETS_BY_PROXIMITY:
        f = ref_frames.get(offset)
        if not f or not f.exists():
            continue
        ref_arr = np.array(Image.open(f).filter(blur).convert('RGB'))
        f_ssim, f_psnr = calculate_metrics(ref_arr, chromium_arr)
        if f_ssim >= SSIM_THRESHOLD and f_psnr >= PSNR_THRESHOLD:
            return f_ssim, f_psnr, 'PASS', offset
    return ssim, psnr, 'FAIL', None


def crop_detect(image_path):
    """Returns (x, y, w, h) of the non-black region via Pillow getbbox(), or None if fully black."""
    if not (bbox := Image.open(image_path).convert('RGB').getbbox()):
        return None  # fully black frame
    x, y, x2, y2 = bbox
    return x, y, x2 - x, y2 - y


def process_frame(frame_num, timestamp, chromium_frame, crop,
                  video_url, video_fps, reference_frames_dir, results):
    """Processes a captured Chromium frame: extracts reference, compares metrics."""
    try:
        # video_fps is guaranteed to be non-None because we checked video_duration is not None in main()
        frame_duration = 1.0 / video_fps

        img = Image.open(chromium_frame)
        if crop:
            x, y, w, h = crop
            if (x, y, w, h) != (0, 0, img.width, img.height):
                img = img.crop((x, y, x + w, y + h))

        # Compute the exact output size preprocess() will produce so reference frames match
        target_w = int(int(img.width  * CENTER_CROP) * PREPROCESS_SCALE)
        target_h = int(int(img.height * CENTER_CROP) * PREPROCESS_SCALE)

        ref_frames = extract_reference_frames(
            video_url, timestamp, frame_duration, reference_frames_dir, frame_num,
            target_w, target_h)
        reference_frame = ref_frames.get(0)
        if reference_frame is None:
            raise ValueError("Exact reference frame (offset=0) not found in extracted frames")

        blur = ImageFilter.GaussianBlur(radius=BLUR_RADIUS)
        img = preprocess(img).filter(blur)
        img.save(chromium_frame)
        chromium_arr = np.array(img.convert('RGB'))

        # Only blur the exact reference frame; offset frames are blurred on demand
        if reference_frame.exists():
            Image.open(reference_frame).filter(blur).save(reference_frame)

        ssim, psnr = calculate_metrics(reference_frame, chromium_arr) \
            if reference_frame.exists() else (0.0, 0.0)

        status = 'PASS' if ssim >= SSIM_THRESHOLD and psnr >= PSNR_THRESHOLD else 'FAIL'

        passed_offset = None
        if status == 'FAIL':
            ssim, psnr, status, passed_offset = try_offset_frames(ref_frames, chromium_arr, ssim, psnr, blur)

        offset_str = f" (offset {passed_offset:+d})" if passed_offset is not None else ""
        print(f"  {status}{offset_str} - SSIM: {ssim:.6f}, PSNR: {psnr:.2f}")

        chromium_frame.unlink(missing_ok=True)
        for f in ref_frames.values():
            f.unlink(missing_ok=True)

        results.append({'frame_num': frame_num, 'timestamp': timestamp,
                        'ssim': ssim, 'psnr': psnr, 'status': status})

    except Exception as e:
        print(f"  ERROR: {e}")
        print(traceback.format_exc())
        results.append({'frame_num': frame_num, 'timestamp': timestamp, 'status': 'ERROR'})


def _resolve_crop(detected, img_w, img_h, video_w, video_h):
    """Return the crop box for the video region, accounting for black bars."""
    cx, cy, cw, ch = detected
    if cw == video_w and ch == video_h:
        # crop_detect matches video resolution - trust its position
        return detected
    # Mismatch - the video likely has black bars (letterbox/pillarbox)
    # encoded into the stream itself, so center crop to the known
    # video resolution to exclude them before comparison
    cx0, cy0 = (img_w - video_w) // 2, (img_h - video_h) // 2
    if cx0 >= 0 and cy0 >= 0 and cx0 + video_w <= img_w and cy0 + video_h <= img_h:
        return (cx0, cy0, video_w, video_h)
    # video too large for display when centered - use crop_detect region directly
    return detected


def detect_display(output_dir, video_w, video_h):
    """Takes an initial screenshot to detect dual-display setup and crop region.
    Returns (video_side, crop) where video_side is 'left', 'right', or None,
    and crop is (x, y, w, h) or None if detection failed.
    The temporary screenshot is deleted after use.
    The half-crop is applied before crop_detect so that the weston desktop
    side is excluded, and crop coordinates are relative to the video half."""
    screenshot = output_dir / "initial_screenshot.png"
    try:
        take_screenshot(screenshot)
        side = detect_video_display_side(screenshot)
        img = Image.open(screenshot)
        if side:
            w, h = img.size
            half = (0, 0, w // 2, h) if side == 'left' else (w // 2, 0, w, h)
            img = img.crop(half)
            img.save(screenshot)
        img_w, img_h = img.size
        detected = crop_detect(screenshot)
        crop = _resolve_crop(detected, img_w, img_h, video_w, video_h) if detected else None
        print(f"Display: {'dual - video on ' + side if side else 'single'}")
        print(f"Crop region: {crop}")
        return side, crop
    except Exception as e:
        print(f"Warning: Display detection failed: {e}")
        return None, None
    finally:
        screenshot.unlink(missing_ok=True)


def print_summary(results):
    """Prints pass/fail/error counts and returns exit code (0=PASS, 1=FAIL)."""
    if not results:
        print("ERROR: No frames were successfully compared")
        return 1
    stats = Counter(r['status'] for r in results)
    print(f"\nTotal: {len(results)} | Passed: {stats['PASS']} | Failed: {stats['FAIL']} | Errors: {stats['ERROR']}")
    passed = stats['FAIL'] == 0 and stats['ERROR'] == 0
    print("RESULT: PASS" if passed else "RESULT: FAIL")
    return 0 if passed else 1


def main():
    parser = argparse.ArgumentParser(description='Sample Chromium playback and compare with reference video')
    parser.add_argument('--video',       required=True,          help='Reference video local path')
    parser.add_argument('--output-dir',  default='playback_comparison', help='Output directory for frames')
    parser.add_argument('--max-frames',  type=int, default=30,   help='Number of frames to sample')
    args = parser.parse_args()

    output_dir           = Path(args.output_dir).resolve()
    chromium_frames_dir  = output_dir / "chromium_frames"
    reference_frames_dir = output_dir / "reference_frames"
    try:
        for d in (output_dir, chromium_frames_dir, reference_frames_dir):
            d.mkdir(exist_ok=True)
    except OSError as e:
        sys.exit(f"ERROR: could not create output directory: {e}")

    try:
        video_w, video_h, video_fps, video_duration = get_video_info(args.video)
    except ValueError as e:
        sys.exit(f"ERROR: {e}")
    print(f"Video: {video_w}x{video_h}, {video_fps:.2f}fps, {video_duration:.1f}s")

    results = []

    with chromium_cdp() as cdp:
        pause_video(cdp)
        first_timestamp = get_video_state(cdp)['currentTime']
        timestamps = np.linspace(first_timestamp, video_duration, args.max_frames)
        print(f"Sampling {args.max_frames} frames from {timestamps[0]:.1f}s to {timestamps[-1]:.1f}s\n")

        video_side, crop = detect_display(output_dir, video_w, video_h)

        for frame_num, target_ts in enumerate(timestamps, start=1):
            chromium_frame = chromium_frames_dir / f"frame_{frame_num:04d}.png"

            try:
                timestamp = capture_chromium_frame(cdp, chromium_frame, video_side, target_ts)
                print(f"[{frame_num}/{args.max_frames}] Timestamp: {timestamp:.3f}s")
            except Exception as e:
                print(f"[{frame_num}/{args.max_frames}] ERROR during capture: {e}")
                results.append({'frame_num': frame_num, 'timestamp': None, 'status': 'ERROR'})
                continue

            process_frame(frame_num, timestamp, chromium_frame, crop,
                          args.video, video_fps, reference_frames_dir, results)

    rc = print_summary(results)
    shutil.rmtree(output_dir, ignore_errors=True)
    return rc


if __name__ == "__main__":
    sys.exit(main())
