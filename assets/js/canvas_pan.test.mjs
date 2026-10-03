import test from "node:test"
import assert from "node:assert/strict"
import {CanvasPan, preservePanStyles} from "./canvas_pan.mjs"

class Events {
  constructor() { this.listeners = new Map() }
  addEventListener(type, fn) {
    if (!this.listeners.has(type)) this.listeners.set(type, new Set())
    this.listeners.get(type).add(fn)
  }
  removeEventListener(type, fn) { this.listeners.get(type)?.delete(fn) }
  emit(type, properties = {}) {
    const event = {
      preventDefault() { this.defaultPrevented = true },
      stopImmediatePropagation() { this.stopped = true },
      ...properties,
    }
    for (const fn of [...(this.listeners.get(type) || [])]) {
      fn(event)
      if (event.stopped) break
    }
    return event
  }
  count() { return [...this.listeners.values()].reduce((n, set) => n + set.size, 0) }
}

function element() {
  const classes = new Set(), styles = new Map()
  return {
    style: {
      setProperty: (key, value) => styles.set(key, value),
      getPropertyValue: key => styles.get(key) || "",
    },
    classList: {
      add: name => classes.add(name), remove: name => classes.delete(name),
      contains: name => classes.has(name),
      toggle: (name, present) => present ? classes.add(name) : classes.delete(name),
    },
  }
}

function fixture({first = null, busy = false} = {}) {
  const doc = new Events(), win = new Events(), host = new Events()
  win.setTimeout = setTimeout
  win.clearTimeout = clearTimeout
  doc.defaultView = win
  host.ownerDocument = doc
  host.setPointerCapture = id => { host.capture = id }
  host.hasPointerCapture = id => host.capture === id
  host.releasePointerCapture = id => {
    host.capture = null
    host.emit("lostpointercapture", {pointerId: id})
  }
  const pane = {...element(), clientHeight: 500, closest: () => null}
  const background = {closest: () => null}
  const card = {closest: () => card}
  const input = {closest: () => input}
  pane.contains = target => [pane, background, card, input].includes(target)
  const canvas = {
    dataset: {gridStep: "20", gridPadding: "32", cardWidth: "240", cardHeight: "120"},
    closest: () => pane,
    querySelector: () => first && {dataset: first},
    querySelectorAll: () => [],
    contains: target => target === card,
  }
  const pan = new CanvasPan({host, getCanvas: () => canvas, isBusy: () => busy})
  pan.mount()
  const pointer = (type, x, y, extra = {}) => doc.emit(type, {
    target: background, pointerId: 1, pointerType: "mouse", button: 0,
    isPrimary: true, clientX: x, clientY: y, ...extra,
  })
  return {doc, win, host, pane, canvas, background, card, input, pan, pointer}
}

test("background drag pans in every direction without changing world coordinates", () => {
  const f = fixture()
  f.pointer("pointerdown", 100, 100)
  f.pointer("pointermove", 1100, -1900)
  assert.deepEqual(f.pan.position, {x: 1000, y: -2000})
  assert.equal(f.pane.style.getPropertyValue("--canvas-pan-x"), "0px")
  assert.equal(f.pane.style.getPropertyValue("--canvas-origin-x"), "-1000px")
  assert.equal(f.pane.classList.contains("canvas-panning"), true)
  assert.equal(f.host.capture, 1)
  f.pointer("pointerup", 1200, -2000)
  assert.deepEqual(f.pan.position, {x: 1100, y: -2100})
  assert.equal(f.pan.busy, false)
  assert.equal(f.host.capture, null)
  assert.equal(f.pane.classList.contains("canvas-panning"), false)
  f.pan.destroy()
})

test("ordinary clicks and small pointer jitter remain clicks", () => {
  const f = fixture()
  f.pointer("pointerdown", 100, 100)
  assert.equal(f.pointer("pointermove", 102, 102).defaultPrevented, undefined)
  f.pointer("pointerup", 102, 102)
  assert.deepEqual(f.pan.position, {x: 0, y: 0})
  assert.equal(f.doc.emit("click", {target: f.background}).stopped, undefined)
  f.pan.destroy()
})

test("rapid pans commit each release even without a threshold-crossing move event", () => {
  const f = fixture()
  f.host.setPointerCapture = () => { throw Error("Cannot capture a released pointer") }
  for (const intermediate of [null, [102, 102]]) {
    f.pointer("pointerdown", 100, 100)
    if (intermediate) f.pointer("pointermove", ...intermediate)
    const released = f.pointer("pointerup", 60, 140)
    assert.equal(released.defaultPrevented, true)
    assert.equal(f.pan.busy, false)
    assert.equal(f.host.capture, undefined)
    assert.equal(f.doc.emit("click", {target: f.background}).stopped, true)
  }
  assert.deepEqual(f.pan.position, {x: -80, y: 80})
  f.pan.destroy()
})

test("a previous capture-loss event cannot cancel a new pan with the same pointer ID", () => {
  const f = fixture()
  f.pointer("pointerdown", 100, 100)
  f.pointer("pointermove", 60, 140)
  f.pointer("pointerup", 60, 140)
  f.pointer("pointerdown", 100, 100)
  f.pointer("pointermove", 60, 140)
  f.host.emit("lostpointercapture", {pointerId: 1})
  assert.equal(f.pan.busy, true)
  assert.equal(f.host.capture, 1)
  f.pointer("pointerup", 60, 140)
  assert.deepEqual(f.pan.position, {x: -80, y: 80})
  f.pan.destroy()
})

test("release capture loss finishes a pan before the delayed pointerup arrives", () => {
  for (const pointerType of ["mouse", "pen", "touch"]) {
    const f = fixture()
    f.pointer("pointerdown", 100, 100, {pointerType, buttons: 1})
    f.pointer("pointermove", 60, 140, {pointerType, buttons: 1})
    f.host.capture = null
    f.host.emit("lostpointercapture", {
      pointerId: 1, pointerType, buttons: 0, clientX: 50, clientY: 150,
    })
    assert.deepEqual(f.pan.position, {x: -50, y: 50})
    assert.equal(f.pan.busy, false)
    f.pointer("pointermove", 50, 150, {buttons: 0})
    f.pointer("pointerup", 50, 150, {buttons: 0})
    assert.deepEqual(f.pan.position, {x: -50, y: 50})
    assert.equal(f.doc.emit("click", {target: f.background}).stopped, true)
    f.pan.destroy()
  }
})

test("released-primary movement finishes a pan once, without following subsequent hover", () => {
  for (const buttons of [0, 2]) {
    const f = fixture()
    f.pointer("pointerdown", 100, 100, {buttons: 1})
    f.pointer("pointermove", 60, 140, {buttons: 1})
    f.pointer("pointermove", 50, 150, {buttons})
    assert.deepEqual(f.pan.position, {x: -50, y: 50})
    assert.equal(f.pan.busy, false)
    f.pointer("pointermove", 0, 0, {buttons: 0})
    f.pointer("pointerup", 0, 0, {buttons: 0})
    assert.deepEqual(f.pan.position, {x: -50, y: 50})
    f.pan.destroy()
  }
})

test("a pending pan recovers release without trying to acquire pointer capture", () => {
  const f = fixture()
  f.pointer("pointerdown", 100, 100, {buttons: 1})
  f.host.setPointerCapture = () => { throw Error("Cannot capture a released pointer") }
  f.pointer("pointermove", 60, 140, {buttons: 0})
  assert.deepEqual(f.pan.position, {x: -40, y: 40})
  assert.equal(f.pan.busy, false)
  assert.equal(f.host.capture, undefined)
  f.pan.destroy()
})

test("explicit pan cancellation stays rolled back through later release events", () => {
  const f = fixture()
  f.pointer("pointerdown", 100, 100, {buttons: 1})
  f.pointer("pointermove", 60, 140, {buttons: 1})
  f.pointer("pointercancel", 60, 140, {buttons: 0})
  f.host.emit("lostpointercapture", {pointerId: 1, buttons: 0, clientX: 60, clientY: 140})
  f.pointer("pointermove", 60, 140, {buttons: 0})
  f.pointer("pointerup", 60, 140, {buttons: 0})
  assert.deepEqual(f.pan.position, {x: 0, y: 0})
  assert.equal(f.pan.busy, false)
  f.pan.destroy()
})

test("capture loss while the primary button is held still rolls a pan back", () => {
  const f = fixture()
  f.pointer("pointerdown", 100, 100, {buttons: 1})
  f.pointer("pointermove", 60, 140, {buttons: 1})
  f.host.capture = null
  f.host.emit("lostpointercapture", {pointerId: 1, buttons: 1, clientX: 60, clientY: 140})
  assert.deepEqual(f.pan.position, {x: 0, y: 0})
  assert.equal(f.pan.busy, false)
  f.pan.destroy()
})

test("card descendants, controls, outside targets, and nonprimary buttons never start panning", () => {
  const f = fixture()
  for (const extra of [
    {target: f.card}, {target: f.input}, {target: {closest: () => null}},
    {button: 2}, {isPrimary: false}, {pointerType: "unknown"},
  ]) {
    f.pointer("pointerdown", 100, 100, extra)
    assert.equal(f.pan.busy, false)
  }
  f.pan.destroy()
  const busy = fixture({busy: true})
  busy.pointer("pointerdown", 100, 100)
  assert.equal(busy.pan.busy, false)
  busy.pan.destroy()
})

test("touch and pen background gestures pan while unrelated pointer events are ignored", () => {
  for (const pointerType of ["touch", "pen"]) {
    const f = fixture()
    f.pointer("pointerdown", 100, 100, {pointerType})
    f.pointer("pointermove", 0, 0, {pointerId: 2})
    assert.deepEqual(f.pan.position, {x: 0, y: 0})
    f.pointer("pointermove", 60, 140)
    f.pointer("pointerup", 60, 140)
    assert.deepEqual(f.pan.position, {x: -40, y: 40})
    f.pan.destroy()
  }
})

test("Escape, cancellation, capture loss, blur, and disconnect restore the start of the gesture", () => {
  for (const cancel of [
    f => f.doc.emit("keydown", {key: "Escape"}),
    f => f.pointer("pointercancel", 0, 0),
    f => { f.host.capture = null; f.host.emit("lostpointercapture", {pointerId: 1}) },
    f => f.win.emit("blur"),
    f => f.pan.cancel(),
  ]) {
    const f = fixture()
    f.pointer("pointerdown", 100, 100)
    f.pointer("pointermove", 60, 140)
    cancel(f)
    assert.deepEqual(f.pan.position, {x: 0, y: 0})
    assert.equal(f.pan.busy, false)
    assert.equal(f.host.capture, null)
    f.pan.destroy()
  }
})

test("panning suppresses accidental click/double-click but not the next intentional gesture", () => {
  const f = fixture()
  f.pointer("pointerdown", 100, 100)
  f.pointer("pointermove", 60, 140)
  f.pointer("pointerup", 60, 140)
  assert.equal(f.doc.emit("click", {target: f.host}).stopped, true)
  assert.equal(f.doc.emit("dblclick", {target: f.background}).stopped, true)
  f.pointer("pointerdown", 100, 100)
  f.pointer("pointerup", 100, 100)
  assert.equal(f.doc.emit("dblclick", {target: f.background}).stopped, undefined)
  f.pan.destroy()
})

test("scrolling and focused-viewport arrows pan, without stealing card keys or browser zoom", () => {
  const f = fixture()
  const wheel = extra => f.doc.emit("wheel", {
    target: f.background, deltaX: 10, deltaY: 30, deltaMode: 0, ...extra,
  })
  assert.equal(wheel().defaultPrevented, true)
  assert.deepEqual(f.pan.position, {x: -10, y: -30})
  wheel({deltaX: 0, deltaY: 2, deltaMode: 1, shiftKey: true})
  assert.deepEqual(f.pan.position, {x: -50, y: -30})
  assert.equal(wheel({ctrlKey: true}).defaultPrevented, undefined)
  f.doc.emit("keydown", {target: f.pane, key: "ArrowDown"})
  assert.deepEqual(f.pan.position, {x: -50, y: -70})
  f.doc.emit("keydown", {target: f.card, key: "ArrowDown"})
  assert.deepEqual(f.pan.position, {x: -50, y: -70})
  f.pan.destroy()
})

test("viewport survives LiveView patches and starts with a reopened distant card visible", () => {
  const f = fixture({first: {gridX: "-250", gridY: "1300"}})
  assert.deepEqual(f.pan.position, {x: 5000, y: -26000})
  const patched = element()
  f.pane.hasAttribute = name => name === "data-canvas-viewport"
  f.pointer("pointerdown", 100, 100)
  f.pointer("pointermove", 60, 140)
  preservePanStyles(f.pane, patched)
  assert.equal(patched.style.getPropertyValue("--canvas-origin-x"), "-4960px")
  assert.equal(patched.style.getPropertyValue("--canvas-pan-x"), "0px")
  assert.equal(patched.classList.contains("canvas-panning"), true)
  f.doc.emit("phx:update")
  assert.deepEqual(f.pan.position, {x: 4960, y: -25960})
  f.pan.destroy()
})

test("keyboard focus reveals offscreen cards by moving the camera, keeping dots aligned", () => {
  const f = fixture()
  f.card.dataset = {gridX: "-16", gridY: "34"}
  f.pane.getBoundingClientRect = () => ({left: 0, right: 900, top: 100, bottom: 600})
  f.doc.emit("focusin", {target: f.card})
  assert.deepEqual(f.pan.position, {x: 304, y: -348})
  assert.equal(f.pane.style.getPropertyValue("--canvas-pan-y"), "-8px")
  f.pan.destroy()
})

test("focus reveals distant cards beyond CSS layout limits and rebases the rendering origin", () => {
  const f = fixture()
  f.card.dataset = {gridX: "1000000000", gridY: "-1000000000"}
  f.pane.getBoundingClientRect = () => ({left: 0, right: 900, top: 100, bottom: 600})
  f.doc.emit("focusin", {target: f.card})
  assert.deepEqual(f.pan.position, {x: -19_999_999_388, y: 19_999_999_984})
  assert.equal(f.canvas.dataset.gridOriginX, "999999969")
  assert.equal(f.pane.style.getPropertyValue("--canvas-pan-x"), "-8px")
  f.pan.destroy()
})

test("teardown removes all global listeners, pointer capture, and click suppression", () => {
  const f = fixture()
  f.pointer("pointerdown", 100, 100)
  f.pointer("pointermove", 60, 140)
  f.pan.destroy()
  assert.equal(f.doc.count(), 0)
  assert.equal(f.win.count(), 0)
  assert.equal(f.host.count(), 0)
  assert.equal(f.host.capture, null)
})
