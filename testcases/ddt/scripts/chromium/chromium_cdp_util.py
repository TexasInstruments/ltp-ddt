#!/usr/bin/env python3
"""Simple Chromium video playback checker via CDP"""

import sys
import json
import time
import websocket
import requests

TIMEOUT             = 10  # seconds to wait for a single CDP response
VIDEO_TIMEOUT       = 30  # total seconds to poll for active video playback
POLL_INTERVAL       = 5   # seconds between each playback state poll
STABLE_PLAYBACK_MIN = 5   # minimum currentTime (s) before calculating fps

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
        totalFrames: q.totalVideoFrames
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
        self.next_id = 1

    def __enter__(self):
        return self

    def __exit__(self, *_):
        try:
            self.ws.close()
        except Exception:
            pass

    def send(self, method, params=None):
        msg_id = self.next_id
        self.next_id += 1
        self.ws.send(json.dumps({"id": msg_id, "method": method, "params": params or {}}))
        return msg_id

    def wait_for_response(self, msg_id, timeout=TIMEOUT):
        start = time.time()
        while True:
            if time.time() - start > timeout:
                raise TimeoutError(f"Timeout waiting for response id={msg_id}")
            msg = json.loads(self.ws.recv())
            if msg.get("id") == msg_id:
                return msg

    def evaluate(self, js):
        """Evaluate a JS expression and return the result value."""
        msg_id = self.send('Runtime.evaluate', {'expression': js, 'returnByValue': True})
        resp = self.wait_for_response(msg_id)
        return resp.get('result', {}).get('result', {}).get('value')


def get_page_ws_url(port=9222):
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
                return page['webSocketDebuggerUrl']
        time.sleep(1)
    raise TimeoutError(f"Chromium not ready on port {port} after {VIDEO_TIMEOUT}s")


def query_video_state(ws_url):
    """Query a CDP target and return the video element state, or None."""
    with CDPClient(ws_url) as client:
        result = client.evaluate(_JS_VIDEO_CHECK)
    return result if isinstance(result, dict) else None


def calc_fps(v):
    """Calculate average FPS from video start: totalVideoFrames / currentTime.
    Returns 0 if currentTime is 0."""
    ct = v.get('currentTime') or 0
    return (v.get('totalFrames') or 0) / ct if ct > 0 else 0


def wait_for_stable_playback(ws_url):
    """Poll until video is playing, sleep until currentTime >= STABLE_PLAYBACK_MIN, then return state."""
    deadline = time.time() + VIDEO_TIMEOUT
    while time.time() < deadline:
        v = query_video_state(ws_url)
        if isinstance(v, dict) and v.get('currentTime', 0) > 0 and not v.get('paused', True):
            ct = v.get('currentTime', 0)
            if ct < STABLE_PLAYBACK_MIN:
                time.sleep(STABLE_PLAYBACK_MIN - ct)
                v = query_video_state(ws_url)
                if not isinstance(v, dict):
                    return None
            return v
        time.sleep(POLL_INTERVAL)
    return None


def get_video_state(cdp):
    """Returns video element state. Removes the controls attribute. Raises if no video element is found."""
    js = """(() => {
        const v = document.querySelector('video');
        if (!v) return null;
        v.removeAttribute('controls');
        return { currentTime: v.currentTime, paused: v.paused,
                 readyState: v.readyState, duration: v.duration };
    })();"""
    result = cdp.evaluate(js)
    if result is None:
        raise Exception("No video element found")
    return result


def pause_video(cdp):
    cdp.wait_for_response(cdp.send("Runtime.evaluate",
        {"expression": "document.querySelector('video').pause();"}))


def check_playback(port=9222):
    """Check if video is playing."""
    try:
        ws_url = get_page_ws_url(port)
        v = wait_for_stable_playback(ws_url)
        if not isinstance(v, dict):
            print("ERROR: No video element found within timeout", file=sys.stderr)
            return False

        duration = v.get('duration') or 0
        ct       = v.get('currentTime') or 0
        paused   = v.get('paused', True)
        error    = v.get('error')
        fps      = calc_fps(v)

        print(f"Video state: duration={duration:.1f}s, currentTime={ct:.1f}s, paused={paused}")
        print(f"VIDEO_FPS:{fps:.2f}")
        print(f"VIDEO_DURATION:{duration:.1f}")

        if error:
            print(f"ERROR: Media error {error}", file=sys.stderr)
            return False

        if duration > 0 and ct > 0 and not paused:
            print("Video is playing")
            return True

        print("ERROR: Video is not playing", file=sys.stderr)
        return False

    except Exception as e:
        print(f"ERROR: {e}", file=sys.stderr)
        return False


def measure_webgl_fps(cdp, warmup, duration, num_samples):
    """Injects an rAF counter, waits warmup seconds, then takes num_samples evenly
    spaced over duration seconds. Returns the average FPS, or 0.0 if no samples collected."""
    deadline = time.time() + VIDEO_TIMEOUT
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
    port = int(sys.argv[1]) if len(sys.argv) > 1 else 9222
    sys.exit(0 if check_playback(port) else 1)
