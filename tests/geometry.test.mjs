import { test } from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import vm from "node:vm";

// overlay/geometry.js is a QML JavaScript library: run it as a plain script,
// its pragma dropped, so its top-level functions land on `capture`.
const capture = {};
vm.runInNewContext(
  readFileSync(new URL("../overlay/geometry.js", import.meta.url), "utf8").replace(/^\.pragma library$/m, ""),
  capture,
);
// A value from the library's context as a plain one, for deepEqual.
const plain = value => JSON.parse(JSON.stringify(value));
// Two 1920x1080 monitors side by side.
const screens = [{ x: 0, y: 0, width: 1920, height: 1080 }, { x: 1920, y: 0, width: 1920, height: 1080 }];
const bar = { width: 300, height: 40 };
// The screen as its index into `screens`, for deepEqual.
const place = (region, layout = screens) => {
  const placement = capture.controlsPlacement(region, layout, bar, 12);
  return { ...plain(placement), screen: layout.indexOf(placement.screen) };
};

test("parseGeometry reads slurp's output", () => {
  assert.deepEqual(plain(capture.parseGeometry("10,-20 300x400\n")), { x: 10, y: -20, width: 300, height: 400 });
  assert.equal(capture.parseGeometry(""), null);
  assert.equal(capture.parseGeometry("selection cancelled"), null);
});

test("the bar goes under the region, centered", () => {
  assert.deepEqual(place({ x: 100, y: 100, width: 600, height: 400 }), { screen: 0, x: 250, y: 512, inside: false });
});

test("the bar goes above a region that reaches the bottom", () => {
  assert.deepEqual(place({ x: 100, y: 300, width: 600, height: 780 }), { screen: 0, x: 250, y: 248, inside: false });
});

test("a full-height region keeps the bar inside along the bottom, marked inside", () => {
  assert.deepEqual(place({ x: 0, y: 0, width: 1920, height: 1080 }), { screen: 0, x: 810, y: 1028, inside: true });
});

test("the bar stays on screen and on the region's monitor", () => {
  assert.deepEqual(place({ x: 1930, y: 100, width: 100, height: 100 }), { screen: 1, x: 12, y: 212, inside: false });
  assert.deepEqual(place({ x: 3800, y: 100, width: 40, height: 100 }), { screen: 1, x: 1608, y: 212, inside: false });
});

test("a region off every screen's bottom edge falls back to its middle, then the first screen", () => {
  // 2560x1440 beside a shorter 1920x1080, so a region's bottom can hang below the short one.
  const uneven = [{ x: 0, y: 0, width: 2560, height: 1440 }, { x: 2560, y: 0, width: 1920, height: 1080 }];
  // Bottom-center (2750,1400) is on no screen; the middle (2750,950) is on the short one.
  assert.deepEqual(place({ x: 2000, y: 500, width: 1500, height: 900 }, uneven), { screen: 1, x: 40, y: 448, inside: false });
  // Neither the bottom-center nor the middle (2750,1150) is on a screen.
  assert.deepEqual(place({ x: 2000, y: 900, width: 1500, height: 500 }, uneven), { screen: 0, x: 2248, y: 848, inside: false });
});
