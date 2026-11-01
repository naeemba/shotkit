#!/usr/bin/env python3
"""Stitch the frames of a scrolling capture into one tall image.

    scroll-stitch.py output.png frame1.ppm frame2.ppm ...

The frames are grabs of the same screen region taken while the page scrolls
(shotkit scroll). Each frame is matched against the last frame kept, by
finding how many rows the content moved, and only the rows it brought into view
are appended.

Frames are compared as narrow strips of their edges: grey, minus a blurred copy
of itself (so only text and lines remain, not smooth backgrounds), squeezed to
32 columns at full height so a one-row shift still shows. A shift is accepted
when the overlapping rows differ by about a grey level on average; on real
terminal frames the right shift scores about 0.2 and every wrong one about 2 or
more. What breaks naive stitching, and what is done about it:

- A translucent window (the terminal at 0.9 opacity): the wallpaper behind it
  stays put while the text moves, so no two rows are ever identical. The blur
  subtraction removes the smooth wallpaper. The pasted pieces still carry their
  own bit of wallpaper, so faint seams can show in it.
- A sticky header or footer, a status line, a prompt: rows that stay the same
  across every pair of frames are found first and left out of the matching. The
  header is taken from the first frame, the footer from the last.
- A fixed sidebar, a file tree, a second tmux pane: columns at the left or
  right edge that stay the same across every pair of frames are left out of the
  matching the same way. In the result each piece keeps its own slice of them.
- A scrollbar at the right edge changes as it moves, so the right-most columns
  are left out of the comparison.
- Animations, a blinking cursor: they add a little difference to a few rows,
  which the average absorbs. A large animated area makes frames unmatchable;
  they are skipped.
- Smooth scrolling: every grab is a finished frame, so a frame taken mid-scroll
  is just a smaller shift. Scrolling back up gives a negative shift; that frame
  is skipped and matching resumes once the page is back below the last kept one.
- Scrolling faster than a frame: less than a fifth of the region overlaps, the
  frame is skipped, and the count of skipped frames goes to stderr.
- Repeated or blank content: several shifts fit equally well; on a tie the one
  nearest the last movement wins, since a hand scrolls at a steady pace.
"""
import sys

from PIL import Image, ImageChops, ImageFilter, ImageStat

SCROLLBAR_COLUMNS = 24
# The edges are the grey minus a box blur of this radius.
BLUR_RADIUS = 2
STRIP_COLUMNS = 32
# Mean grey-level difference, out of 255.
STATIC_TOLERANCE = 3
MATCH_TOLERANCE = 1.0
# A shift is only trusted when this much of the band overlaps.
MINIMUM_OVERLAP = 0.2


def load(frame, mode="RGB"):
    """A frame in `mode`: an Image, or a path read from disk."""
    if isinstance(frame, Image.Image):
        return frame.convert(mode)
    with Image.open(frame) as image:
        return image.convert(mode)


def edge_run(values):
    """How many of `values`, from the start, are at most STATIC_TOLERANCE."""
    count = 0
    while count < len(values) and values[count] <= STATIC_TOLERANCE:
        count += 1
    return count


def static_columns(images):
    """(left, right): how many columns at the left and right edges stay the
    same in every pair of consecutive frames, measured on the full-width grey
    frames, one pair in memory at a time. (0, 0) when that leaves too little."""
    previous = load(images[0], "L")
    width = previous.width
    worst = [0] * width
    for image in images[1:]:
        current = load(image, "L")
        difference = ImageChops.difference(previous, current)
        columns = difference.resize((width, 1), Image.BOX).tobytes()
        worst = [max(pair) for pair in zip(worst, columns)]
        previous = current
    left = edge_run(worst)
    right = edge_run(worst[::-1])
    if width - left - right < SCROLLBAR_COLUMNS * 4:
        return 0, 0
    return left, right


def strip(frame, left=0, right=0):
    """The frame's edges as STRIP_COLUMNS grey columns, the `left` and `right`
    static columns and the scrollbar left out."""
    grey = load(frame, "L")
    width, height = grey.size
    used = width - left - right
    if used > SCROLLBAR_COLUMNS * 4:
        used -= SCROLLBAR_COLUMNS
    grey = grey.crop((left, 0, left + used, height))
    edges = ImageChops.difference(grey, grey.filter(ImageFilter.BoxBlur(BLUR_RADIUS)))
    return edges.resize((STRIP_COLUMNS, height), Image.BOX)


def row_differences(first, second):
    """Mean grey difference of each row between two strips."""
    difference = ImageChops.difference(first, second)
    return list(difference.resize((1, difference.height), Image.BOX).tobytes())


def static_bands(strips):
    """(header, footer): how many rows at the top and bottom stay the same in
    every pair of consecutive frames. The last BLUR_RADIUS rows of a band blur
    in the first row that moves, so their edges change too; they are added back."""
    height = strips[0].height
    worst = [0] * height
    for first, second in zip(strips, strips[1:]):
        worst = [max(pair) for pair in zip(worst, row_differences(first, second))]

    def band_rows(rows, room):
        return min(room, rows + BLUR_RADIUS) if rows else 0

    header = band_rows(edge_run(worst), height)
    footer = band_rows(edge_run(worst[header:][::-1]), height - header)
    return header, footer


def difference_at(previous, current, shift):
    """Mean grey difference where `current` row y lies over `previous` row y + shift."""
    height = current.height
    top, bottom = max(0, -shift), min(height, height - shift)
    width = current.width
    upper = previous.crop((0, top + shift, width, bottom + shift))
    lower = current.crop((0, top, width, bottom))
    return ImageStat.Stat(ImageChops.difference(upper, lower)).mean[0]


def find_shift(previous, current, expected=0):
    """How many rows the content moved up from `previous` to `current` (strips
    of the scrolling band), or None when nothing lines up. A tie goes to the
    shift nearest `expected`, the last movement seen."""
    height = current.height
    reach = height - max(1, int(height * MINIMUM_OVERLAP))
    # Nearest the expected shift first; a clear match ends the search early.
    # A frame taken after the scrolling stopped is caught here at once.
    if difference_at(previous, current, 0) <= MATCH_TOLERANCE / 2:
        return 0
    best, best_score = None, MATCH_TOLERANCE
    for shift in sorted(range(-reach, reach + 1), key=lambda candidate: abs(candidate - expected)):
        score = difference_at(previous, current, shift)
        if score <= MATCH_TOLERANCE / 2:
            return shift
        if score < best_score:
            best, best_score = shift, score
    return best


def stitch(images):
    """The stitched image and how many frames could not be matched. `images`
    are Images or paths; paths are read three times (finding the static
    columns, comparing, then pasting) so a minute of full-screen frames is
    never in memory at once."""
    first = load(images[0])
    if len(images) == 1:
        return first, 0
    width, height = first.size
    left, right = static_columns(images)
    strips = [strip(first, left, right)] + [strip(image, left, right) for image in images[1:]]
    header, footer = static_bands(strips)
    bottom = height - footer
    if bottom - header < 16:
        return first, 0

    # Compared a few rows inside the band: the blur behind the edges reaches
    # across its ends into the header and footer.
    def band(index):
        return strips[index].crop((0, header + 3, STRIP_COLUMNS, bottom - 3))

    # (image, rows to take from the bottom of its band); the first frame whole.
    pieces = [(images[0], bottom - header)]
    last = band(0)
    movement = skipped = 0
    for index in range(1, len(images)):
        current = band(index)
        shift = find_shift(last, current, movement)
        if shift is None:
            skipped += 1
            continue
        if shift <= 0:
            continue
        pieces.append((images[index], shift))
        last, movement = current, shift

    total = header + sum(rows for _, rows in pieces) + footer
    result = Image.new("RGB", (width, total))
    result.paste(first.crop((0, 0, width, header)), (0, 0))
    y = header
    for image, rows in pieces:
        image = load(image)
        result.paste(image.crop((0, bottom - rows, width, bottom)), (0, y))
        y += rows
    result.paste(image.crop((0, bottom, width, height)), (0, y))
    return result, skipped


def main(arguments):
    if len(arguments) < 2:
        sys.exit("usage: scroll-stitch.py output.png frame...")
    result, skipped = stitch(arguments[1:])
    result.save(arguments[0])
    if skipped:
        print(f"{skipped} frame(s) left out", file=sys.stderr)


if __name__ == "__main__":
    main(sys.argv[1:])
