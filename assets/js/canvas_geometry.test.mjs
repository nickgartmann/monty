import test from "node:test"
import assert from "node:assert/strict"
import {centeredPosition, readGeometry, snapPosition} from "./canvas_geometry.mjs"

const geometry = {step: 20, padding: 32, originX: 0, originY: 0}

test("new cards are centered on the double-click point and snapped to the grid", () => {
  assert.deepEqual(centeredPosition({left: 392, top: 212}, {width: 240, height: 120}, geometry), {x: 12, y: 6})
  assert.deepEqual(centeredPosition({left: 10, top: 10}, {width: 240, height: 120}, geometry), {x: -7, y: -4})
  assert.deepEqual(centeredPosition({left: 100_000, top: 100_000}, {width: 240, height: 120}, geometry), {x: 4992, y: 4995})
})

test("geometry is read from the current server-rendered canvas", () => {
  assert.deepEqual(readGeometry({gridStep: "20", gridPadding: "32"}), geometry)
})

test("old or malformed markup is rejected rather than generating NaN drag coordinates", () => {
  const current = {gridStep: "20", gridPadding: "32"}
  for (const dataset of [
    undefined,
    {},
    {...current, gridStep: undefined},
    {...current, gridStep: ""},
    {...current, gridStep: "0"},
    {...current, gridStep: "NaN"},
    {...current, gridPadding: "Infinity"},
    {...current, gridPadding: "-1"},
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

test("snapped positions extend in all directions without a finite canvas boundary", () => {
  assert.deepEqual(snapPosition({left: -200, top: -500}, geometry), {x: -12, y: -27})
  assert.deepEqual(snapPosition({left: 100_000, top: 100_000}, geometry), {x: 4998, y: 4998})
})

test("a rebased viewport converts local pixels back to distant canonical coordinates", () => {
  const grid = readGeometry({
    gridStep: "20", gridPadding: "32", gridOriginX: "1000000000", gridOriginY: "-1000000000",
  })
  assert.deepEqual(snapPosition({left: 72, top: 12}, grid), {x: 1_000_000_002, y: -1_000_000_001})
})
