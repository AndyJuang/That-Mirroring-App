#!/usr/bin/env python3
"""Write standard PNG-backed ICNS chunks if macOS iconutil cannot encode.
No image conversion here: sips already produced every iconset size.
"""
import pathlib, struct, sys
folder, output = map(pathlib.Path, sys.argv[1:])
specs = [('icp4',16,1), ('ic11',16,2), ('icp5',32,1), ('ic12',32,2),
         ('ic07',128,1), ('ic13',128,2), ('ic08',256,1), ('ic14',256,2),
         ('ic09',512,1), ('ic10',512,2)]
chunks = []
for kind, size, scale in specs:
    name = f'icon_{size}x{size}' + ('@2x' if scale == 2 else '') + '.png'
    data = (folder / name).read_bytes()
    assert data[:8] == b'\x89PNG\r\n\x1a\n', name
    assert struct.unpack('>II', data[16:24]) == (size*scale, size*scale), name
    chunks.append(kind.encode() + struct.pack('>I', len(data)+8) + data)
body = b''.join(chunks)
output.write_bytes(b'icns' + struct.pack('>I', len(body)+8) + body)
