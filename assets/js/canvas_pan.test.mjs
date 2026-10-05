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

function fixture({first = null, busy = false, panelInPane = true} = {}) {
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
  const pane = {
    ...element(), clientHeight: 500, closest: () => null,
    getBoundingClientRect: () => ({left: 100, top: 80, right: 1000, bottom: 580}),
  }
  const background = {closest: () => null}
  const card = {closest: selector => selector.includes("[data-metric-id]") ? card : null}
  const cardChild = {closest: selector => selector.includes("[data-metric-id]") ? card : null}
  const input = {closest: () => input}
  const form = {closest: selector => selector.includes("form") ? form : null}
  const panel = {closest: selector => selector === "[data-canvas-controls]" ? panel : null}
  const panelChild = {closest: selector => selector === "[data-canvas-controls]" ? panel : null}
  pane.contains = target => [pane, background, card, cardChild, input, form].includes(target) ||
    (panelInPane && [panel, panelChild].includes(target))
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
  return {doc, win, host, pane, canvas, background, card, cardChild, panel, panelChild, input, form, pan, pointer}
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
    {target: f.card}, {target: f.cardChild}, {target: f.input},
    {target: f.form}, {target: {closest: () => null}},
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

test("floating controls and descendants cannot start a pan inside or outside the viewport", () => {
  for (const panelInPane of [true, false]) {
    const f = fixture({panelInPane})
    for (const target of [f.panel, f.panelChild]) {
      f.pointer("pointerdown", 100, 100, {target})
      f.pointer("pointermove", 60, 140, {target})
      f.pointer("pointerup", 60, 140, {target})
      assert.equal(f.pan.busy, false)
      assert.deepEqual(f.pan.position, {x: 0, y: 0})
      assert.equal(f.host.capture, undefined)
    }
    f.pan.destroy()
  }
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

test("post-pan click suppression does not swallow floating control clicks or double-clicks", () => {
  const f = fixture()
  f.pointer("pointerdown", 100, 100)
  f.pointer("pointermove", 60, 140)
  f.pointer("pointerup", 60, 140)
  for (const type of ["click", "dblclick"]) {
    const event = f.doc.emit(type, {target: f.panelChild})
    assert.equal(event.defaultPrevented, undefined)
    assert.equal(event.stopped, undefined)
  }
  assert.equal(f.doc.emit("dblclick", {target: f.background}).stopped, true)
  f.pan.destroy()
})

test("scrolling and focused-viewport arrows pan without stealing card keys", () => {
  const f = fixture()
  const wheel = extra => f.doc.emit("wheel", {
    target: f.background, deltaX: 10, deltaY: 30, deltaMode: 0, ...extra,
  })
  assert.equal(wheel().defaultPrevented, true)
  assert.deepEqual(f.pan.position, {x: -10, y: -30})
  wheel({deltaX: 0, deltaY: 2, deltaMode: 1, shiftKey: true})
  assert.deepEqual(f.pan.position, {x: -50, y: -30})
  f.doc.emit("keydown", {target: f.pane, key: "ArrowDown"})
  assert.deepEqual(f.pan.position, {x: -50, y: -70})
  f.doc.emit("keydown", {target: f.card, key: "ArrowDown"})
  assert.deepEqual(f.pan.position, {x: -50, y: -70})
  f.pan.destroy()
})

test("floating controls retain wheel and keys even during a pending pan", () => {
  for (const panelInPane of [true, false]) {
    const f = fixture({panelInPane})
    for (const target of [f.panel, f.panelChild]) {
      const wheel = f.doc.emit("wheel", {target, deltaX: 10, deltaY: 30, deltaMode: 0})
      assert.equal(wheel.defaultPrevented, undefined)
      assert.deepEqual(f.pan.position, {x: 0, y: 0})
      const arrow = f.doc.emit("keydown", {target, key: "ArrowDown"})
      assert.equal(arrow.defaultPrevented, undefined)
    }
    f.pointer("pointerdown", 100, 100)
    const escape = f.doc.emit("keydown", {target: f.panelChild, key: "Escape"})
    assert.equal(escape.defaultPrevented, undefined)
    assert.equal(f.pan.busy, true)
    f.doc.emit("keydown", {target: f.pane, key: "Escape"})
    assert.equal(f.pan.busy, false)
    f.pan.destroy()
  }
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

test("focus inside floating controls never reveals a card by shifting the camera", () => {
  const f = fixture()
  f.card.dataset = {gridX: "-16", gridY: "34"}
  f.panelChild.closest = selector => selector === "[data-canvas-controls]" ? f.panel
    : selector.includes("[data-metric-id]") ? f.card : null
  f.pane.getBoundingClientRect = () => ({left: 0, right: 900, top: 100, bottom: 600})
  f.doc.emit("focusin", {target: f.panelChild})
  assert.deepEqual(f.pan.position, {x: 0, y: 0})
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

test("zoom keeps the anchored world point stationary and rebases scaled dots", () => {
  const f = fixture()
  f.pan.position = {x: -123, y: 47}
  const anchor = {x: 180, y: 100}
  const world = {x: anchor.x - f.pan.position.x, y: anchor.y - f.pan.position.y}
  for (const zoom of [0.5, 2, 1]) {
    f.pan.setZoom(zoom, anchor)
    assert.equal((anchor.x - f.pan.position.x) / zoom, world.x)
    assert.equal((anchor.y - f.pan.position.y) / zoom, world.y)
    assert.equal(f.canvas.dataset.canvasZoom, String(zoom))
    assert.equal(f.pane.style.getPropertyValue("--canvas-zoom"), String(zoom))
    assert.equal(f.pane.style.getPropertyValue("--canvas-grid-size"), `${20 * zoom}px`)
    assert.equal(f.pane.style.getPropertyValue("--canvas-grid-offset"), `${2 * zoom}px`)
    const origin = Number(f.canvas.dataset.gridOriginX)
    assert.equal(Number.parseFloat(f.pane.style.getPropertyValue("--canvas-pan-x")),
      f.pan.position.x + origin * 20 * zoom)
  }
  f.pan.destroy()
})

test("Ctrl/Cmd wheel and trackpad pinch zoom at the pointer; outside wheels stay native", () => {
  for (const modifier of ["ctrlKey", "metaKey"]) {
    for (const deltaMode of [0, 1, 2]) {
      const f = fixture()
      const event = f.doc.emit("wheel", {
        target: f.background, [modifier]: true, deltaY: -1, deltaMode,
        clientX: 350, clientY: 280,
      })
      assert.equal(event.defaultPrevented, true)
      assert.ok(f.pan.zoom > 1)
      assert.equal((250 - f.pan.position.x) / f.pan.zoom, 250)
      assert.equal((200 - f.pan.position.y) / f.pan.zoom, 200)
      for (const target of [f.panelChild, {closest: () => null}]) {
        const outside = f.doc.emit("wheel", {target, [modifier]: true, deltaY: -10, deltaMode: 0})
        assert.equal(outside.defaultPrevented, undefined)
      }
      f.pan.destroy()
    }
  }
})

test("zoom buttons support nested icons, bounds, percentage feedback, and reset", () => {
  const f = fixture()
  const buttons = new Map()
  for (const [id, action] of [["out", "out"], ["in", "in"], ["level", "reset"]]) {
    const button = {
      dataset: {canvasZoom: action},
      closest: selector => selector === "[data-canvas-zoom]" ? button : f.panel,
      setAttribute(name, value) { this[name] = value },
    }
    buttons.set(`#canvas-zoom-${id}`, button)
  }
  const status = {textContent: "Zoom 100%"}
  buttons.set("#canvas-zoom-status", status)
  f.pane.querySelector = selector => buttons.get(selector)
  const contains = f.pane.contains
  f.pane.contains = target => [...buttons.values()].includes(target) || contains(target)
  const click = action => f.doc.emit("click", {
    target: {closest: () => buttons.get(`#canvas-zoom-${action}`)},
  })
  click("in")
  assert.equal(f.pan.zoom, 1.25)
  assert.deepEqual(f.pan.position, {x: -112.5, y: -62.5})
  assert.equal(buttons.get("#canvas-zoom-level").textContent, "125%")
  assert.equal(buttons.get("#canvas-zoom-level")["aria-label"], "Zoom 125%. Reset zoom to 100%")
  assert.equal(status.textContent, "Zoom 125%")
  f.pan.setZoom(100)
  assert.equal(f.pan.zoom, 2)
  assert.equal(buttons.get("#canvas-zoom-in").disabled, true)
  f.pan.setZoom(0)
  assert.equal(f.pan.zoom, 0.25)
  assert.equal(buttons.get("#canvas-zoom-out").disabled, true)
  click("level")
  assert.equal(f.pan.zoom, 1)
  assert.equal(buttons.get("#canvas-zoom-level").textContent, "100%")
  assert.equal(status.textContent, "Zoom 100%")
  assert.equal(buttons.get("#canvas-zoom-out").disabled, false)
  assert.equal(buttons.get("#canvas-zoom-in").disabled, false)
  f.pan.destroy()
})

test("zoom keyboard shortcuts are scoped to the focused viewport and blocked during gestures", () => {
  const f = fixture()
  for (const target of [f.card, f.panelChild, f.input]) {
    assert.equal(f.doc.emit("keydown", {target, key: "+"}).defaultPrevented, undefined)
  }
  for (const key of ["+", "=", "-", "0"]) {
    assert.equal(f.doc.emit("keydown", {target: f.pane, key}).defaultPrevented, true)
  }
  assert.equal(f.pan.zoom, 1)
  f.pointer("pointerdown", 100, 100)
  f.pan.setZoom(2)
  assert.equal(f.pan.zoom, 1)
  f.pan.cancel()
  f.pan.isBusy = () => true
  f.pan.setZoom(2)
  assert.equal(f.pan.zoom, 1)
  f.pan.destroy()
})

test("zoom and rendering state survive LiveView patches without changing model coordinates", () => {
  const f = fixture({first: {gridX: "-1000000000", gridY: "1000000000"}})
  f.pan.setZoom(0.5)
  const position = {...f.pan.position}
  const patched = element()
  f.pane.hasAttribute = name => name === "data-canvas-viewport"
  preservePanStyles(f.pane, patched)
  for (const key of ["--canvas-zoom", "--canvas-grid-size", "--canvas-grid-offset"]) {
    assert.equal(patched.style.getPropertyValue(key), f.pane.style.getPropertyValue(key))
  }
  f.canvas.hasAttribute = name => name === "data-model-canvas"
  const nextCanvas = {dataset: {}}
  preservePanStyles(f.canvas, nextCanvas)
  assert.deepEqual(nextCanvas.dataset, {
    gridOriginX: f.canvas.dataset.gridOriginX, gridOriginY: f.canvas.dataset.gridOriginY,
    canvasZoom: "0.5",
  })
  f.doc.emit("phx:update")
  assert.equal(f.pan.zoom, 0.5)
  assert.deepEqual(f.pan.position, position)
  f.pan.destroy()
})

test("panning remains screen-space and keyboard focus reveals scaled distant cards", () => {
  const f = fixture()
  f.pan.setZoom(0.5, {x: 0, y: 0})
  f.pointer("pointerdown", 100, 100)
  f.pointer("pointermove", 160, 140)
  f.pointer("pointerup", 160, 140)
  assert.deepEqual(f.pan.position, {x: 60, y: 40})
  f.card.dataset = {gridX: "-1000000000", gridY: "1000000000"}
  f.doc.emit("focusin", {target: f.card})
  const left = (32 + Number(f.card.dataset.gridX) * 20) * f.pan.zoom + f.pan.position.x
  const top = (32 + Number(f.card.dataset.gridY) * 20) * f.pan.zoom + f.pan.position.y
  assert.equal(left, 16)
  assert.equal(top + 120 * f.pan.zoom, 484)
  f.pan.destroy()
})
