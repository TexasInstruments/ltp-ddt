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
offset = int(h/4)

#print "width = {}, height = {}".format(w,h)

fbs=[]

pix_fmt = pykms.PixelFormat.ARGB8888
platform = sys.argv[1]
if len(sys.argv) > 1:
    if re.match('am43.*', platform, re.I):
        pix_fmt = pykms.PixelFormat.RGB888

for i in range(len(planes)):
    fbs.append(pykms.DumbFramebuffer(card, w, h, pix_fmt))
    pykms.draw_rect(fbs[i], 0, 0, w, h, pykms.RGB(255*(i==0), 255*(i==1), 255*(i==2)))
    pykms.draw_rect(fbs[i], i*offset, i*offset, int(w/2**(i+1)), int(h/2**(i+1)), pykms.RGB(255*(i!=1), 255*(i!=2), 255*(i!=0)))

try:
    crtc.set_props({
        "trans-key-mode": 0,
        "trans-key": 0,
        "background": 0,
        "alpha_blender": 1,
    })
except:
    print("trans-key-mode, trans-key, background, and alpha_blender will not be set")

#Show the whole frame
for i in range(len(planes)):
    plane = planes[i]
    fb = fbs[i]

    print("set crtc {}, plane {}, fb {} ({}, {})".format(crtc.id, plane.id, fbs[i].id, fb.width, fb.height))

    p_props = {
        "FB_ID": fb.id,
        "CRTC_ID": crtc.id,
        "SRC_X": 0,
        "SRC_Y": 0,
        "SRC_W": fb.width << 16,
        "SRC_H": fb.height << 16,
        "CRTC_X": 0,
        "CRTC_Y": 0,
        "CRTC_W": fb.width,
        "CRTC_H": fb.height,
    }
    if re.match("am62.*|am62a.*|am62d.*|am62l.*|am62p.*|am62xxsip.*|am64.*|am65.*|am68.*|am69.*|j721.*|j722.*|j742.*|j784.*|beagleplay.*", platform, re.I):
        p_props["zpos"] = i
    elif re.match("k2.*", platform, re.I):
        pass
    else:
        p_props["zorder"] = i
    plane.set_props(p_props)
    time.sleep(1)

#Show only the cropped rect
for i in range(len(planes)):
    plane = planes[i]
    fb = fbs[i]
    p_w = int(fb.width/2**(i+1))
    p_h = int(fb.height/2**(i+1))
    print("set crtc {}, plane {}, fb {} ({}, {})".format(crtc.id, plane.id, fbs[i].id, fb.width, fb.height))

    p_props = {
        "FB_ID": fb.id,
        "CRTC_ID": crtc.id,
        "SRC_X": i*offset << 16,
        "SRC_Y": i*offset << 16,
        "SRC_W":  p_w << 16,
        "SRC_H":  p_h << 16,
        "CRTC_X": 0,
        "CRTC_Y": 0,
        "CRTC_W": p_w,
        "CRTC_H": p_h
    }
    if re.match("am62.*|am65.*|j721.*|j722.*|j784.*|j742.*|am68.*|am69.*|beagleplay.*", platform, re.I):
        p_props["zpos"] = i
    elif re.match("k2.*", platform, re.I):
        pass
    else:
        p_props["zorder"] = i

    plane.set_props(p_props)

time.sleep(3)
