"""Small image helpers for FightingLab review material.

  python media.py gif   <out.gif> <frame1.png> [<frame2.png> ...] [--ms 100] [--width 960]
  python media.py sheet <out.png> <img1.png> [<img2.png> ...] [--cols 4] [--width 480] [--labels]
"""
import argparse
import os

from PIL import Image, ImageDraw


def load(path, width):
    img = Image.open(path).convert("RGB")
    if width and img.width != width:
        img = img.resize((width, round(img.height * width / img.width)), Image.LANCZOS)
    return img


def make_gif(out, frames, ms, width):
    imgs = [load(p, width) for p in frames]
    pal = [im.quantize(colors=256, method=Image.MEDIANCUT, dither=Image.FLOYDSTEINBERG) for im in imgs]
    pal[0].save(out, save_all=True, append_images=pal[1:], duration=ms, loop=0, optimize=True)
    print(f"{out}: {len(imgs)} frames, {os.path.getsize(out) // 1024} KB")


def make_sheet(out, images, cols, width, labels):
    imgs = [load(p, width) for p in images]
    h = max(im.height for im in imgs)
    rows = (len(imgs) + cols - 1) // cols
    sheet = Image.new("RGB", (cols * width, rows * h), (24, 24, 28))
    draw = ImageDraw.Draw(sheet)
    for i, (im, path) in enumerate(zip(imgs, images)):
        x, y = (i % cols) * width, (i // cols) * h
        sheet.paste(im, (x, y))
        if labels:
            draw.text((x + 6, y + 6), os.path.splitext(os.path.basename(path))[0], fill=(255, 220, 90))
    sheet.save(out)
    print(f"{out}: {len(imgs)} tiles")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("mode", choices=["gif", "sheet"])
    ap.add_argument("out")
    ap.add_argument("inputs", nargs="+")
    ap.add_argument("--ms", type=int, default=100)
    ap.add_argument("--width", type=int, default=960)
    ap.add_argument("--cols", type=int, default=4)
    ap.add_argument("--labels", action="store_true")
    a = ap.parse_args()
    if a.mode == "gif":
        make_gif(a.out, a.inputs, a.ms, a.width)
    else:
        make_sheet(a.out, a.inputs, a.cols, a.width, a.labels)


if __name__ == "__main__":
    main()
