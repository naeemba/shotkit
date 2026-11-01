.pragma library
// Geometry for the scrolling capture overlay (overlay/shell.qml): the region
// slurp picked, and where its Start/Stop bar goes. Pure, so
// tests/geometry.test.mjs runs it under node.

// slurp's "X,Y WxH" as {x, y, width, height}, or null.
function parseGeometry(text) {
    const match = /^(-?\d+),(-?\d+) (\d+)x(\d+)$/.exec(String(text).trim());
    if (!match)
        return null;
    return { x: Number(match[1]), y: Number(match[2]), width: Number(match[3]), height: Number(match[4]) };
}

function contains(screen, x, y) {
    return x >= screen.x && x < screen.x + screen.width && y >= screen.y && y < screen.y + screen.height;
}

// Where a bar of `size` goes for `region`, both in global logical pixels:
// {screen, x, y, inside}, the screen from `screens` and the bar's top left on
// it. It sits `gap` below the region, or above it when there is no room below,
// so grim never sees it. A region as tall as the screen leaves no room either
// way; the bar then goes inside along the bottom and `inside` is true, and the
// overlay hides it once grabbing starts.
function controlsPlacement(region, screens, size, gap) {
    const centerX = region.x + region.width / 2;
    const bottom = region.y + region.height;
    let index = screens.findIndex(screen => contains(screen, centerX, bottom - 1));
    if (index < 0)
        index = screens.findIndex(screen => contains(screen, centerX, region.y + region.height / 2));
    if (index < 0)
        index = 0;
    const screen = screens[index];
    let y = bottom + gap;
    if (y + size.height > screen.y + screen.height - gap)
        y = region.y - gap - size.height;
    const inside = y < screen.y + gap;
    if (inside)
        y = bottom - gap - size.height;
    const x = Math.max(screen.x + gap, Math.min(centerX - size.width / 2, screen.x + screen.width - gap - size.width));
    return { screen, x: Math.round(x - screen.x), y: Math.round(y - screen.y), inside };
}
