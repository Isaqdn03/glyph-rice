#!/usr/bin/python3 -I
# local: the Kraken Z's screen face for services/Rgb.qml — a Glyph dial. Coolant temperature as a 5x7 dot matrix (the
# same glyphs as components/DotClock), a ring of dots lit by how warm it is from LO to HI °C with the head a size up in
# the lights' colour, a Space Mono label under it. Black, so the round panel's edge disappears. 320x320 PNG; liquidctl
# resizes and rotates it on upload.
#
#   kraken.py <temp °C> <out.png> <fg> <dim> <grey> <head>     colours as RRGGBB
import math, os, subprocess, sys
from PIL import Image, ImageDraw, ImageFont

LO, HI = 20, 50       # the ring's span, °C — coolant sits ~25-40
SIZE, SS = 320, 4     # panel px; drawn 4x and scaled down so the dots come out round
N = 48                # ring dots

GLYPHS = {
    "0": ["01110", "10001", "10001", "10001", "10001", "10001", "01110"],
    "1": ["00100", "01100", "00100", "00100", "00100", "00100", "01110"],
    "2": ["01110", "10001", "00001", "00010", "00100", "01000", "11111"],
    "3": ["11110", "00001", "00001", "01110", "00001", "00001", "11110"],
    "4": ["00010", "00110", "01010", "10010", "11111", "00010", "00010"],
    "5": ["11111", "10000", "11110", "00001", "00001", "10001", "01110"],
    "6": ["00110", "01000", "10000", "11110", "10001", "10001", "01110"],
    "7": ["11111", "00001", "00010", "00100", "01000", "01000", "01000"],
    "8": ["01110", "10001", "10001", "01110", "10001", "10001", "01110"],
    "9": ["01110", "10001", "10001", "01111", "00001", "00010", "01100"],
}


def rgb(h):
    return tuple(int(h[i:i + 2], 16) for i in (0, 2, 4))


def main():
    temp, out = float(sys.argv[1]), sys.argv[2]
    fg, dim, grey, head = (rgb(h) for h in sys.argv[3:7])
    s = SIZE * SS
    img = Image.new("RGB", (s, s), (0, 0, 0))
    d = ImageDraw.Draw(img)

    def dot(cx, cy, diam, col):
        r = diam * SS / 2
        d.ellipse((cx * SS - r, cy * SS - r, cx * SS + r, cy * SS + r), fill=col)

    # ring: clockwise from the top, like prefs' dials
    lit = round(N * max(0, min(1, (temp - LO) / (HI - LO))))
    for i in range(N):
        a = i / N * 2 * math.pi - math.pi / 2
        x, y = SIZE / 2 + 140 * math.cos(a), SIZE / 2 + 140 * math.sin(a)
        if i == lit - 1:
            dot(x, y, 13, head)
        else:
            dot(x, y, 7.5, fg if i < lit else dim)

    # the number: whole degrees, centred together with the label under it
    text = str(max(0, min(99, round(temp))))
    p, g = 11, 5.5    # dot, gap
    gw, sp, dh = 5 * p + 4 * g, 2.4 * p, 7 * p + 6 * g
    w = len(text) * gw + (len(text) - 1) * sp
    x0, y0 = (SIZE - w) / 2, (SIZE - dh - 39) / 2   # 39: the label's gap and line
    for k, ch in enumerate(text):
        for r, row in enumerate(GLYPHS[ch]):
            for c, bit in enumerate(row):
                if bit == "1":
                    dot(x0 + k * (gw + sp) + c * (p + g) + p / 2, y0 + r * (p + g) + p / 2, p, fg)
    # degree: a small ring of dots at the top right of the number
    for i in range(6):
        a = i / 6 * 2 * math.pi
        dot(x0 + w + 14 + 5 * math.cos(a), y0 + 6 + 5 * math.sin(a), 3, fg)

    # label: Space Mono caps, tracked .14em like Lb
    font_path = subprocess.run(["fc-match", "-f", "%{file}", "Space Mono:style=Regular"],
                               capture_output=True, text=True).stdout.strip()
    if font_path and os.path.exists(font_path):
        px = 13
        font = ImageFont.truetype(font_path, px * SS)
        label = "LIQUID"
        track = px * 0.14 * SS * 2.2
        widths = [d.textlength(ch, font=font) for ch in label]
        lw = sum(widths) + track * (len(label) - 1)
        x, y = (s - lw) / 2, (y0 + dh + 22) * SS
        for ch, cw in zip(label, widths):
            d.text((x, y), ch, font=font, fill=grey)
            x += cw + track

    img = img.resize((SIZE, SIZE), Image.LANCZOS)
    tmp = out + ".tmp.png"
    img.save(tmp)
    os.replace(tmp, out)


if __name__ == "__main__":
    main()
