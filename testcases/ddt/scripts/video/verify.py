#!/usr/bin/python3

import numpy as np
import os
import sys
import argparse
import subprocess
import time
from math import log10, sqrt

# values obtained from https://learn.microsoft.com/en-us/windows/win32/medfound/about-yuv-video#yuv-in-computer-video
maxLuma = 240
maxChroma = 235

# function to calculate the size of a frame
# Can be extended to support more formats
# Currently only concerned with YUV420 (NV12)
def getVal(width, height):
    return width*height*3//2

# Function for calculating the PSNR value between two given values
# Inputs are same position in bitstream between golden reference and video under review
# Where byte0 is golden and byte1 is one under test
# Currently written under assumption we are using bit depth 8
# Returns the PSNR calculated
def PSNR(byte0, byte1, Luma):
    mse = np.mean((byte0 - byte1) ** 2)
    maxPixel = 0 # set default value for max pixel value
    if mse == 0:
        return 100 # there is no difference between the two
    else:
        if Luma:
            maxPixel = maxLuma
        else:
            maxPixel = maxChroma
        psnr = 20 * log10(maxPixel/sqrt(mse))
    return psnr

def getElements(file, width, height):
    # set up the different layers to NV12 video
    y = np.zeros([height, width])
    uv = np.zeros([height//2, width])

    # need to get the y, u, and v portions of the video
    # read the specifc amount in the file for that specific image, each Y U V value is 1 byte
    # turn the array into vector of height*1.5 rows and width columns
    y = np.frombuffer(file.read(width*height), dtype=np.uint8).reshape([height, width])
    uv = np.frombuffer(file.read(width*height//2), dtype=np.uint8).reshape([height//2, width])

    u = np.zeros([height//4, width//2], dtype=np.uint8)
    v = np.zeros([height//4, width//2], dtype=np.uint8)

    for j in range(height//2):
        u_index = 0
        v_index = 0
        for k in range(width):
            if k%2 == 0:
                u[j//2][u_index] = uv[j][k]
                u_index += 1
            else:
                v[j//2][v_index] = uv[j][k]
                v_index += 1

    return [y, u, v]

def ParseCmdLineArgs():
    # Define the parser rules
    parser = argparse.ArgumentParser(description='Parser Used to Generate Gstreamer Strings for testing Codecs', add_help=False)

    required    = parser.add_argument_group('required arguments')
    
    required.add_argument('-t', '--test_file',
                          help="Location of the video under test",
                          required=True)
    
    required.add_argument('-r', '--reference_file',
                          help="Video that was used for decoding",
                          required=True)

    required.add_argument('-p', '--parse_file',
                          help='''Text file that contains verbose data about previously decoded video.
                          This is needed in order to get crop information''',
                          required=True)
    
    required.add_argument('-w', '--width',
                          help='''Width of the encoded video file.
                          Parameter is required to ensure sizes are the same.
                          ''')
    
    required.add_argument('-h', '--height',
                          help='''Width of the encoded video file.
                          Parameter is required to ensure sizes are the same.
                          ''')
    
    # Invoke the parser
    args = parser.parse_args()

    return args

def ProcessInputFile(inFile):
    width = 0
    height = 0
    with open(inFile, 'r') as f:
        data = f.readlines()
        for i in data:
            if "src" in i:
                vals = i.split('src: caps = ')[1]
                if "v4l2" in i:
                    vals = vals.split(', ')
                    for v in vals:
                        if '=' in v:
                            key,val = v.split('=')
                            if "width" in key:
                                pos = val.find(')')
                                width = val[pos+1:]
                            elif "height" in key:
                                pos = val.find(')')
                                height = val[pos+1:]
    return int(width), int(height)

def getResolution(video):
    command = "ffprobe -v error -select_streams v:0 -show_entries stream=width,height -of csv=s=x:p=0 "
    command += video
        
    result = subprocess.run(command, shell=True, stdout=subprocess.PIPE)
    resolutions = result.stdout.decode().strip("\n")
    split = resolutions.find('x')

    return int(resolutions[:split]), int(resolutions[split+1:])

def getName(video):
    loc = video.find('.')
    return video[:loc]

def buildPipe(video):
    gstStr = "gst-launch-1.0 filesrc location=" + video
    vidName = getName(video)

    parser = ""
    decoder = ""
    if video[-3:] == "264":
        parser = "h264parse"
        decoder = "avdec_h264"
    else:
        parser = "h265parse"
        decoder = "avdec_h265"

    gstStr += " ! " + parser + " ! " + decoder
    gstStr += " ! videoconvert ! video/x-raw, format=NV12 ! filesink location="

    outName = vidName + ".yuv"

    out = open(outName, 'wb')
    gstStr += vidName + ".yuv"

    out.close()
    runConversion(gstStr)

    return outName

def runConversion(gstStr):
    subprocess.run(gstStr, shell=True)
    time.sleep(1)

def videoCrop():
    return

def main():
    # Parse command line arguments
    args      = ParseCmdLineArgs()
    underTest = args.test_file
    reference = args.reference_file
    parse     = args.parse_file

    # get what correct resolution should be given encoded file
    width_ref   = int(args.width)
    height_ref  = int(args.height)
    print("Ref: " + str(width_ref) + "x" + str(height_ref))

    width = 0
    height = 0

    # get what resolution is of decoded file
    width_out, height_out = ProcessInputFile(parse)
    print("Out: " + str(width_out) + "x" + str(height_out))

    # TODO: Remove failing and implement crop
    if ((width_ref != width_out) or (height_ref != height_out)):
        print("Mismatched resolutions. Cropping issue present\n")
        sys.exit(1)
    else:
        width = width_out
        height = height_out
    
    golden = buildPipe(reference) # get the golden video to compare

    # get the size of the file in order to calculate the number of frames
    # yuv420 frame size is width*height*1.5
    goldenFilesize = os.path.getsize(golden)
    underTestFileSize = os.path.getsize(underTest)

    if goldenFilesize != underTestFileSize:
        print("Different File Sizes")
        sys.exit(1)

    golden_nframes = goldenFilesize // (width*height*3//2)
    underTest_nframes = underTestFileSize // (width*height*3//2)

    frames = 0
    if golden_nframes != underTest_nframes:
        print("Different number of decoded frames")
        sys.exit(1)
    else:
        frames = golden_nframes
    print("Going to parse " + str(frames) + " frames")
    
    # open the file in read and byte mode
    goldFile = open(golden, 'rb')
    testFile = open(underTest, 'rb')

    Luma = []
    ChromaB = []
    ChromaR = []
    # iterate through the number of frames
    for i in range(frames):
        # extract the stream elements of NV12 frame
        goldY, goldU, goldV = getElements(goldFile, width, height)
        testY, testU, testV = getElements(testFile, width, height)

        # calculate a PSNR on each respective element
        psnrY = PSNR(goldY, testY, True)
        psnrU = PSNR(goldU, testU, False)
        psnrV = PSNR(goldV, testV, False)

        Luma.append(psnrY)
        ChromaB.append(psnrU)
        ChromaR.append(psnrV)

    lumaAvg = np.mean(Luma)
    chromaBavg = np.mean(ChromaB)    
    chromaRavg = np.mean(ChromaR)   

    print("Luma: " + str(lumaAvg))
    print("Cb: " + str(chromaBavg))
    print("Cr: " + str(chromaRavg))

    if (lumaAvg <= 90 or chromaBavg <= 90 or chromaRavg <= 90):
        print("Status: Fail")
        sys.exit(1)
    
    print("Status: Pass")

    goldFile.close()
    testFile.close()
    sys.exit(0)

if __name__ == '__main__':
    main()