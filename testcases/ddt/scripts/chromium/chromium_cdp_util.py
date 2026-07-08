#!/usr/bin/env python3
"""Simple Chromium video playback checker via CDP"""

import sys
import os
import json
import time
import websocket
import requests
from contextlib import contextmanager

TIMEOUT             = 10  # seconds to wait for a single CDP response
VIDEO_TIMEOUT       = 30  # total seconds to poll for active video playback
POLL_INTERVAL       = 5   # seconds between each playback state poll
STABLE_PLAYBACK_MIN = 5   # minimum currentTime (s) before calculating fps

# JS injected via CDP to return the state of the first <video> element found.
# currentTime > 0 and not paused confirms that decoding has actually started.
_JS_CHECK = ('(function(){'
             'var v=document.querySelector("video");'
             'if(!v)return null;'
             'var q=v.getVideoPlaybackQuality();'
             'return{'
             'duration:v.duration,'
             'currentTime:v.currentTime,'
             'paused:v.paused,'
             'error:v.error?v.error.code:null,'
             'totalFrames:q.totalVideoFrames'
             '};'
             '})()')

@contextmanager
def no_proxy():
    """Temporarily clear proxy environment variables."""
    proxy_vars = ['HTTP_PROXY', 'HTTPS_PROXY', 'http_proxy', 'https_proxy', 'ALL_PROXY', 'all_proxy']
    saved = {var: os.environ.pop(var) for var in proxy_vars if var in os.environ}
    try:
        yield
    finally:
        os.environ.update(saved)


class CDPClient:
    """Chrome DevTools Protocol client"""
    def __init__(self, ws_url):
        with no_proxy():
            self.ws = websocket.WebSocket()
            self.ws.connect(ws_url)
            self.next_id = 1

    def __enter__(self):
        return self

    def __exit__(self, exc_type, exc_val, exc_tb):
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


def query_video_state(ws_url):
    """Query a CDP target and return the video element state, or None."""
    with CDPClient(ws_url) as client:
        result = client.evaluate(_JS_CHECK)
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
        if (!v) throw new Error('No video element found');
        v.removeAttribute('controls');
        return { currentTime: v.currentTime, paused: v.paused,
                 readyState: v.readyState, duration: v.duration };
    })();"""
    msg_id = cdp.send("Runtime.evaluate", {"expression": js, "returnByValue": True})
    response = cdp.wait_for_response(msg_id)
    if "exceptionDetails" in response.get("result", {}):
        raise Exception("Failed to get video state")
    return response["result"]["result"]["value"]


def pause_video(cdp):
    cdp.wait_for_response(cdp.send("Runtime.evaluate",
        {"expression": "document.querySelector('video').pause();"}))


def check_playback(port=9222):
    """Check if video is playing."""
    try:
        with no_proxy():
            targets = requests.get(f'http://localhost:{port}/json', timeout=2).json()

        page = next((t for t in targets
                     if t.get('type') == 'page'
                     and t.get('url') not in ('about:blank', '', None)), None)
        if not page:
            print("ERROR: No page loaded or page still loading", file=sys.stderr)
            return False

        print(f"Video page loaded: {page['url']}")

        ws_url = page.get('webSocketDebuggerUrl')
        if not ws_url:
            print("ERROR: WebSocket URL not available", file=sys.stderr)
            return False

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
            print("✓ Video is playing")
            return True

        print("ERROR: Video is not playing", file=sys.stderr)
        return False

    except Exception as e:
        print(f"ERROR: {e}", file=sys.stderr)
        return False


if __name__ == '__main__':
    port = int(sys.argv[1]) if len(sys.argv) > 1 else 9222
    sys.exit(0 if check_playback(port) else 1)
