#!/usr/bin/env python3
"""Self-check for scroll-stitch.py on synthetic frames: a tall page cut into
overlapping windows with a sticky header and footer, a moving scrollbar, a
fixed sidebar on the left or right, a blinking cursor, blank gaps, a repeated
frame, a scroll back up, one jump too far to match and a translucent background.
    tests/scroll-stitch.test.py
"""
import importlib.util
import pathlib
import random

from PIL import Image, ImageChops, ImageDraw, ImageStat

here = pathlib.Path(__file__).parent
specification = importlib.util.spec_from_file_location("scroll_stitch", here.parent / "scroll-stitch.py")
scroll_stitch = importlib.util.module_from_spec(specification)
specification.loader.exec_module(scroll_stitch)

WIDTH, VIEW, HEADER, FOOTER, SIDEBAR, RIGHT_PANE = 200, 120, 16, 10, 30, 80
PAGE = VIEW - HEADER - FOOTER
FOOTER_COLOUR = (166, 227, 161)
random.seed(7)

# The page: random "text" lines with blank gaps between some of them.
page = Image.new("RGB", (WIDTH, 900), "#1e1e2e")
draw = ImageDraw.Draw(page)
y = 0
while y < 900:
    if random.random() < 0.2:
        y += random.randint(6, 30)
        continue
    for x in range(4, WIDTH - 30, 6):
        if random.random() < 0.7:
            draw.rectangle((x, y, x + 4, y + 7), fill=(random.randint(80, 255), random.randint(80, 255), 200))
    y += 10


def pane(width):
    """A sidebar or second pane: its own "text" that never scrolls."""
    image = Image.new("RGB", (width, PAGE), "#181825")
    for y in range(2, PAGE - 8, 12):
        ImageDraw.Draw(image).rectangle((4, y, random.randint(8, width - 4), y + 7), fill="#a6adc8")
    return image


sidebar = pane(SIDEBAR)
right_pane = pane(RIGHT_PANE)


def frame(offset, cursor=False, with_sidebar=False, with_right_pane=False):
    """What the screen shows scrolled to `offset`: the header on top, the footer
    at the bottom, the page between them, a scrollbar thumb at the right edge
    that moves with the offset, the sidebar over the left edge if asked, and a
    static pane over the right edge in place of the scrollbar if asked."""
    view = Image.new("RGB", (WIDTH, VIEW))
    view.paste(page.crop((0, offset, WIDTH, offset + PAGE)), (0, HEADER))
    if with_sidebar:
        view.paste(sidebar, (0, HEADER))
    paint = ImageDraw.Draw(view)
    paint.rectangle((0, 0, WIDTH, HEADER - 1), fill="#b4befe")
    paint.rectangle((0, VIEW - FOOTER, WIDTH, VIEW), fill=FOOTER_COLOUR)
    if with_right_pane:
        view.paste(right_pane, (WIDTH - RIGHT_PANE, HEADER))
    else:
        paint.rectangle((WIDTH - 6, HEADER, WIDTH, VIEW - FOOTER - 1), fill="#313244")
        thumb = HEADER + offset * (PAGE - 20) // (900 - PAGE)
        paint.rectangle((WIDTH - 6, thumb, WIDTH, thumb + 20), fill="#cdd6f4")
    if cursor:
        paint.rectangle((10, 40, 12, 42), fill="#f5e0dc")
    return view


def expected(last_offset, left=0, right=scroll_stitch.SCROLLBAR_COLUMNS):
    """The page from the top down to the bottom of the last view, under the header."""
    return page.crop((left, 0, WIDTH - right, last_offset + PAGE))


def check(offsets, cursor_frames=(), last=None, skipped_expected=0, with_sidebar=False, with_right_pane=False):
    """`last`: the offset of the last frame kept, the furthest one by default."""
    frames = [
        frame(offset, index in cursor_frames, with_sidebar, with_right_pane) for index, offset in enumerate(offsets)
    ]
    result, skipped = scroll_stitch.stitch(frames)
    last = max(offsets) if last is None else last
    assert skipped == skipped_expected, (offsets, skipped)
    assert result.size == (WIDTH, last + VIEW), (offsets, result.size)
    assert result.crop((0, 0, WIDTH, HEADER)).getcolors() == [(WIDTH * HEADER, (180, 190, 254))]
    footer = result.crop((0, result.height - FOOTER, WIDTH, result.height))
    assert footer.getcolors() == [(WIDTH * FOOTER, FOOTER_COLOUR)], offsets
    left = SIDEBAR if with_sidebar else 0
    right = RIGHT_PANE if with_right_pane else scroll_stitch.SCROLLBAR_COLUMNS
    body = result.crop((left, HEADER, WIDTH - right, result.height - FOOTER))
    assert body.tobytes() == expected(last, left, right).tobytes(), offsets


# Even steps, uneven steps, a repeated frame and a scroll back up.
check([0, 40, 80, 120, 160])
check([0, 3, 57, 57, 101, 60, 140, 200, 260, 310, 370, 430, 490, 550, 610, 670, 730, 780])
# A cursor blinking in one frame still lines up.
check([0, 50, 100, 150], cursor_frames={2})
# A jump of more than a view is left out, and the next frame that overlaps the
# last kept one resumes the stitch.
check([0, 50, 400, 100], last=100, skipped_expected=1)
# A fixed sidebar beside the scrolling page is left out of the matching.
check([0, 40, 80, 120, 160, 200, 240, 280], with_sidebar=True)
# So is a static pane at the right edge, where there is no scrollbar.
check([0, 40, 80, 120, 160, 200, 240, 280], with_right_pane=True)
# A translucent window: a wallpaper that stays put shows through at 10 %, so no
# row is ever identical after a scroll. The stitch still lines up; each piece
# keeps its own bit of wallpaper, so it is checked against the page loosely.
wallpaper = Image.radial_gradient("L").resize((WIDTH, VIEW)).convert("RGB")
offsets = [0, 30, 75, 120, 170]
frames = [Image.blend(frame(offset), wallpaper, 0.1) for offset in offsets]
result, skipped = scroll_stitch.stitch(frames)
assert skipped == 0 and result.height == 170 + VIEW, (skipped, result.height)
body = result.crop((0, HEADER, WIDTH - scroll_stitch.SCROLLBAR_COLUMNS, result.height - FOOTER)).convert("L")
reference = expected(170).convert("L")
assert ImageStat.Stat(ImageChops.difference(body, reference)).mean[0] < 15
# One frame is returned as it is.
assert scroll_stitch.stitch([frame(0)])[0].size == (WIDTH, VIEW)
print("ok")
