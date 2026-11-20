#!/usr/local/bin/python3
"""Read-only sips metadata replacement for Linux; never modifies source bytes."""
import sys,warnings
from PIL import Image
Image.MAX_IMAGE_PIXELS=40000000
warnings.simplefilter('error',Image.DecompressionBombWarning)
try:
    path=sys.argv[-1]
    with Image.open(path) as im:
        w,h=im.size;fmt=im.format.lower();im.verify()
    with Image.open(path) as im:im.load()
    if fmt not in ('png','jpeg'):raise ValueError()
    print(f'{path}\n  pixelWidth: {w}\n  pixelHeight: {h}\n  format: {fmt}')
except Exception:sys.exit(1)
