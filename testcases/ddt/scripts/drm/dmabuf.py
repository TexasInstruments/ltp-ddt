#!/usr/bin/python3

import pykms
import time
import sys
import re
import dmaheap

def usage():
  print("Failed: {} <platform i.e dra7xx>".format(sys.argv[0]))
  exit(1)

if len(sys.argv) != 2 : usage()

card = pykms.Card()

res = pykms.ResourceManager(card)
conn = res.reserve_connector()
crtc = res.reserve_crtc(conn)
mode = conn.get_default_mode()

#Allocate dma-heap
if re.search("am62l", sys.argv[1], flags=0) != None :
	heap_handler = dmaheap.DMAHeap("reserved")
else :
	heap_handler = dmaheap.DMAHeap("linux,cma")
width = mode.hdisplay
height = mode.vdisplay
buffer = heap_handler.alloc(width * height * 4)

#Allocate DmabuffFramebuffer
fb = pykms.DmabufFramebuffer(card,width,height,"XR24",[buffer.fd],[width*4],[0])

pykms.draw_test_pattern(fb)

crtc.set_mode(conn, fb, mode)

time.sleep(3)
