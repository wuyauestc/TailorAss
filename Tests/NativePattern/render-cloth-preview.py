#!/usr/bin/env python3
"""Rasterize actual exported cloth geometry, with a depth buffer, without deps.

This is a diagnostic mesh rendering, not a photo, a simulator, or a screenshot
of the App. It does not modify either upstream reference image.
"""
import argparse
import json
import math
from pathlib import Path
import struct
import zlib


def write_png(path, width, height, pixels):
    def chunk(kind, data):
        return struct.pack(">I", len(data)) + kind + data + struct.pack(">I", zlib.crc32(kind + data))
    raw = b"".join(b"\0" + pixels[y*width*3:(y+1)*width*3] for y in range(height))
    path.write_bytes(b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", width, height, 8, 2, 0, 0, 0)) + chunk(b"IDAT", zlib.compress(raw, 7)) + chunk(b"IEND", b""))


def render(mesh_path, output_path, focus_cloth=False):
    mesh = json.loads(mesh_path.read_text())
    view_width, height = 480, 750
    width = view_width*3
    image = bytearray([243, 239, 231])*(width*height)
    depth = [-math.inf]*(width*height)
    groups = [(mesh["mannequinPositions"], mesh["mannequinTriangleIndices"], (180, 167, 146)),
              (mesh["positions"], mesh["triangleIndices"], (41, 141, 150))]
    all_points = mesh["positions"] if focus_cloth else mesh["mannequinPositions"] + mesh["positions"]
    low, high = min(p["y"] for p in all_points), max(p["y"] for p in all_points)
    center_y = (low+high)/2
    scale = min(520, (height-90)/max(0.1, high-low))
    if focus_cloth:
        horizontal = max(max(p[k] for p in all_points)-min(p[k] for p in all_points)
                         for k in ("x", "z"))
        scale = min((view_width-80)/max(0.1, horizontal), (height-90)/max(0.1, high-low))
    for view, yaw in enumerate([0.0, math.pi/2, math.pi]):
        cy, sy, cp, sp = math.cos(yaw), math.sin(yaw), math.cos(-0.10), math.sin(-0.10)

        def transform(point):
            x, y, z = point["x"], point["y"]-center_y, point["z"]
            xx, zz = cy*x + sy*z, -sy*x + cy*z
            yy, zz = cp*y-sp*zz, sp*y+cp*zz
            return [view*view_width+view_width/2+xx*scale, height/2-yy*scale, zz]

        for points, indices, base in groups:
            projected = [transform(p) for p in points]
            for offset in range(0, len(indices), 3):
                a, b, c = [projected[i] for i in indices[offset:offset+3]]
                denominator = (b[1]-c[1])*(a[0]-c[0]) + (c[0]-b[0])*(a[1]-c[1])
                if abs(denominator) < 1e-9:
                    continue
                # Compute a camera-space normal before the screen scale/flip.
                u = [(b[0]-a[0])/scale, -(b[1]-a[1])/scale, b[2]-a[2]]
                v = [(c[0]-a[0])/scale, -(c[1]-a[1])/scale, c[2]-a[2]]
                n = [u[1]*v[2]-u[2]*v[1], u[2]*v[0]-u[0]*v[2], u[0]*v[1]-u[1]*v[0]]
                norm = math.sqrt(sum(t*t for t in n))
                if norm < 1e-12:
                    continue
                brightness = 0.45+0.55*abs((n[0]*0.4+n[1]*0.7+n[2]*0.59)/norm)
                color = bytes(min(255, max(0, int(channel*brightness))) for channel in base)
                left = max(view*view_width, int(math.floor(min(a[0], b[0], c[0]))))
                right = min((view+1)*view_width-1, int(math.ceil(max(a[0], b[0], c[0]))))
                top = max(0, int(math.floor(min(a[1], b[1], c[1]))))
                bottom = min(height-1, int(math.ceil(max(a[1], b[1], c[1]))))
                for y in range(top, bottom+1):
                    for x in range(left, right+1):
                        aa = ((b[1]-c[1])*(x+0.5-c[0])+(c[0]-b[0])*(y+0.5-c[1]))/denominator
                        bb = ((c[1]-a[1])*(x+0.5-c[0])+(a[0]-c[0])*(y+0.5-c[1]))/denominator
                        cc = 1-aa-bb
                        if min(aa, bb, cc) < -1e-7:
                            continue
                        z = aa*a[2]+bb*b[2]+cc*c[2]
                        pixel = y*width+x
                        if z > depth[pixel]:
                            depth[pixel] = z
                            image[pixel*3:pixel*3+3] = color
        # Dark dividers distinguish front / right side / back projections.
        if view:
            for y in range(height):
                pixel = (y*width+view*view_width)*3
                image[pixel:pixel+3] = bytes([220, 212, 201])
    output_path.parent.mkdir(parents=True, exist_ok=True)
    write_png(output_path, width, height, image)
    print(f"Rendered actual mesh (front / right / back): {output_path}")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("mesh", type=Path)
    parser.add_argument("output", type=Path)
    parser.add_argument("--focus-cloth", action="store_true", help="Frame the actual cloth; keep body geometry unchanged")
    args = parser.parse_args()
    render(args.mesh, args.output, args.focus_cloth)
