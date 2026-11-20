"""Read local raster pixels with macOS ImageIO/CoreGraphics. No network."""
import ctypes as C
from pathlib import Path
CF=C.CDLL('/System/Library/Frameworks/CoreFoundation.framework/CoreFoundation');CG=C.CDLL('/System/Library/Frameworks/CoreGraphics.framework/CoreGraphics');IO=C.CDLL('/System/Library/Frameworks/ImageIO.framework/ImageIO')
P=C.c_void_p;Z=C.c_size_t
class Point(C.Structure):_fields_=[('x',C.c_double),('y',C.c_double)]
class Size(C.Structure):_fields_=[('width',C.c_double),('height',C.c_double)]
class Rect(C.Structure):_fields_=[('origin',Point),('size',Size)]
def f(lib,name,ret,args):fn=getattr(lib,name);fn.restype=ret;fn.argtypes=args;return fn
release=f(CF,'CFRelease',None,[P])
def read(path):
 raw=str(Path(path).resolve()).encode();url=f(CF,'CFURLCreateFromFileSystemRepresentation',P,[P,C.c_char_p,Z,C.c_bool])(None,raw,len(raw),False);src=f(IO,'CGImageSourceCreateWithURL',P,[P,P])(url,None);img=f(IO,'CGImageSourceCreateImageAtIndex',P,[P,Z,P])(src,0,None)
 if not img:raise ValueError('image decode failed')
 w=f(CG,'CGImageGetWidth',Z,[P])(img);h=f(CG,'CGImageGetHeight',Z,[P])(img);buf=C.create_string_buffer(w*h*4);space=f(CG,'CGColorSpaceCreateDeviceRGB',P,[])();ctx=f(CG,'CGBitmapContextCreate',P,[P,Z,Z,Z,Z,P,C.c_uint])(buf,w,h,8,w*4,space,0x4001)
 f(CG,'CGContextDrawImage',None,[P,Rect,P])(ctx,Rect(Point(0,0),Size(w,h)),img)
 for ob in [ctx,space,img,src,url]:release(ob)
 return w,h,buf.raw
def write(path,w,h,pixels):
 raw=str(Path(path).resolve()).encode();url=f(CF,'CFURLCreateFromFileSystemRepresentation',P,[P,C.c_char_p,Z,C.c_bool])(None,raw,len(raw),False);kind=f(CF,'CFStringCreateWithCString',P,[P,C.c_char_p,C.c_uint])(None,b'public.png',0x08000100);space=f(CG,'CGColorSpaceCreateDeviceRGB',P,[])();buf=C.create_string_buffer(bytes(pixels));ctx=f(CG,'CGBitmapContextCreate',P,[P,Z,Z,Z,Z,P,C.c_uint])(buf,w,h,8,w*4,space,0x4001);img=f(CG,'CGBitmapContextCreateImage',P,[P])(ctx);dest=f(IO,'CGImageDestinationCreateWithURL',P,[P,P,Z,P])(url,kind,1,None);f(IO,'CGImageDestinationAddImage',None,[P,P,P])(dest,img,None)
 if not f(IO,'CGImageDestinationFinalize',C.c_bool,[P])(dest):raise ValueError('PNG write failed')
 for ob in [dest,img,ctx,space,kind,url]:release(ob)
if __name__=='__main__':
 import sys,json
 w,h,b=read(sys.argv[1]);Path(sys.argv[2]).write_bytes(b);print(json.dumps({'width':w,'height':h,'bytes':len(b)}))
