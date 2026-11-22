#!/usr/bin/env python3
"""make_gif.py <framesdir> <out.gif>: stitches the PPM frames into a 1.5x GIF at 20 fps."""
import sys, glob
from PIL import Image
files = sorted(glob.glob(sys.argv[1] + '/f*.ppm'))
frames = [Image.open(f).convert('RGB').resize((384, 360), Image.NEAREST) for f in files]
frames = [f.quantize(colors=64, method=Image.MEDIANCUT, dither=Image.NONE) for f in frames]
frames[0].save(sys.argv[2], save_all=True, append_images=frames[1:], duration=50, loop=0, optimize=False)
print(len(frames), 'frames ->', sys.argv[2])
