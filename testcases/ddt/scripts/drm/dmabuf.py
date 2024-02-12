#!/usr/bin/python3

import pykms
import time
import sys
import re

def usage():
  print("Failed: {} <platform i.e dra7xx>".format(sys.argv[0]))
  exit(1)

if len(sys.argv) != 2 : usage()

if re.match('dra7.*|am5.*',sys.argv[1],re.I):
	card = pykms.OmapCard()
else:
	card = pykms.Card()

res = pykms.ResourceManager(card)
conn = res.reserve_connector()
crtc = res.reserve_crtc(conn)
mode = conn.get_default_mode()

origfb = pykms.DmabufFramebuffer(card, mode.hdisplay, mode.vdisplay, "XR24")

fb = pykms.ExtFramebuffer(card, origfb.width, origfb.height, origfb.format,
		[origfb.fd(0)], [origfb.stride(0)], [origfb.offset(0)])

pykms.draw_test_pattern(fb);

crtc.set_mode(conn, fb, mode)

time.sleep(3)
