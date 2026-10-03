import test from "node:test"
import assert from "node:assert/strict"
import {primaryButtonReleased} from "./canvas_pointer.mjs"

test("the primary-button bit, not all held buttons, determines release", () => {
  for (const buttons of [0, 2, 4, 6, 32]) assert.equal(primaryButtonReleased({buttons}), true)
  for (const buttons of [1, 3, 5, 7, 33]) assert.equal(primaryButtonReleased({buttons}), false)
})

test("missing or invalid button state is not interpreted as a release", () => {
  for (const buttons of [undefined, null, NaN, Infinity, -1, 0.5, "0"]) {
    assert.equal(primaryButtonReleased({buttons}), false)
  }
})
