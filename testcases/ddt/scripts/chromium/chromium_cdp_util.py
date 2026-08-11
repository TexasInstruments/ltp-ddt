#!/usr/bin/env python3
"""Simple Chromium video playback checker via CDP"""

import sys
import json
import time
import websocket
import requests
from contextlib import contextmanager
from chromium_common import CDP_PORT

TIMEOUT             = 10  # seconds to wait for a single CDP response
VIDEO_TIMEOUT       = 30  # total seconds to poll for active video playback
POLL_INTERVAL       = 5   # seconds between each playback state poll
STABLE_PLAYBACK_MIN = 5   # minimum currentTime (s) before calculating fps
PAGE_LOAD_TIMEOUT   = 30  # seconds to wait for document.readyState == complete

# currentTime > 0 and not paused confirms that decoding has actually started.
_JS_VIDEO_CHECK = """(function() {
    var v = document.querySelector("video");
    if (!v) return null;
    var q = v.getVideoPlaybackQuality();
    return {
        duration:    v.duration,
        currentTime: v.currentTime,
        paused:      v.paused,
        error:       v.error ? v.error.code : null,
        totalFrames: q.totalVideoFrames,
        readyState:  v.readyState
    };
})()"""

_JS_WEBGL_FPS_INJECT = """
    window.__fps = { frames: 0, t0: performance.now() };
    const _raf = window.requestAnimationFrame.bind(window);
    window.requestAnimationFrame = function(cb) {
        return _raf(function(t) { window.__fps.frames++; cb(t); });
    };
"""

_JS_WEBGL_FPS_READ = """(function() {
    const elapsed = (performance.now() - window.__fps.t0) / 1000;
    return elapsed > 0 ? window.__fps.frames / elapsed : 0;
})()"""


class CDPClient:
    """Chrome DevTools Protocol client"""
    def __init__(self, ws_url):
        self.ws = websocket.WebSocket()
        self.ws.connect(ws_url)
        self._id = 1

    def __enter__(self):
        return self

    def __exit__(self, *_):
        try:
            self.ws.close()
        except Exception:
            pass

    def evaluate(self, js):
        msg_id = self._id
        self._id += 1
        self.ws.send(json.dumps({
            "id": msg_id,
            "method": "Runtime.evaluate",
            "params": {"expression": js, "returnByValue": True},
        }))
        deadline = time.time() + TIMEOUT
        while time.time() <= deadline:
            msg = json.loads(self.ws.recv())
            if msg.get("id") == msg_id:
                if "error" in msg:
                    raise RuntimeError(f"CDP error: {msg['error']}")
                return msg.get("result", {}).get("result", {}).get("value")
        raise TimeoutError("Timeout waiting for CDP response")


@contextmanager
def chromium_cdp(port=CDP_PORT):
    with CDPClient(get_page_ws_url(port)) as cdp:
        yield cdp


def get_page_ws_url(port=CDP_PORT):
    """Polls until a non-blank page is available. Returns its WebSocket URL."""
    deadline = time.time() + VIDEO_TIMEOUT
    while time.time() <= deadline:
        try:
            resp = requests.get(f'http://localhost:{port}/json', timeout=5)
            resp.raise_for_status()
        except (requests.exceptions.ConnectionError, requests.exceptions.Timeout):
            pass
        else:
            targets = resp.json()
            page = targets[0] if targets else None
            if page and page.get('url') not in ('about:blank', '', None):
                print(f"Connected to: {page['title']}")
                return page['webSocketDebuggerUrl']
        time.sleep(1)
    raise TimeoutError(f"Chromium not ready on port {port} after {VIDEO_TIMEOUT}s")


def wait_for_stable_playback(cdp):
    """Poll until video is playing, sleep until currentTime >= STABLE_PLAYBACK_MIN, then return state."""
    deadline = time.time() + VIDEO_TIMEOUT
    while time.time() < deadline:
        v = cdp.evaluate(_JS_VIDEO_CHECK)
        if not isinstance(v, dict):
            time.sleep(POLL_INTERVAL)
            continue
        if v.get('currentTime', 0) > 0 and not v.get('paused', True):
            ct = v['currentTime']
            if ct < STABLE_PLAYBACK_MIN:
                remaining = deadline - time.time()
                sleep_time = min(STABLE_PLAYBACK_MIN - ct, remaining)
                if sleep_time > 0:
                    time.sleep(sleep_time)
                v = cdp.evaluate(_JS_VIDEO_CHECK)
            return v if isinstance(v, dict) else None
        time.sleep(POLL_INTERVAL)
    return None


def get_video_state(cdp):
    """Returns video element state. Removes the controls attribute. Raises if no video element is found."""
    cdp.evaluate("var v = document.querySelector('video'); if (v) v.removeAttribute('controls');")
    result = cdp.evaluate(_JS_VIDEO_CHECK)
    if result is None:
        raise Exception("No video element found")
    return result


def pause_video(cdp):
    cdp.evaluate("document.querySelector('video').pause();")


def parse_video_state(v):
    """Parse and print video state dict. Returns (fps, ct, duration, paused, error)."""
    ct       = v.get('currentTime') or 0
    duration = v.get('duration') or 0
    paused   = v.get('paused', True)
    error    = v.get('error')
    fps      = (v.get('totalFrames') or 0) / ct if ct > 0 else 0
    print(f"Video state: duration={duration:.1f}s, currentTime={ct:.1f}s, paused={paused}")
    print(f"VIDEO_FPS:{fps:.2f}")
    print(f"VIDEO_DURATION:{duration:.1f}")
    return fps, ct, duration, paused, error


def check_playback(port=CDP_PORT):
    """Check if video is playing."""
    try:
        with chromium_cdp(port) as cdp:
            v = wait_for_stable_playback(cdp)
    except Exception as e:
        print(f"ERROR: {e}", file=sys.stderr)
        return False

    if not isinstance(v, dict):
        print("ERROR: No video element found within timeout", file=sys.stderr)
        return False

    fps, ct, duration, paused, error = parse_video_state(v)

    if error:
        print(f"ERROR: Media error {error}", file=sys.stderr)
        return False

    if duration > 0 and ct > 0 and not paused:
        print("Video is playing")
        return True

    print("ERROR: Video is not playing", file=sys.stderr)
    return False


def measure_webgl_fps(cdp, warmup, duration, num_samples):
    """Injects an rAF counter, waits warmup seconds, then takes num_samples evenly
    spaced over duration seconds. Returns the average FPS, or 0.0 if no samples collected."""
    deadline = time.time() + PAGE_LOAD_TIMEOUT
    while cdp.evaluate("document.readyState") != 'complete':
        if time.time() > deadline:
            raise TimeoutError("Page did not finish loading")
        time.sleep(1)

    cdp.evaluate(_JS_WEBGL_FPS_INJECT)
    print(f"Warming up for {warmup}s...")
    time.sleep(warmup)

    # Re-inject in case the page reloaded during warmup
    if cdp.evaluate("typeof window.__fps === 'undefined'") is not False:
        cdp.evaluate(_JS_WEBGL_FPS_INJECT)

    interval = duration / num_samples
    print(f"Measuring {num_samples} samples over {duration}s ({interval:.2f}s per sample)...")
    samples = []
    for i in range(num_samples):
        cdp.evaluate("window.__fps = { frames: 0, t0: performance.now() };")
        time.sleep(interval)
        fps = cdp.evaluate(_JS_WEBGL_FPS_READ)
        if fps is not None:
            samples.append(fps)
            print(f"  [{i+1}/{num_samples}] {fps:.1f} fps")
    return sum(samples) / len(samples) if samples else 0.0


if __name__ == '__main__':
    port = int(sys.argv[1]) if len(sys.argv) > 1 else CDP_PORT
    sys.exit(0 if check_playback(port) else 1)
