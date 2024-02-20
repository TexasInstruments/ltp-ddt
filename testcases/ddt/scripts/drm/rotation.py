#!/usr/bin/python3

import pykms
import time
from enum import Enum

card = pykms.Card()

res = pykms.ResourceManager(card)
conn = res.reserve_connector()
crtc = res.reserve_crtc(conn)
mode = conn.get_default_mode()
modeb = mode.to_blob(card)
rootplane = res.reserve_primary_plane(crtc, pykms.PixelFormat.XRGB8888)
plane = res.reserve_overlay_plane(crtc, pykms.PixelFormat.NV12)

card.disable_planes()

req = pykms.AtomicReq(card)
req.add(conn, "CRTC_ID", crtc.id)
req.add(crtc, {"ACTIVE": 1,
		"MODE_ID": modeb.id})
req.commit_sync(allow_modeset = True)

def show_rot_plane(crtc, plane, fb, rot, x_scale, y_scale):

	crtc_w = int(fb_w * x_scale)
	crtc_h = int(fb_h * y_scale)

	if (rot & pykms.Rotation.ROTATE_90) or (rot & pykms.Rotation.ROTATE_270):
		tmp = crtc_w
		crtc_w = crtc_h
		crtc_h = tmp

	crtc_x = int(mode.hdisplay / 2 - crtc_w / 2)
	crtc_y = int(mode.vdisplay / 2 - crtc_h / 2)

	req = pykms.AtomicReq(card)

	src_x = 0
	src_y = 0
	src_w = fb_w - src_x
	src_h = fb_h - src_y

	print("SRC {},{}-{}x{}  DST {},{}-{}x{}".format(
		src_x, src_y, src_w, src_h,
		crtc_x, crtc_y, crtc_w, crtc_h))

	angle_str = pykms.Rotation(rot & pykms.Rotation.ROTATE_MASK).name
	reflect_x_str = "REFLECT_X" if rot & pykms.Rotation.REFLECT_X else ""
	reflect_y_str = "REFLECT_Y" if rot & pykms.Rotation.REFLECT_Y else ""

	print("{} {} {}".format(angle_str, reflect_x_str, reflect_y_str))

	req.add(plane, {"FB_ID": fb.id,
			"CRTC_ID": crtc.id,
			"SRC_X": src_x << 16,
			"SRC_Y": src_y << 16,
			"SRC_W": src_w << 16,
			"SRC_H": src_h << 16,
			"CRTC_X": crtc_x,
			"CRTC_Y": crtc_y,
			"CRTC_W": crtc_w,
			"CRTC_H": crtc_h,
			"rotation": rot,
			"zpos": 2})

	req.commit_sync(allow_modeset = True)


fb_w = 480
fb_h = 350
x_scale = 1
y_scale = 1

fb = pykms.OmapFramebuffer(card, fb_w, fb_h, "NV12", flags = pykms.OmapFramebuffer.Tiled);
pykms.draw_test_pattern(fb);

rotations = [ pykms.Rotation.ROTATE_0, pykms.Rotation.ROTATE_90, pykms.Rotation.ROTATE_180, pykms.Rotation.ROTATE_270 ]
reflections = [0, pykms.Rotation.REFLECT_X, pykms.Rotation.REFLECT_X | pykms.Rotation.REFLECT_Y, pykms.Rotation.REFLECT_Y ]

current_rot = pykms.Rotation.ROTATE_0

show_rot_plane(crtc, plane, fb, current_rot, x_scale, y_scale)

for rot in rotations:
	for reflection in reflections:
		show_rot_plane(crtc, plane, fb, rot | reflection, x_scale, y_scale)
		time.sleep(0.2)

