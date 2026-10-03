import test from "node:test"
import assert from "node:assert/strict"
import {CanvasDrag, preserveDragStyles} from "./canvas_drag.mjs"
import {CanvasPan} from "./canvas_pan.mjs"

class Events {
  constructor() { this.listeners = new Map() }
  addEventListener(type, fn) {
    if (!this.listeners.has(type)) this.listeners.set(type, new Set())
    this.listeners.get(type).add(fn)
  }
  removeEventListener(type, fn) { this.listeners.get(type)?.delete(fn) }
  emit(type, properties = {}) {
    const event = {
      type, defaultPrevented: false, stopped: false,
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
  listenerCount() {
    return [...this.listeners.values()].reduce((count, listeners) => count + listeners.size, 0)
  }
}

class Element extends Events {
  constructor(doc) {
    super()
    this.ownerDocument = doc
    this.dataset = {}
    this.style = {}
    this.children = []
    this.parent = null
    this.attributes = {}
    const classes = new Set()
    this.classList = {
      add: (...names) => names.forEach(name => classes.add(name)),
      remove: (...names) => names.forEach(name => classes.delete(name)),
      contains: name => classes.has(name),
    }
    this.isConnected = true
  }
  setAttribute(key, value) { this.attributes[key] = value }
  getAttribute(key) { return this.attributes[key] ?? null }
  append(child) { child.parent = this; this.children.push(child) }
  remove() {
    if (this.parent) this.parent.children = this.parent.children.filter(child => child !== this)
    this.parent = null
    this.isConnected = false
  }
  contains(other) {
    for (let current = other; current; current = current.parent) {
      if (current === this) return true
    }
    return false
  }
  closest(selector) {
    for (let current = this; current; current = current.parent) {
      if (selector === "[data-metric-id]" && current.dataset.metricId) return current
      if (selector === ".canvas-scroll" && current.className === "canvas-scroll") return current
      if (selector.includes("a, button, input") &&
          (selector.split(", ").includes(current.tagName) ||
           current.attributes.contenteditable !== undefined ||
           current.attributes["data-card-controls"] !== undefined)) return current
    }
    return null
  }
  querySelectorAll(selector) {
    if (!["[data-metric-id]", ".dependency-path[data-source-id][data-target-id]"].includes(selector)) {
      throw Error(`Unexpected selector ${selector}`)
    }
    const result = []
    const visit = node => {
      if (selector === "[data-metric-id]" && node.dataset.metricId) result.push(node)
      if (selector.startsWith(".dependency-path") && node.dataset.sourceId && node.dataset.targetId) result.push(node)
      node.children.forEach(visit)
    }
    visit(this)
    return result
  }
  getBoundingClientRect() { return this.rect }
}

function fixture({editable = true, legacy = false, geometry = true, busy = false} = {}) {
  const win = new Events()
  win.innerWidth = 500
  win.innerHeight = 400
  win.frames = new Map()
  let frameId = 0
  win.requestAnimationFrame = callback => {
    const id = ++frameId
    win.frames.set(id, callback)
    return id
  }
  win.cancelAnimationFrame = id => win.frames.delete(id)
  win.flushFrame = () => {
    const callbacks = [...win.frames.values()]
    win.frames.clear()
    callbacks.forEach(callback => callback())
  }
  const doc = new Events()
  doc.defaultView = win
  doc.createElement = () => new Element(doc)
  const pane = new Element(doc)
  pane.className = "canvas-scroll"
  pane.rect = {left: 100, top: 100, right: 400, bottom: 300}
  const canvas = new Element(doc)
  canvas.rect = {left: 100, top: 100, right: 700, bottom: 900}
  if (geometry) canvas.dataset = {gridStep: "20", gridPadding: "32"}
  pane.append(canvas)
  const card = new Element(doc)
  card.dataset = {metricId: "card-1", gridX: "2", gridY: "1", movable: String(editable)}
  card.setAttribute("draggable", String(legacy))
  card.rect = {left: 172, top: 152, right: 412, bottom: 340, width: 240, height: 188}
  card.style = {left: "72px", top: "52px", transform: "rotate(1deg)", transition: ""}
  canvas.append(card)
  const host = new Element(doc)
  host.capture = null
  host.setPointerCapture = id => { host.capture = id }
  host.hasPointerCapture = id => host.capture === id
  host.releasePointerCapture = id => {
    host.capture = null
    host.emit("lostpointercapture", {pointerId: id})
  }
  const moves = []
  let invalidGeometry = 0
  const drag = new CanvasDrag({
    host, getCanvas: () => canvas,
    isBusy: () => busy,
    onMove: (id, position, done) => moves.push({id, position, done}),
    onInvalidGeometry: () => invalidGeometry++,
  })
  drag.mount()
  const pointer = (type, x, y, extra = {}) => {
    const event = doc.emit(type, {
      target: card, pointerId: 1, pointerType: "mouse", isPrimary: true,
      button: 0, clientX: x, clientY: y, ...extra,
    })
    win.flushFrame()
    return event
  }
  return {doc, win, pane, canvas, card, host, drag, moves, pointer,
    invalidGeometry: () => invalidGeometry}
}

test("pointer bursts paint only the latest sample once per animation frame", () => {
  const f = fixture()
  f.pointer("pointerdown", 182, 160)
  for (const [clientX, clientY] of [[197, 165], [202, 169], [207, 171]]) {
    f.doc.emit("pointermove", {
      target: f.card, pointerId: 1, clientX, clientY,
    })
  }
  assert.equal(f.win.frames.size, 1)
  assert.equal(f.card.style.transform, "rotate(1deg)")
  f.win.flushFrame()
  assert.equal(f.card.style.transform, "translate3d(25px, 11px, 0) rotate(1deg)")
  assert.equal(f.win.frames.size, 1)
  assert.deepEqual(f.moves, [])
  f.drag.cancel()
  assert.equal(f.win.frames.size, 0)
})

test("release flushes its final position even before a queued frame is painted", () => {
  const f = fixture()
  f.pointer("pointerdown", 182, 160)
  f.doc.emit("pointermove", {target: f.card, pointerId: 1, clientX: 250, clientY: 200})
  assert.equal(f.win.frames.size, 1)
  f.pointer("pointerup", 207, 171)
  assert.equal(f.win.frames.size, 0)
  assert.deepEqual(f.moves[0].position, {x: 3, y: 2})
  assert.equal(f.card.style.transform, "translate3d(20px, 20px, 0) rotate(1deg)")
  f.moves[0].done()
})

test("a rapid card drag commits the release position even without a threshold-crossing move event", () => {
  for (const intermediate of [null, [185, 163]]) {
    const f = fixture()
    f.pointer("pointerdown", 182, 160)
    if (intermediate) f.pointer("pointermove", ...intermediate)
    // Browsers no longer allow acquiring capture once the pointer is released.
    f.host.setPointerCapture = () => { throw Error("Cannot capture a released pointer") }
    const released = f.pointer("pointerup", 207, 171)
    assert.equal(released.defaultPrevented, true)
    assert.equal(f.win.frames.size, 0)
    assert.deepEqual(f.moves[0]?.position, {x: 3, y: 2})
    assert.equal(f.card.style.transform, "translate3d(20px, 20px, 0) rotate(1deg)")
    assert.equal(f.doc.emit("click", {detail: 1}).defaultPrevented, true)
    f.moves[0].done()
    f.drag.destroy()
  }
})

test("a previous capture-loss event cannot cancel a new drag with the same pointer ID", () => {
  const f = fixture()
  f.pointer("pointerdown", 182, 160)
  f.pointer("pointermove", 207, 171)
  f.pointer("pointerup", 207, 171)
  f.moves[0].done()
  f.pointer("pointerdown", 182, 160)
  f.pointer("pointermove", 222, 200)
  f.host.emit("lostpointercapture", {pointerId: 1})
  assert.equal(f.drag.busy, true)
  assert.equal(f.host.capture, 1)
  f.pointer("pointerup", 222, 200)
  assert.deepEqual(f.moves[1].position, {x: 4, y: 3})
  f.moves[1].done()
  f.drag.destroy()
})

test("recorded release ordering commits once when capture loss precedes pointerup", () => {
  const f = fixture()
  f.win.innerWidth = 1280
  f.win.innerHeight = 1000
  f.canvas.rect = {left: 0, top: 271.25, right: 925, bottom: 1334.5}
  f.pane.rect = {...f.canvas.rect}
  Object.assign(f.card.dataset, {gridX: "36", gridY: "13"})
  f.card.rect = {left: 752, top: 563.25, right: 992, bottom: 683.25, width: 240, height: 120}
  f.pointer("pointerdown", 866.2109375, 599.18359375, {buttons: 1})
  for (const [x, y] of [
    [867.16015625, 596.5703125], [866.28515625, 596.046875],
    [845.453125, 600.94921875], [790.609375, 623.67578125],
    [737.5078125, 650.22265625], [642.046875, 700.3046875],
    [541.16796875, 754.0078125],
  ]) f.pointer("pointermove", x, y, {buttons: 1})

  // Trace events 509–513: capture loss with buttons already up, then move/up.
  const release = {pointerId: 1, buttons: 0, clientX: 499.91796875, clientY: 776.30078125}
  f.host.capture = null
  f.host.emit("lostpointercapture", release)
  assert.equal(f.moves.length, 1)
  assert.deepEqual(f.moves[0].position, {x: 18, y: 22})
  assert.equal(f.card.style.transform, "translate3d(-360px, 180px, 0) rotate(1deg)")
  f.pointer("pointermove", release.clientX, release.clientY, {buttons: 0, target: f.canvas})
  f.pointer("pointerup", release.clientX, release.clientY, {buttons: 0, target: f.canvas})
  assert.equal(f.moves.length, 1)
  f.moves[0].done()
  f.pointer("pointerup", release.clientX, release.clientY, {buttons: 0, target: f.canvas})
  assert.equal(f.moves.length, 1)
  f.drag.destroy()
})

test("a released-primary move finishes a card drop without waiting for pointerup", () => {
  for (const buttons of [0, 2]) {
    const f = fixture()
    f.pointer("pointerdown", 182, 160, {buttons: 1})
    f.pointer("pointermove", 207, 171, {buttons: 1})
    f.pointer("pointermove", 222, 200, {buttons})
    assert.deepEqual(f.moves[0]?.position, {x: 4, y: 3})
    assert.equal(f.host.capture, null)
    f.pointer("pointermove", 300, 250, {buttons: 0})
    f.pointer("pointerup", 222, 200, {buttons: 0})
    assert.equal(f.moves.length, 1)
    f.moves[0].done()
    f.drag.destroy()
  }
})

test("a pending card gesture recovers release without capturing an already released pointer", () => {
  const f = fixture()
  f.pointer("pointerdown", 182, 160, {buttons: 1})
  f.host.setPointerCapture = () => { throw Error("Cannot capture a released pointer") }
  f.pointer("pointermove", 207, 171, {buttons: 0})
  assert.deepEqual(f.moves[0]?.position, {x: 3, y: 2})
  assert.equal(f.host.capture, null)
  f.moves[0].done()
  f.drag.destroy()
})

test("explicit pointer cancellation is not resurrected by released-button events", () => {
  const f = fixture()
  f.pointer("pointerdown", 182, 160, {buttons: 1})
  f.pointer("pointermove", 207, 171, {buttons: 1})
  f.pointer("pointercancel", 207, 171, {buttons: 0})
  f.host.emit("lostpointercapture", {pointerId: 1, buttons: 0, clientX: 207, clientY: 171})
  f.pointer("pointermove", 207, 171, {buttons: 0})
  f.pointer("pointerup", 207, 171, {buttons: 0})
  assert.deepEqual(f.moves, [])
  assert.equal(f.drag.busy, false)
  assert.equal(f.card.style.transform, "rotate(1deg)")
  f.drag.destroy()
})

test("capture loss with the primary button held still cancels a card drag", () => {
  const f = fixture()
  f.pointer("pointerdown", 182, 160, {buttons: 1})
  f.pointer("pointermove", 207, 171, {buttons: 1})
  f.host.capture = null
  f.host.emit("lostpointercapture", {pointerId: 1, buttons: 1, clientX: 207, clientY: 171})
  assert.equal(f.drag.busy, false)
  assert.deepEqual(f.moves, [])
  assert.equal(f.card.style.transform, "rotate(1deg)")
  f.drag.destroy()
})

test("another active canvas gesture prevents a card drag from taking ownership", () => {
  const f = fixture({busy: true})
  f.pointer("pointerdown", 182, 160, {pointerId: 2, pointerType: "pen"})
  f.pointer("pointermove", 222, 200, {pointerId: 2})
  assert.equal(f.drag.busy, false)
  assert.equal(f.host.capture, null)
  assert.deepEqual(f.moves, [])
  f.drag.destroy()
})

test("LiveView preserves only transient drag presentation while updating card content and coordinates", () => {
  const f = fixture()
  f.pointer("pointerdown", 182, 160)
  f.pointer("pointermove", 207, 171)
  const next = new Element(f.doc)
  next.style = {left: "120px", top: "92px", transform: "", transition: ""}
  preserveDragStyles(f.card, next)
  assert.equal(next.style.transform, f.card.style.transform)
  assert.equal(next.style.transition, "")
  assert.equal(next.style.left, "120px")
  assert.equal(next.style.top, "92px")
  assert.equal(next.classList.contains("metric-card-dragging"), true)
  f.drag.cancel()
  const unchanged = new Element(f.doc)
  unchanged.style = {transform: "scale(2)"}
  preserveDragStyles(f.card, unchanged)
  assert.equal(unchanged.style.transform, "scale(2)")
})

test("Escape cannot undo a drop already submitted, and stale acknowledgements are ignored", () => {
  const f = fixture()
  f.pointer("pointerdown", 182, 160)
  assert.equal(f.drag.gesturing, true)
  f.pointer("pointermove", 207, 171)
  f.pointer("pointerup", 207, 171)
  f.doc.emit("keydown", {key: "Escape"})
  assert.equal(f.drag.busy, true)
  assert.equal(f.drag.gesturing, false)
  assert.equal(f.moves[0].done(), true)
  assert.equal(f.drag.busy, false)
  assert.equal(f.drag.gesturing, false)
  assert.equal(f.moves[0].done(), false)
})

test("pan continues through a pending card acknowledgement and keeps preview links attached", () => {
  const f = fixture()
  f.win.setTimeout = setTimeout
  f.win.clearTimeout = clearTimeout
  f.pane.style.setProperty = (key, value) => { f.pane.style[key] = value }
  f.pane.classList.toggle = (name, present) =>
    present ? f.pane.classList.add(name) : f.pane.classList.remove(name)
  f.canvas.querySelector = selector => f.canvas.querySelectorAll(selector)[0] || null
  Object.assign(f.canvas.dataset, {cardWidth: "240", cardHeight: "188", linkBend: "50"})
  const pan = new CanvasPan({
    host: f.host, getCanvas: () => f.canvas,
    isBusy: () => f.drag.gesturing,
    onRender: () => f.drag.refreshLinks(),
  })
  // Model the camera's CSS rebasing and the card's transient transform.
  f.canvas.getBoundingClientRect = () => ({
    left: f.pane.rect.left + (Number.parseFloat(f.pane.style["--canvas-pan-x"]) || 0),
    top: f.pane.rect.top + (Number.parseFloat(f.pane.style["--canvas-pan-y"]) || 0),
  })
  const cardRect = card => {
    const [dx, dy] = card.style.transform?.match(/translate3d\(([-\d.]+)px, ([-\d.]+)px, 0\)/)?.slice(1).map(Number) || [0, 0]
    const left = f.pane.rect.left + 32 + Number(card.dataset.gridX) * 20 + pan.position.x + dx
    const top = f.pane.rect.top + 32 + Number(card.dataset.gridY) * 20 + pan.position.y + dy
    return {left, top, right: left + 240, bottom: top + 188, width: 240, height: 188}
  }
  f.card.getBoundingClientRect = () => cardRect(f.card)
  const other = new Element(f.doc)
  other.dataset = {metricId: "card-2", gridX: "12", gridY: "3"}
  other.getBoundingClientRect = () => cardRect(other)
  f.canvas.append(other)
  const line = new Element(f.doc)
  line.dataset = {sourceId: "card-1", targetId: "card-2"}
  f.canvas.append(line)
  pan.mount()

  f.pointer("pointerdown", 182, 160)
  f.pointer("pointermove", 207, 171)
  f.pointer("pointerup", 207, 171)
  assert.equal(f.drag.busy, true)
  assert.equal(f.drag.gesturing, false)

  f.pointer("pointerdown", 350, 200, {target: f.canvas})
  f.pointer("pointermove", 300, 250, {target: f.canvas})
  assert.equal(pan.busy, true)
  assert.deepEqual(pan.position, {x: -90, y: 30})
  const beforeAck = f.card.getBoundingClientRect()
  const canvasRect = f.canvas.getBoundingClientRect()
  const expectedStart = `M ${beforeAck.right - canvasRect.left} ${(beforeAck.top + beforeAck.bottom) / 2 - canvasRect.top} C `
  assert.ok(line.getAttribute("d").startsWith(expectedStart))

  // A LiveView patch can replace SVG paths before acknowledging the card move.
  line.remove()
  const patchedLine = new Element(f.doc)
  patchedLine.dataset = {...line.dataset}
  f.canvas.append(patchedLine)
  f.doc.emit("phx:update")
  assert.ok(patchedLine.getAttribute("d").startsWith(expectedStart))
  Object.assign(f.card.dataset, {gridX: "3", gridY: "2"})
  assert.equal(f.moves[0].done(), true)
  assert.equal(pan.busy, true)
  assert.equal(f.drag.busy, false)
  assert.deepEqual(f.card.getBoundingClientRect(), beforeAck)
  f.pointer("pointerup", 300, 250, {target: f.canvas})
  assert.deepEqual(pan.position, {x: -90, y: 30})
  assert.equal(pan.busy, false)
  pan.destroy()
  f.drag.destroy()
})

test("threshold preserves clicks; editable pointer moves the original card and separate snapped shadow", () => {
  const f = fixture()
  f.pointer("pointerdown", 182, 160)
  assert.equal(f.drag.busy, true)
  f.pointer("pointermove", 185, 163)
  assert.equal(f.card.style.transform, "rotate(1deg)")
  assert.equal(f.host.capture, null)
  f.pointer("pointerup", 185, 163)
  assert.equal(f.drag.busy, false)
  assert.equal(f.doc.emit("click", {detail: 1}).defaultPrevented, false)

  f.pointer("pointerdown", 182, 160)
  const moving = f.pointer("pointermove", 207, 171)
  assert.equal(moving.defaultPrevented, true)
  assert.equal(f.host.capture, 1)
  assert.equal(f.host.children.length, 1)
  assert.equal(f.card.style.left, "72px")
  assert.equal(f.card.style.top, "52px")
  assert.equal(f.card.style.transform, "translate3d(25px, 11px, 0) rotate(1deg)")
  assert.equal(f.card.classList.contains("metric-card-dragging"), true)
  assert.equal(f.drag.preview.dataset.gridX, "3")
  assert.equal(f.drag.preview.dataset.gridY, "2")
  assert.equal(f.drag.preview.style.left, "0px")
  assert.equal(f.drag.preview.style.top, "0px")
  assert.equal(f.drag.preview.style.transform, "translate3d(92px, 72px, 0)")
  assert.equal(f.drag.preview.style.width, "240px")
  assert.equal(f.drag.layer.style.pointerEvents, "none")
  assert.equal(f.drag.layer.attributes["aria-hidden"], "true")
  assert.equal(f.drag.layer.style.display, "block")
  assert.deepEqual(f.moves, [])
  f.pointer("pointerup", 207, 171)
  assert.equal(f.host.capture, null)
  assert.equal(f.drag.busy, true)
  assert.equal(f.card.style.transform, "translate3d(20px, 20px, 0) rotate(1deg)")
  assert.equal(f.card.classList.contains("metric-card-settling"), true)
  assert.deepEqual(f.moves.map(({id, position}) => ({id, position})),
    [{id: "card-1", position: {x: 3, y: 2}}])
  assert.equal(f.doc.emit("click", {target: f.card, detail: 1}).defaultPrevented, true)
  assert.equal(f.doc.emit("click", {target: f.card, detail: 1}).defaultPrevented, false)
  f.card.style.left = "92px" // Server-owned style is applied before the ack.
  f.moves[0].done()
  assert.equal(f.card.style.transform, "rotate(1deg)")
  assert.equal(f.card.style.left, "92px")
  assert.equal(f.card.classList.contains("metric-card-settling"), false)
  assert.equal(f.drag.busy, false)
})

test("touch and pen use the same original-card movement and single snapped drop", () => {
  for (const pointerType of ["touch", "pen"]) {
    const f = fixture()
    f.pointer("pointerdown", 182, 160, {pointerType})
    f.pointer("pointermove", 207, 171, {pointerType})
    assert.equal(f.card.classList.contains("metric-card-dragging"), true)
    assert.equal(f.card.style.transform, "translate3d(25px, 11px, 0) rotate(1deg)")
    f.pointer("pointerup", 207, 171, {pointerType})
    assert.equal(f.moves.length, 1)
    assert.deepEqual(f.moves[0].position, {x: 3, y: 2})
    assert.equal(f.moves[0].done(), true)
    f.drag.destroy()
  }
})

test("snap preview uses the actual compact card dimensions", () => {
  const f = fixture()
  f.card.rect.height = 120
  f.card.rect.bottom = f.card.rect.top + 120
  f.pointer("pointerdown", 182, 160)
  f.pointer("pointermove", 207, 171)
  assert.equal(f.drag.preview.style.width, "240px")
  assert.equal(f.drag.preview.style.height, "120px")
  f.pointer("pointerup", 207, 171)
  assert.deepEqual(f.moves[0].position, {x: 3, y: 2})
  f.moves[0].done()
  f.drag.destroy()
})

test("scroll and canvas bounds refresh with the last pointer coordinates", () => {
  const f = fixture()
  f.pointer("pointerdown", 182, 160)
  f.pointer("pointermove", 207, 171)
  f.canvas.rect = {left: 80, top: 90, right: 680, bottom: 890}
  f.win.emit("scroll")
  f.win.flushFrame()
  assert.equal(f.card.style.transform, "translate3d(45px, 21px, 0) rotate(1deg)")
  assert.equal(f.drag.preview.dataset.gridX, "4")
  assert.equal(f.drag.preview.style.transform, "translate3d(92px, 62px, 0)")
  f.pointer("pointermove", 10000, -1000, {target: f.host})
  assert.equal(f.drag.preview.dataset.gridX, "494")
  assert.equal(f.drag.preview.dataset.gridY, "-56")
  assert.equal(f.card.style.transform, "translate3d(9838px, -1150px, 0) rotate(1deg)")
  f.drag.cancel()
})

test("invalid origin, unchanged snap, and rejected server move never persist the wrong coordinates", () => {
  const f = fixture()
  const occupied = new Element(f.doc)
  occupied.dataset = {metricId: "other", gridX: "3", gridY: "2"}
  f.canvas.append(occupied)
  f.pointer("pointerdown", 182, 160)
  f.pointer("pointermove", 207, 171)
  assert.equal(f.drag.preview.dataset.invalid, "true")
  f.pointer("pointerup", 207, 171)
  assert.equal(f.drag.busy, false)
  assert.equal(f.card.style.transform, "rotate(1deg)")
  assert.equal(f.moves.length, 0)
  occupied.remove()
  f.pointer("pointerdown", 182, 160)
  f.pointer("pointermove", 188, 160)
  f.pointer("pointerup", 188, 160)
  assert.equal(f.moves.length, 0)
  f.pointer("pointerdown", 182, 160)
  f.pointer("pointermove", 207, 171)
  f.pointer("pointerup", 207, 171)
  assert.equal(f.moves.length, 1)
  f.moves[0].done() // A rejected move leaves the server's original left/top untouched.
  assert.equal(f.card.style.left, "72px")
  assert.equal(f.card.style.transform, "rotate(1deg)")
})

test("nonprimary, right-button, and read-only cards are excluded; legacy draggable is supported but native ghost is not", () => {
  const f = fixture({editable: false})
  f.pointer("pointerdown", 182, 160)
  assert.equal(f.drag.busy, false)
  assert.equal(f.doc.emit("dragstart", {target: f.card}).defaultPrevented, false)
  f.card.setAttribute("draggable", "true")
  assert.equal(f.doc.emit("dragstart", {target: f.card}).defaultPrevented, true)
  f.pointer("pointerdown", 182, 160, {button: 2})
  f.pointer("pointerdown", 182, 160, {isPrimary: false})
  assert.equal(f.drag.busy, false)
  f.pointer("pointerdown", 182, 160)
  assert.equal(f.drag.busy, true)
  f.drag.cancel()
})

test("nested card controls keep pointer gestures and native text drags; card surface remains draggable", () => {
  const f = fixture()
  for (const tagName of ["button", "input", "select", "textarea", "a", "label"]) {
    const control = new Element(f.doc)
    control.tagName = tagName
    f.card.append(control)
    const child = new Element(f.doc)
    control.append(child)
    for (const target of [control, child]) {
      f.pointer("pointerdown", 182, 160, {target})
      assert.equal(f.drag.busy, false, `${tagName} should not start a card drag`)
      f.pointer("pointermove", 240, 200, {target})
      f.pointer("pointerup", 240, 200, {target})
      assert.equal(f.moves.length, 0)
      assert.equal(f.doc.emit("dragstart", {target}).defaultPrevented, false)
    }
  }
  const editor = new Element(f.doc)
  editor.setAttribute("contenteditable", "true")
  f.card.append(editor)
  f.pointer("pointerdown", 182, 160, {target: editor})
  assert.equal(f.drag.busy, false)
  f.pointer("pointerdown", 182, 160, {target: f.card})
  assert.equal(f.drag.busy, true)
  f.drag.cancel()
  f.drag.destroy()
})

test("selected card summaries inside a form remain draggable, while its configuration does not", () => {
  const f = fixture()
  const form = new Element(f.doc)
  form.tagName = "form"
  f.card.append(form)
  const summary = new Element(f.doc)
  form.append(summary)
  f.pointer("pointerdown", 182, 160, {target: summary})
  assert.equal(f.drag.busy, true)
  f.drag.cancel()

  const config = new Element(f.doc)
  config.setAttribute("data-card-controls", "")
  form.append(config)
  const text = new Element(f.doc)
  config.append(text)
  f.pointer("pointerdown", 182, 160, {target: text})
  assert.equal(f.drag.busy, false)
  f.drag.destroy()
})

test("cancellation, disconnect, teardown, and stale acknowledgements restore state", () => {
  const f = fixture()
  const start = () => { f.pointer("pointerdown", 182, 160); f.pointer("pointermove", 207, 171) }
  start()
  f.doc.emit("pointercancel", {pointerId: 2})
  assert.equal(f.drag.busy, true)
  f.doc.emit("keydown", {key: "Escape"})
  assert.equal(f.drag.busy, false)
  assert.equal(f.host.capture, null)
  assert.equal(f.card.style.transform, "rotate(1deg)")
  assert.equal(f.doc.emit("click", {target: f.card, detail: 1}).defaultPrevented, true)
  start()
  f.host.capture = null
  f.host.emit("lostpointercapture", {pointerId: 1})
  assert.equal(f.drag.busy, false)
  start()
  f.win.emit("blur")
  assert.equal(f.drag.busy, false)
  start()
  f.pointer("pointerup", 207, 171)
  const done = f.moves[0].done
  f.pointer("pointerdown", 182, 160)
  assert.equal(f.drag.busy, true) // no second move while awaiting ack
  assert.equal(f.moves.length, 1)
  f.drag.cancel()
  start()
  done()
  assert.equal(f.drag.busy, true) // stale acknowledgement does not cancel the next gesture
  f.card.isConnected = false
  f.pointer("pointermove", 210, 175)
  assert.equal(f.drag.busy, false)
  f.drag.destroy()
  assert.equal(f.doc.listenerCount(), 0)
  assert.equal(f.win.listenerCount(), 0)
  assert.equal(f.host.listenerCount(), 0)
  assert.equal(f.host.children.length, 0)
  assert.equal(f.win.frames.size, 0)
  done()
  assert.equal(f.card.style.transform, "rotate(1deg)")
})

test("invalid or missing canvas geometry invokes compatibility notice instead of starting drag", () => {
  const f = fixture({geometry: false})
  assert.equal(f.invalidGeometry(), 1)
  f.pointer("pointerdown", 182, 160)
  assert.equal(f.invalidGeometry(), 2)
  assert.equal(f.drag.busy, false)
  f.drag.destroy()
})

test("incident connection endpoints follow the card and are recomputed after acknowledgement", () => {
  const f = fixture()
  f.canvas.dataset.linkBend = "50"
  const other = new Element(f.doc)
  other.dataset = {metricId: "card-2", gridX: "12", gridY: "3"}
  other.rect = {left: 372, right: 612, top: 192, bottom: 380}
  f.canvas.append(other)
  const line = new Element(f.doc)
  line.dataset = {sourceId: "card-1", targetId: "card-2"}
  line.setAttribute("d", "old")
  f.canvas.append(line)
  f.card.getBoundingClientRect = () => {
    const [dx, dy] = f.card.style.transform.match(/translate3d\(([-\d.]+)px, ([-\d.]+)px, 0\)/)?.slice(1).map(Number) || [0, 0]
    const left = 172 + (Number.parseInt(f.card.style.left, 10) - 72) + dx
    const top = 152 + dy
    return {left, right: left + 240, top, bottom: top + 188, width: 240, height: 188}
  }
  f.pointer("pointerdown", 182, 160)
  f.pointer("pointermove", 207, 171)
  assert.equal(line.attributes.d, "M 337 157 C 387 157, 222 186, 272 186")
  f.pointer("pointerup", 207, 171)
  assert.equal(line.attributes.d, "M 332 166 C 382 166, 222 186, 272 186")
  f.card.style.left = "92px"
  f.moves[0].done()
  assert.equal(line.attributes.d, "M 332 146 C 382 146, 222 186, 272 186")
})

test("card drops in a rebased distant viewport persist canonical world coordinates", () => {
  const f = fixture()
  f.canvas.dataset.gridOriginX = "1000000000"
  f.canvas.dataset.gridOriginY = "-1000000000"
  f.card.dataset.gridX = "1000000002"
  f.card.dataset.gridY = "-999999999"
  f.pointer("pointerdown", 182, 160)
  f.pointer("pointermove", 207, 171)
  assert.equal(f.drag.preview.dataset.gridX, "1000000003")
  assert.equal(f.drag.preview.dataset.gridY, "-999999998")
  f.pointer("pointerup", 207, 171)
  assert.deepEqual(f.moves[0].position, {x: 1_000_000_003, y: -999_999_998})
  assert.equal(f.card.style.transform, "translate3d(20px, 20px, 0) rotate(1deg)")
  f.moves[0].done()
  f.drag.destroy()
})
