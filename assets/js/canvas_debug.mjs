const STORAGE_KEY = "monty.canvas-debug"
const TRACE_LIMIT = 500
const PREFIX = "[monty:canvas]"

// Diagnostics are local, opt-in, and deliberately exclude DOM content, URLs,
// model identifiers, form values, and LiveView/session payloads.
export class CanvasDebug {
  constructor({storage = null, output = (...args) => console.info(...args), now = Date.now} = {}) {
    this.storage = storage
    this.output = output
    this.now = now
    this.page = String(now())
    this.enabled = false
    this.moves = false
    this.entries = []
    this.sequence = 0
    this.getState = () => ({})
    try {
      const saved = JSON.parse(storage?.getItem(STORAGE_KEY) || "null")
      if (saved) {
        this.enabled = saved.enabled === true
        this.moves = saved.moves === true
        this.entries = Array.isArray(saved.entries) ? saved.entries.slice(-TRACE_LIMIT) : []
        this.sequence = this.entries.at(-1)?.sequence || 0
      }
    } catch {
      // Storage may be unavailable or left over from an older asset version.
    }
    this.record("page.loaded")
  }

  enable({moves = false} = {}) {
    this.enabled = true
    this.moves = moves
    this.record("debug.enabled", {moves})
    return "Canvas tracing enabled. Filter the console by [monty:canvas]."
  }

  disable() {
    this.record("debug.disabled")
    this.enabled = false
    this.save()
    return "Canvas tracing disabled."
  }

  clear() {
    this.entries = []
    this.sequence = 0
    this.save()
    return "Canvas trace cleared."
  }

  events() {
    return JSON.parse(JSON.stringify(this.entries))
  }

  dump() {
    const entries = this.events()
    this.output(`${PREFIX} trace`, entries)
    return entries
  }

  save() {
    try {
      this.storage?.setItem(STORAGE_KEY, JSON.stringify({
        enabled: this.enabled, moves: this.moves, entries: this.entries,
      }))
    } catch {
      // Diagnostics must never break a gesture, even when storage is full.
    }
  }

  record(event, details = {}) {
    if (!this.enabled || (event === "input.pointermove" && !this.moves)) return
    try {
      // Store a snapshot, not console's lazy references to mutable gesture state.
      const entry = JSON.parse(JSON.stringify({
        sequence: ++this.sequence, time: this.now(), page: this.page,
        event, details, state: this.getState(),
      }))
      this.entries.push(entry)
      if (this.entries.length > TRACE_LIMIT) this.entries.shift()
      this.output(`${PREFIX} #${entry.sequence} ${event}`, entry)
      // Verbose move samples stay in memory until the next decision/end event.
      if (event !== "input.pointermove") this.save()
    } catch {
      // A diagnostic failure must not change pointer or LiveView behavior.
    }
  }

  attach({host, getCanvas, getState}) {
    const doc = host.ownerDocument, win = doc.defaultView
    this.getState = getState
    const listeners = []
    const listen = (target, type, handler) => {
      target.addEventListener(type, handler, true)
      listeners.push(() => target.removeEventListener(type, handler, true))
    }
    const input = event => {
      if (!this.enabled || (event.type === "pointermove" && !this.moves)) return
      if (event.type === "keydown" && !["Escape", "ArrowLeft", "ArrowRight", "ArrowUp", "ArrowDown"].includes(event.key)) return
      try {
        const pane = getCanvas()?.closest(".canvas-scroll")
        const state = getState()
        const active = (state.drag?.phase && state.drag.phase !== "idle") ||
          (state.pan?.phase && state.pan.phase !== "idle")
        if (!pane?.contains(event.target) && !host.contains(event.target) && !active) return
        const target = host.contains(event.target) ? "capture-host"
          : !pane?.contains(event.target) ? "outside"
          : event.target.closest?.("[data-metric-id]") ? "card"
          : event.target.closest?.("a, button, input, textarea, select") ? "control" : "background"
        this.record(`input.${event.type}`, {
          target, pointerId: event.pointerId, pointerType: event.pointerType,
          button: event.button, buttons: event.buttons, primary: event.isPrimary,
          x: event.clientX, y: event.clientY, key: event.key,
          deltaX: event.deltaX, deltaY: event.deltaY, deltaMode: event.deltaMode,
          defaultPrevented: event.defaultPrevented, trusted: event.isTrusted,
          eventTime: event.timeStamp,
        })
      } catch {
        // A detached canvas or failed snapshot must not disrupt event dispatch.
      }
    }
    for (const type of ["pointerdown", "pointermove", "pointerup", "pointercancel",
      "gotpointercapture", "lostpointercapture", "click", "dblclick", "dragstart",
      "wheel", "focusin", "keydown"]) listen(doc, type, input)
    listen(doc, "phx:update", () => this.record("liveview.patch"))
    listen(doc, "visibilitychange", () => this.record("page.visibility", {visibility: doc.visibilityState}))
    listen(win, "blur", () => this.record("window.blur"))
    listen(win, "focus", () => this.record("window.focus"))
    listen(win, "pagehide", event => this.record("page.hide", {persisted: event.persisted}))
    listen(win, "error", event => this.record("javascript.error", {name: event.error?.name || "Error"}))
    listen(win, "unhandledrejection", event =>
      this.record("javascript.rejection", {name: event.reason?.name || typeof event.reason}))
    return () => {
      listeners.forEach(remove => remove())
      if (this.getState === getState) this.getState = () => ({})
    }
  }
}

let storage = null
try {
  if (typeof window !== "undefined") storage = window.sessionStorage
} catch {
  // The console API still works when the browser disallows session storage.
}
export const canvasDebug = new CanvasDebug({storage})
if (typeof window !== "undefined") window.montyCanvasDebug = canvasDebug
