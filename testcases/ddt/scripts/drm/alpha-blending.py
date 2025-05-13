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
side = int(h/4)

def usage():
  print("Failed: {} <platform i.e dra7xx>".format(sys.argv[0]))
  exit(1)

if len(sys.argv) != 2 : usage()

platform = sys.argv[1]

#print "width = {}, height = {}".format(w,h)

fbs=[]

for i in range(len(planes)):
    fbs.append(pykms.DumbFramebuffer(card, w, h, pykms.PixelFormat.ARGB8888))
    pykms.draw_rect(fbs[i], 0, 0, side, side, pykms.RGB(128, 255*(1 & 2**i), 255*((2 & 2**i) >> i), 255*((4 & 2**i) >> i)))

try:
    crtc.set_props({
        "trans-key-mode": 0,
        "trans-key": 0,
        "background": 0,
        "alpha_blender": 1,
    })
except:
    print("trans-key-mode, trans-key, background, and alpha_blender will not be set")


for i in range(len(planes)):
    plane = planes[i]
    fb = fbs[i]
    print("set crtc {}, plane {}, fb {} ({}, {})".format(crtc.id, plane.id, fbs[i].id, fb.width, fb.height))

    p_props = {
        "FB_ID": fb.id,
        "CRTC_ID": crtc.id,
        "SRC_W":  side << 16,
        "SRC_H":  side << 16,
        "CRTC_X": i*100,
        "CRTC_Y": i*100,
        "CRTC_W": side,
        "CRTC_H": side,
    }
    if re.match("am62.*|am62a.*|am62d.*|am62l.*|am62p.*|am62xxsip.*|am64.*|am65.*|am68.*|am69.*|j721.*|j722.*|j742.*|j784.*", platform, re.I):
        p_props["zpos"] = i
        p_props["alpha"] = int(65535/(i+1))
    else:
        p_props["zorder"] = i
    plane.set_props(p_props)

time.sleep(3)
