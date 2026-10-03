import test from "node:test"
import assert from "node:assert/strict"
import {CanvasDebug} from "./canvas_debug.mjs"

function fixture() {
  const values = new Map(), output = []
  let time = 1000
  const storage = {
    getItem: key => values.get(key),
    setItem: (key, value) => values.set(key, value),
  }
  const options = {storage, output: (...args) => output.push(args), now: () => time++}
  return {debug: new CanvasDebug(options), output, options, values}
}

class Events {
  constructor() { this.listeners = new Map() }
  addEventListener(type, callback) {
    if (!this.listeners.has(type)) this.listeners.set(type, new Set())
    this.listeners.get(type).add(callback)
  }
  removeEventListener(type, callback) { this.listeners.get(type)?.delete(callback) }
  emit(type, data = {}) {
    for (const callback of this.listeners.get(type) || []) callback({type, ...data})
  }
  count() { return [...this.listeners.values()].reduce((n, set) => n + set.size, 0) }
}

function attach(debug) {
  const doc = new Events(), win = new Events()
  doc.defaultView = win
  const background = {closest: () => null}, outside = {closest: () => null}
  const card = {closest: selector => selector === "[data-metric-id]" ? card : null}
  const host = {ownerDocument: doc, contains: target => target === host}
  const canvas = {closest: () => ({contains: target => target === background || target === card})}
  const state = {drag: {phase: "idle"}, pan: {phase: "idle", position: {x: 0, y: 0}}}
  const stop = debug.attach({host, getCanvas: () => canvas, getState: () => state})
  return {doc, win, host, background, outside, card, state, stop}
}

test("tracing is disabled by default and does not evaluate gesture state", () => {
  const f = fixture()
  f.debug.getState = () => { throw Error("State must not be read") }
  f.debug.record("pan.started")
  assert.deepEqual(f.output, [])
  assert.deepEqual(f.debug.events(), [])
  assert.equal(f.values.size, 0)
})

test("records immutable state and details snapshots in sequence", () => {
  const f = fixture()
  const state = {pan: {position: {x: 20, y: -40}}}
  f.debug.getState = () => state
  f.debug.enable()
  const details = {reason: "escape", position: {x: 10, y: 30}}
  f.debug.record("pan.cancelled", details)
  state.pan.position.x = 999
  details.position.x = 999
  const entry = f.debug.events().at(-1)
  assert.equal(entry.sequence, 2)
  assert.equal(entry.event, "pan.cancelled")
  assert.equal(entry.state.pan.position.x, 20)
  assert.equal(entry.details.position.x, 10)
  assert.match(f.output.at(-1)[0], /^\[monty:canvas\] #2 pan.cancelled$/)
  entry.details.reason = "modified"
  assert.equal(f.debug.events().at(-1).details.reason, "escape")
})

test("opt-in and the bounded trace survive reloads; disabling stays disabled", () => {
  const f = fixture()
  f.debug.enable({moves: true})
  for (let i = 0; i < 520; i++) f.debug.record("pan.started", {i})
  assert.equal(f.debug.events().length, 500)
  const reloaded = new CanvasDebug(f.options)
  assert.equal(reloaded.enabled, true)
  assert.equal(reloaded.moves, true)
  assert.equal(reloaded.events().length, 500)
  assert.equal(reloaded.events().at(-1).event, "page.loaded")
  assert.equal(reloaded.events().at(-2).details.i, 519)
  assert.notEqual(reloaded.events().at(-1).page, f.debug.page)
  reloaded.disable()
  const disabled = new CanvasDebug(f.options)
  const count = disabled.events().length
  disabled.record("pan.started")
  assert.equal(disabled.enabled, false)
  assert.equal(disabled.events().length, count)
  disabled.clear()
  assert.deepEqual(disabled.events(), [])
})

test("raw inputs are scoped and allowlisted; verbose moves are opt-in", () => {
  const f = fixture(), a = attach(f.debug)
  f.debug.enable()
  a.doc.emit("pointermove", {target: a.background, clientX: 20})
  a.doc.emit("pointerdown", {target: a.outside, clientX: 20})
  a.doc.emit("keydown", {target: a.card, key: "a", value: "private input"})
  assert.equal(f.debug.events().length, 1)
  a.doc.emit("pointerdown", {
    target: a.card, pointerId: 7, clientX: 20, clientY: 30,
    token: "private token", email: "private email", detail: {model: "private model"},
  })
  const entry = f.debug.events().at(-1)
  assert.equal(entry.event, "input.pointerdown")
  assert.deepEqual(entry.details, {target: "card", pointerId: 7, x: 20, y: 30})
  assert.equal(JSON.stringify(f.debug.events()).includes("private"), false)
  f.debug.enable({moves: true})
  a.doc.emit("pointermove", {target: a.background, clientX: 42})
  assert.equal(f.debug.events().at(-1).event, "input.pointermove")
  a.state.pan.phase = "dragging"
  a.doc.emit("pointerup", {target: a.outside, pointerId: 7})
  assert.equal(f.debug.events().at(-1).details.target, "outside")
  a.stop()
})

test("lifecycle events are retained and all observers are cleaned up", () => {
  const f = fixture(), a = attach(f.debug)
  f.debug.enable()
  a.doc.emit("phx:update")
  a.win.emit("blur")
  a.win.emit("error", {error: {name: "NotFoundError", message: "private content"}})
  a.win.emit("pagehide", {persisted: false})
  assert.deepEqual(f.debug.events().slice(-4).map(e => e.event),
    ["liveview.patch", "window.blur", "javascript.error", "page.hide"])
  assert.equal(JSON.stringify(f.debug.events()).includes("private"), false)
  a.stop()
  assert.equal(a.doc.count(), 0)
  assert.equal(a.win.count(), 0)
  assert.deepEqual(f.debug.getState(), {})
})

test("malformed or unavailable storage cannot interfere with logging", () => {
  for (const storage of [
    {getItem: () => "{invalid", setItem: () => { throw Error("Storage blocked") }},
    {getItem: () => { throw Error("Storage blocked") }},
  ]) {
    const debug = new CanvasDebug({storage, output: () => {}})
    assert.doesNotThrow(() => debug.enable())
    assert.doesNotThrow(() => debug.record("pan.started"))
    assert.equal(debug.events().at(-1).event, "pan.started")
    assert.doesNotThrow(() => debug.disable())
  }
})

test("diagnostic state or console failures cannot disrupt gesture event dispatch", () => {
  const doc = new Events(), win = new Events()
  doc.defaultView = win
  const debug = new CanvasDebug({output: () => { throw Error("Console unavailable") }})
  const stop = debug.attach({
    host: {ownerDocument: doc}, getCanvas: () => null,
    getState: () => { throw Error("Canvas detached") },
  })
  assert.doesNotThrow(() => debug.enable())
  assert.doesNotThrow(() => doc.emit("pointerdown"))
  assert.doesNotThrow(() => debug.record("pan.cancelled"))
  stop()
  assert.equal(doc.count(), 0)
  assert.equal(win.count(), 0)
})
