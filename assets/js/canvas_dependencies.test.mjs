import test from "node:test"
import assert from "node:assert/strict"
import {CanvasDependencies, upstreamPaths} from "./canvas_dependencies.mjs"

function path(sourceId, targetId) {
  const classes = new Set(["dependency-path"])
  return {
    dataset: {sourceId, targetId},
    classList: {
      toggle(name, enabled) { enabled ? classes.add(name) : classes.delete(name) },
      remove(name) { classes.delete(name) },
      contains(name) { return classes.has(name) },
    },
  }
}

function edges(paths) {
  return [...paths].map(p => `${p.dataset.sourceId}->${p.dataset.targetId}`).sort()
}

function fixture(t) {
  const listeners = new Map()
  const doc = {
    addEventListener(type, listener) { listeners.set(type, listener) },
    removeEventListener(type, listener) {
      if (listeners.get(type) === listener) listeners.delete(type)
    },
  }
  const cards = ["A", "B", "C", "D", "E"].map(metricId => {
    const card = {dataset: {metricId}}
    card.closest = () => card
    return card
  })
  const paths = [path("A", "C"), path("B", "C"), path("C", "D"), path("C", "E")]
  const canvas = {
    contains: card => cards.includes(card),
    querySelectorAll: selector => selector === "[data-metric-id]" ? cards : paths,
  }
  const dependencies = new CanvasDependencies({host: {ownerDocument: doc}, getCanvas: () => canvas})
  dependencies.mount()
  t.after(() => dependencies.destroy())
  const emit = (type, target, relatedTarget = null, pointerType = "mouse") =>
    listeners.get(type)?.({target, relatedTarget, pointerType})
  const highlighted = () => edges(paths.filter(p => p.classList.contains("dependency-path-highlighted")))
  return {dependencies, cards, paths, listeners, emit, highlighted}
}

test("traces the entire upstream chain, excluding outgoing edges and unrelated branches", () => {
  const paths = [
    path("D", "H"), path("S", "H"),
    ...["R", "L", "O", "Q", "C"].map(source => path(source, "S")),
    path("K", "R"), path("N", "R"), path("Q", "R"), path("C", "R"),
    path("J", "K"), path("I", "K"), path("M", "N"), path("I", "N"),
    path("A", "J"), path("I", "J"), path("B", "M"), path("I", "M"),
    path("K", "L"), path("I", "L"), path("N", "O"), path("I", "O"),
    path("P", "Q"), path("J", "Q"), path("M", "Q"), path("C", "Q"),
    path("A", "P"), path("B", "P"), path("C", "P"),
  ]
  const unrelated = [path("H", "output"), path("D", "E"), path("X", "Y")]
  assert.deepEqual(edges(upstreamPaths([...paths, ...unrelated], "H")), edges(paths))
})

test("shared ancestors, duplicate edges, cycles, and inputs terminate safely", () => {
  const paths = [path("A", "B"), path("A", "C"), path("B", "D"), path("C", "D"), path("B", "D")]
  assert.equal(upstreamPaths(paths, "D").size, 5)
  assert.equal(upstreamPaths(paths, "A").size, 0)
  assert.equal(upstreamPaths(paths, null).size, 0)
  assert.equal(upstreamPaths([], "D").size, 0)
  const cycle = [...paths, path("D", "A")]
  assert.equal(upstreamPaths(cycle, "D").size, 6)
})

test("hovering card descendants highlights ancestors, switches chains, and clears on leave", t => {
  const f = fixture(t)
  const [, , c, d] = f.cards
  const child = {closest: () => d}
  assert.deepEqual(f.highlighted(), [])
  f.emit("pointerover", child)
  assert.deepEqual(f.highlighted(), ["A->C", "B->C", "C->D"])
  f.emit("pointerout", child, d)
  assert.deepEqual(f.highlighted(), ["A->C", "B->C", "C->D"])
  f.emit("pointerout", d, c)
  assert.deepEqual(f.highlighted(), ["A->C", "B->C"])
  f.emit("pointerout", c)
  assert.deepEqual(f.highlighted(), [])
})

test("keyboard focus highlights dependencies, with hover taking precedence", t => {
  const f = fixture(t)
  const [a, , , d, e] = f.cards
  f.emit("focusin", d)
  assert.deepEqual(f.highlighted(), ["A->C", "B->C", "C->D"])
  f.emit("pointerover", e)
  assert.deepEqual(f.highlighted(), ["A->C", "B->C", "C->E"])
  f.emit("pointerover", a)
  assert.deepEqual(f.highlighted(), [])
  f.emit("pointerout", a)
  assert.deepEqual(f.highlighted(), ["A->C", "B->C", "C->D"])
  f.emit("focusout", d)
  assert.deepEqual(f.highlighted(), [])
})

test("LiveView patches refresh changed and replaced paths without needing another hover", t => {
  const f = fixture(t)
  f.emit("pointerover", f.cards[3])
  f.paths.splice(0, f.paths.length, path("B", "D"), path("A", "B"), path("D", "E"))
  f.emit("phx:update")
  assert.deepEqual(f.highlighted(), ["A->B", "B->D"])
  f.paths[0].classList.remove("dependency-path-highlighted")
  f.emit("phx:update")
  assert.deepEqual(f.highlighted(), ["A->B", "B->D"])
  f.cards.splice(3, 1)
  f.emit("phx:update")
  assert.deepEqual(f.highlighted(), [])
})

test("touch hover and cards outside this canvas do not highlight paths", t => {
  const f = fixture(t)
  f.emit("pointerover", f.cards[3], null, "touch")
  assert.deepEqual(f.highlighted(), [])
  const outside = {dataset: {metricId: "D"}, closest() { return this }}
  f.emit("pointerover", outside)
  f.emit("focusin", outside)
  assert.deepEqual(f.highlighted(), [])
})

test("destroy removes listeners and highlights", t => {
  const f = fixture(t)
  f.emit("pointerover", f.cards[3])
  f.dependencies.destroy()
  assert.equal(f.listeners.size, 0)
  assert.deepEqual(f.highlighted(), [])
})
