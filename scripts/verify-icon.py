#!/usr/bin/env python3
import pathlib, subprocess, struct
# Decode using Apple's iconutil, independent from our fallback writer.
folder = pathlib.Path('build/IconVerified.iconset')
subprocess.run(['iconutil','-c','iconset','AppIcon.icns','-o',str(folder)],check=True)
for size in [16,32,128,256,512]:
    for scale in [1,2]:
        path = folder / (f'icon_{size}x{size}' + ('@2x' if scale == 2 else '') + '.png')
        raw = path.read_bytes()
        assert raw[:8] == b'\x89PNG\r\n\x1a\n' and struct.unpack('>II',raw[16:24]) == (size*scale,size*scale), path
print('ICON VERIFIED')
