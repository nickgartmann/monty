import test from "node:test"
import assert from "node:assert/strict"
import {centeredPosition, clampPosition, readGeometry, snapPosition} from "./canvas_geometry.mjs"

const geometry = {step: 20, padding: 32, maxX: 200, maxY: 1200}

test("new cards are centered on the double-click point and snapped to the grid", () => {
  assert.deepEqual(centeredPosition({left: 392, top: 212}, {width: 240, height: 120}, geometry), {x: 12, y: 6})
  assert.deepEqual(centeredPosition({left: 10, top: 10}, {width: 240, height: 120}, geometry), {x: 0, y: 0})
  assert.deepEqual(centeredPosition({left: 100_000, top: 100_000}, {width: 240, height: 120}, geometry), {x: 200, y: 1200})
})

test("geometry is read from the current server-rendered canvas", () => {
  assert.deepEqual(readGeometry({gridStep: "20", gridPadding: "32", gridMaxX: "200", gridMaxY: "1200"}), geometry)
})

test("old or malformed markup is rejected rather than generating NaN drag coordinates", () => {
  const current = {gridStep: "20", gridPadding: "32", gridMaxX: "200", gridMaxY: "1200"}
  for (const dataset of [
    undefined,
    {},
    {...current, gridStep: undefined},
    {...current, gridStep: ""},
    {...current, gridStep: "0"},
    {...current, gridStep: "NaN"},
    {...current, gridMaxY: "Infinity"},
    {...current, gridMaxX: "-1"},
    {...current, gridPadding: "1.5"},
  ]) {
    assert.equal(readGeometry(dataset), null)
  }
})

test("both axes snap to the nearest dot, rather than the next card-sized cell", () => {
  assert.deepEqual(snapPosition({left: 312, top: 152}, geometry), {x: 14, y: 6})
  assert.deepEqual(snapPosition({left: 313, top: 148}, geometry), {x: 14, y: 6})
  assert.deepEqual(snapPosition({left: 329, top: 169}, geometry), {x: 15, y: 7})
})

test("a 20px movement is one grid increment on either axis", () => {
  const before = snapPosition({left: 312, top: 252}, geometry)
  const after = snapPosition({left: 332, top: 272}, geometry)
  assert.equal(after.x - before.x, 1)
  assert.equal(after.y - before.y, 1)
})

test("snapped positions and keyboard nudges remain within server bounds", () => {
  assert.deepEqual(snapPosition({left: -200, top: -500}, geometry), {x: 0, y: 0})
  assert.deepEqual(snapPosition({left: 100_000, top: 100_000}, geometry), {x: 200, y: 1200})
  assert.deepEqual(clampPosition({x: -1, y: 1201}, geometry), {x: 0, y: 1200})
})
