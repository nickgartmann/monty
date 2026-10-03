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
