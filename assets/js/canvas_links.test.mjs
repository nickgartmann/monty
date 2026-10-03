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
