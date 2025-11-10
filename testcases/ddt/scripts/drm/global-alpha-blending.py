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

platform = ''
if len(sys.argv) > 1:
    platform = sys.argv[1]

planes = []
for p in card.planes:
    if p.supports_crtc(crtc) == False:
        continue
    planes.append(p)

card.disable_planes()

w = mode.hdisplay
h = mode.vdisplay
side = int(h/4)

#print "width = {}, height = {}".format(w,h)

fbs=[]

for i in range(len(planes)):
    fbs.append(pykms.DumbFramebuffer(card, w, h, pykms.PixelFormat.RGB888))
    pykms.draw_rect(fbs[i], 0, 0, side, side, pykms.RGB(255*(1 & 2**i), 255*((2 & 2**i) >> i), 255*((4 & 2**i) >> i)))

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

    if re.match("am62.*|am65.*|j721.*|j722.*|j784.*|j742.*|am68.*|am69.*|am57.*|beagleplay.*", platform, re.I):
        p_props["zpos"] = i
        p_props["alpha"] = 128
    else:
        p_props["zorder"] = i
        p_props["global_alpha"] = 128

    plane.set_props(p_props)        

time.sleep(3)
