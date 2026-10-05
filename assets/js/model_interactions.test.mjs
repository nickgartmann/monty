import test from "node:test"
import assert from "node:assert/strict"
import {ModelInteractions} from "./model_interactions.js"

function fixture(t) {
  const previousDocument = globalThis.document
  const previousWindow = globalThis.window
  t.after(() => {
    hook.destroyed()
    globalThis.document = previousDocument
    globalThis.window = previousWindow
  })
  const listeners = new Map()
  const events = {
    addEventListener(type, fn) {
      if (!listeners.has(type)) listeners.set(type, new Set())
      listeners.get(type).add(fn)
    },
    removeEventListener(type, fn) { listeners.get(type)?.delete(fn) },
  }
  const win = {...events, setTimeout, clearTimeout, innerHeight: 600}
  const doc = {...events, defaultView: win}
  doc.querySelector = () => null
  doc.createElement = () => ({
    style: {}, classList: {add() {}}, setAttribute() {}, append() {}, remove() {},
  })
  const pane = {
    style: {setProperty() {}}, classList: {toggle() {}},
    contains: () => true,
  }
  const canvas = {
    dataset: {gridStep: "20", gridPadding: "32", cardWidth: "240", cardHeight: "120", editable: "true"},
    closest: () => pane,
    contains: target => target === card || card.contains(target),
    querySelector: () => null,
    querySelectorAll: () => [],
    getBoundingClientRect: () => ({left: 0, top: 0}),
  }
  const card = {
    dataset: {metricId: "card-1", movable: "true", gridX: "2", gridY: "3"},
    getAttribute: () => "false",
    contains: target => target === card || target.card === card,
    closest: selector => selector.includes("[data-metric-id]") ? card : null,
  }
  // Controls have a descendant to exercise bubbling from inside their markup.
  const nested = tag => {
    const controlNode = {card}
    return {
      card,
      closest: selector => selector.includes("[data-metric-id]") ? card
        : selector.split(", ").includes(tag) ? controlNode : null,
    }
  }
  const host = {
    ...events, ownerDocument: doc, dataset: {canvasId: "canvas"}, isConnected: true,
    append() {}, contains: () => false,
  }
  const fields = new Map([["canvas", canvas], ["metric-id", {value: "card-1"}]])
  doc.getElementById = id => fields.get(id)
  globalThis.document = doc
  globalThis.window = win
  const pushed = [], handlers = new Map()
  const hook = {
    ...ModelInteractions, el: host,
    pushEvent(name, payload, callback) { pushed.push({name, payload, callback}) },
    handleEvent(name, callback) { handlers.set(name, callback) },
  }
  hook.mounted()
  const key = (target, value, extra = {}) => {
    const event = {
      target, key: value, preventDefault() { this.defaultPrevented = true }, ...extra,
    }
    hook.keydown(event)
    return event
  }
  return {hook, doc, canvas, pane, card, nested, fields, pushed, handlers, key}
}

test("card root arrows nudge and Enter/Space select, while nested controls keep their keys", t => {
  const f = fixture(t)
  const arrow = f.key(f.card, "ArrowRight")
  assert.equal(arrow.defaultPrevented, true)
  assert.deepEqual(f.pushed.pop(), {name: "move-metric", payload: {id: "card-1", x: 3, y: 3}, callback: undefined})
  for (const tag of ["button", "input", "select", "textarea", "a", "label", "[data-card-controls]"]) {
    const event = f.key(f.nested(tag), "ArrowDown")
    assert.equal(event.defaultPrevented, undefined, tag)
    assert.equal(f.pushed.length, 0, tag)
  }
  for (const value of ["Enter", " "]) {
    assert.equal(f.key(f.card, value).defaultPrevented, true)
    assert.deepEqual(f.pushed.pop(), {name: "select", payload: {id: "card-1"}, callback: undefined})
    assert.equal(f.key(f.nested("button"), value).defaultPrevented, undefined)
  }
  f.card.dataset.movable = "false"
  assert.equal(f.key(f.card, "ArrowRight").defaultPrevented, undefined)
  assert.equal(f.key(f.card, "Enter").defaultPrevented, true)
  assert.equal(f.pushed.pop().name, "select")
})

test("new metric and server edit events focus/select the patched inline field without scrolling", t => {
  const f = fixture(t)
  const calls = []
  const field = {
    focus(options) { calls.push(["focus", options]) },
    select() { calls.push(["select"]) },
  }
  f.fields.set("metric_name", field)
  f.fields.set("metric_input", field)
  f.handlers.get("focus-metric-field")({id: "metric_input"})
  assert.deepEqual(calls, [["focus", {preventScroll: true}], ["select"]])
  calls.length = 0
  f.handlers.get("focus-metric-field")({id: "invalid"})
  assert.deepEqual(calls, [])
  const background = {closest: () => null}
  f.hook.dblclick({
    target: background, clientX: 240, clientY: 180,
    preventDefault() { this.defaultPrevented = true },
  })
  const add = f.pushed.pop()
  assert.equal(add.name, "add-metric")
  f.fields.get("metric-id").value = "card-2"
  add.callback()
  assert.deepEqual(calls, [["focus", {preventScroll: true}], ["select"]])
})

test("floating controls and descendants do not add metrics on double-click or handle card keys", t => {
  const f = fixture(t)
  const panel = {closest: selector => selector === "[data-canvas-controls]" ? panel : null}
  const child = {
    closest: selector => selector === "[data-canvas-controls]" ? panel
      : selector.includes("[data-metric-id]") ? f.card : null,
  }
  for (const insideViewport of [true, false]) {
    f.pane.contains = () => insideViewport
    for (const target of [panel, child]) {
      const event = {
        target, clientX: 240, clientY: 180,
        preventDefault() { this.defaultPrevented = true },
      }
      f.hook.dblclick(event)
      assert.equal(event.defaultPrevented, undefined)
      for (const key of ["ArrowDown", "Enter", " "]) {
        assert.equal(f.key(target, key).defaultPrevented, undefined)
      }
      assert.equal(f.pushed.length, 0)
    }
  }
})

test("Cmd+Z and Ctrl+Z click the enabled Undo button from the canvas or toolbar", t => {
  const f = fixture(t)
  let clicks = 0
  f.fields.set("undo", {disabled: false, click() { clicks++ }})
  const background = {closest: () => null}
  const toolbar = {closest: selector => selector === "[data-canvas-controls]" ? toolbar : null}

  for (const target of [background, f.card, toolbar]) {
    for (const modifiers of [{metaKey: true}, {ctrlKey: true}]) {
      const before = clicks
      assert.equal(f.key(target, "z", modifiers).defaultPrevented, true)
      assert.equal(clicks, before + 1)
    }
  }
  assert.equal(f.key(background, "Z", {metaKey: true}).defaultPrevented, true)
  assert.equal(clicks, 7)
  assert.deepEqual(f.pushed, [])
})

test("model undo leaves native editing, redo, and already handled keys alone", t => {
  const f = fixture(t)
  let clicks = 0
  f.fields.set("undo", {disabled: false, click() { clicks++ }})
  for (const target of [
    f.nested("input"), f.nested("textarea"), f.nested("select"),
    {isContentEditable: true, closest: () => null},
  ]) {
    for (const modifiers of [{metaKey: true}, {ctrlKey: true}]) {
      assert.equal(f.key(target, "z", modifiers).defaultPrevented, undefined)
    }
  }
  for (const modifiers of [
    {}, {metaKey: true, shiftKey: true}, {ctrlKey: true, altKey: true},
    {metaKey: true, isComposing: true}, {ctrlKey: true, repeat: true},
  ]) {
    assert.equal(f.key(f.card, "z", modifiers).defaultPrevented, undefined)
  }
  f.key(f.card, "z", {ctrlKey: true, defaultPrevented: true})
  assert.equal(clicks, 0)
})

test("undo shortcuts do nothing with no history, read-only models, modals, or active gestures", t => {
  const f = fixture(t)
  let clicks = 0
  const undo = {disabled: true, click() { clicks++ }}
  f.fields.set("undo", undo)
  assert.equal(f.key(f.card, "z", {ctrlKey: true}).defaultPrevented, undefined)
  undo.disabled = false

  f.canvas.dataset.editable = "false"
  assert.equal(f.key(f.card, "z", {metaKey: true}).defaultPrevented, undefined)
  f.canvas.dataset.editable = "true"
  f.doc.querySelector = () => ({})
  assert.equal(f.key(f.card, "z", {ctrlKey: true}).defaultPrevented, undefined)
  f.doc.querySelector = () => null
  f.hook.canvasConnection = "disconnected"
  assert.equal(f.key(f.card, "z", {metaKey: true}).defaultPrevented, undefined)
  f.hook.canvasConnection = "connected"

  const drag = f.hook.canvasDrag, pan = f.hook.canvasPan
  f.hook.canvasDrag = {busy: true}
  assert.equal(f.key(f.card, "z", {ctrlKey: true}).defaultPrevented, undefined)
  f.hook.canvasDrag = drag
  f.hook.canvasPan = {busy: true}
  assert.equal(f.key(f.card, "z", {metaKey: true}).defaultPrevented, undefined)
  f.hook.canvasPan = pan
  f.fields.delete("undo")
  assert.equal(f.key(f.card, "z", {metaKey: true}).defaultPrevented, undefined)
  assert.equal(clicks, 0)
})

test("double-click places centered cards in world coordinates at each zoom and rebased origin", t => {
  const f = fixture(t)
  f.canvas.getBoundingClientRect = () => ({left: 100, top: 80})
  const background = {closest: () => null}
  for (const zoom of [0.25, 0.5, 1, 2]) {
    f.hook.canvasPan.zoom = zoom
    f.canvas.dataset.gridOriginX = "-1000000000"
    f.canvas.dataset.gridOriginY = "1000000000"
    // World point (232, 252), less the centered card size, snaps to (4, 8).
    f.hook.dblclick({
      target: background, clientX: 100 + 232 * zoom, clientY: 80 + 252 * zoom,
      preventDefault() {},
    })
    assert.deepEqual(f.pushed.pop().payload, {x: -999999996, y: 1000000008})
  }
})
