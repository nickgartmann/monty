import test from "node:test"
import assert from "node:assert/strict"
import {updateCanvasLinks} from "./canvas_links.mjs"

test("connections use viewport-relative coordinates even beyond browser layout limits", () => {
  const cards = [
    {dataset: {metricId: "a", gridX: "1000000000", gridY: "-1000000000"}},
    {dataset: {metricId: "b", gridX: "1000000014", gridY: "-999999992"}},
  ]
  const path = {
    dataset: {sourceId: "a", targetId: "b"},
    getAttribute: () => "",
    setAttribute: (name, value) => { path[name] = value },
  }
  const canvas = {
    dataset: {
      gridStep: "20", gridPadding: "32", gridOriginX: "1000000000", gridOriginY: "-1000000000",
      cardWidth: "240", cardHeight: "120", linkBend: "50",
    },
    contains: () => true,
    querySelectorAll: selector => selector === "[data-metric-id]" ? cards : [path],
  }
  updateCanvasLinks(canvas, undefined, true)
  assert.equal(path.d, "M 272 92 C 322 92, 262 252, 312 252")
})

test("DOM connections undo screen scaling while grid connections stay in world units", () => {
  for (const zoom of [0.5, 2]) {
    const originX = 1_000_000_000, originY = -1_000_000_000
    const cards = [
      {dataset: {metricId: "a", gridX: String(originX + 2), gridY: String(originY + 1)}},
      {dataset: {metricId: "b", gridX: String(originX + 14), gridY: String(originY + 8)}},
    ]
    const path = {
      dataset: {sourceId: "a", targetId: "b"},
      getAttribute: () => path.d,
      setAttribute: (name, value) => { path[name] = value },
    }
    const canvas = {
      dataset: {
        gridStep: "20", gridPadding: "32", gridOriginX: String(originX),
        gridOriginY: String(originY), canvasZoom: String(zoom),
        cardWidth: "240", cardHeight: "120", linkBend: "50",
      },
      getBoundingClientRect: () => ({left: 123, top: -47}),
      contains: () => true,
      querySelectorAll: selector => selector === "[data-metric-id]" ? cards : [path],
    }
    const rect = (left, top) => ({
      left: 123 + left * zoom, top: -47 + top * zoom,
      width: 240 * zoom, height: 120 * zoom,
    })
    cards[0].getBoundingClientRect = () => rect(72, 52)
    cards[1].getBoundingClientRect = () => rect(312, 192)
    updateCanvasLinks(canvas, undefined, true)
    const fromGrid = path.d
    assert.equal(fromGrid, "M 312 112 C 362 112, 262 252, 312 252")
    path.d = "stale"
    updateCanvasLinks(canvas)
    assert.equal(path.d, fromGrid)

    // CSS interpolation moves the card by screen pixels, but the SVG path is
    // still expressed in unscaled world coordinates.
    cards[0].getBoundingClientRect = () => rect(92, 72)
    updateCanvasLinks(canvas)
    assert.equal(path.d, "M 332 132 C 382 132, 262 252, 312 252")
  }
})
