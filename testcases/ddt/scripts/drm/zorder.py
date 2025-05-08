#!/usr/bin/python3

import pykms
import time
import random
import sys
import re

# This hack makes drm initialize the fbcon, setting up the default connector
card = pykms.Card()
card = 0

card = pykms.Card()
res = pykms.ResourceManager(card)
conn = res.reserve_connector()
crtc = res.reserve_crtc(conn)
mode = conn.get_default_mode()

planes = []
for p in card.planes:
    if p.supports_crtc(crtc) == False:
        continue
    planes.append(p)

card.disable_planes()

w = mode.hdisplay
h = mode.vdisplay
offset = int(h/2**(len(planes)-1))
l_div = len(planes) - 1

def usage():
  print("Failed: {} <platform i.e dra7xx>".format(sys.argv[0]))
  exit(1)

if len(sys.argv) != 2 : usage()

platform = sys.argv[1]

fbs=[]

for i in range(len(planes)):
    fbs.append(pykms.DumbFramebuffer(card, w, h, pykms.PixelFormat.RGB888))
    pykms.draw_rect(fbs[i], 0, 0, int(w/l_div), int(h/l_div), pykms.RGB(255*(1 & 2**(i%3)), 255*((2 & 2**(i%3)) >> i), 255*((4 & 2**(i%3)) >> i)))

if not re.match("am62.*|am62a.*||am62d.*|am62l.*|am62p.*|am62xxsip.*|am5.*|am64.*|am65.*|am68.*|am69.*|j721.*|j722.*|j742.*|j784.*", platform, re.I):
    crtc.set_props({
        "trans-key-mode": 0,
        "trans-key": 0,
        "background": 0,
        "alpha_blender": 1,
    })


for i in range(len(planes)):
    plane = planes[i]
    fb = fbs[i]

    print("set crtc {}, plane {}, fb {} ({}, {})".format(crtc.id, plane.id, fbs[i].id, fb.width, fb.height))
    p_props = {
        "FB_ID": fb.id,
        "CRTC_ID": crtc.id,
        "SRC_X": 0,
        "SRC_Y": 0,
        "SRC_W":  int(w/l_div) << 16,
        "SRC_H":  int(h/l_div) << 16,
        "CRTC_X": i*offset,
        "CRTC_Y": i*offset,
        "CRTC_W": int(w/l_div),
        "CRTC_H": int(h/l_div),
    }
    if re.match("am62.*|am65.*|j721.*|j722.*|j784.*|j742.*|am68.*|am69.*", platform, re.I):
        p_props["zpos"] = i
    else:
        p_props["zorder"] = i

    plane.set_props(p_props)

time.sleep(3)
