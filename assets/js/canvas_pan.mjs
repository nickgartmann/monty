import {readGeometry} from "./canvas_geometry.mjs"
import {canvasDebug} from "./canvas_debug.mjs"
import {updateCanvasLinks} from "./canvas_links.mjs"
import {primaryButtonReleased} from "./canvas_pointer.mjs"

const PAN_THRESHOLD = 5
const MIN_ZOOM = 0.25
const MAX_ZOOM = 2
const ZOOM_STEP = 1.25
const PAN_PROPERTIES = ["--canvas-pan-x", "--canvas-pan-y", "--canvas-origin-x", "--canvas-origin-y",
  "--canvas-zoom", "--canvas-grid-size", "--canvas-grid-offset"]

export function isCanvasControl(target) {
  return target?.closest?.("[data-canvas-controls]") != null
}

// LiveView owns the world; the local viewport is presentation, not model data.
export function preservePanStyles(from, to) {
  if (from.hasAttribute?.("data-model-canvas")) {
    for (const key of ["gridOriginX", "gridOriginY", "canvasZoom"]) {
      if (from.dataset[key] !== undefined) to.dataset[key] = from.dataset[key]
    }
  }
  if (!from.hasAttribute?.("data-canvas-viewport")) return
  for (const property of PAN_PROPERTIES) {
    to.style.setProperty(property, from.style.getPropertyValue(property))
  }
  if (from.classList.contains("canvas-panning")) to.classList.add("canvas-panning")
}

export class CanvasPan {
  constructor({host, getCanvas, isBusy, onRender = () => {}}) {
    this.host = host
    this.getCanvas = getCanvas
    this.isBusy = isBusy
    this.onRender = onRender
    this.doc = host.ownerDocument
    this.win = this.doc.defaultView
    this.position = {x: 0, y: 0}
    this.zoom = 1
    this.active = null
    for (const name of ["pointerDown", "pointerMove", "pointerUp", "pointerCancel",
      "lostCapture", "keyDown", "focusIn", "wheel", "zoomClick", "click", "refresh", "cancel"]) {
      this[name] = this[name].bind(this)
    }
    this.blur = () => this.cancel("blur")
  }

  get pane() {
    return this.getCanvas()?.closest(".canvas-scroll")
  }

  get busy() {
    return this.active !== null
  }

  mount() {
    // Reopened models may have cards far from (0, 0), including negative space.
    // Start with the first card in view rather than an empty patch of world.
    const canvas = this.getCanvas()
    const grid = readGeometry(canvas?.dataset)
    const first = canvas?.querySelector("[data-metric-id]")
    if (grid && first) {
      const x = Number(first.dataset.gridX), y = Number(first.dataset.gridY)
      if (Number.isSafeInteger(x) && Number.isSafeInteger(y)) {
        this.position = {x: -x * grid.step, y: -y * grid.step}
      }
    }
    this.refresh()
    this.doc.addEventListener("pointerdown", this.pointerDown)
    this.doc.addEventListener("pointermove", this.pointerMove)
    this.doc.addEventListener("pointerup", this.pointerUp)
    this.doc.addEventListener("pointercancel", this.pointerCancel)
    this.doc.addEventListener("keydown", this.keyDown)
    this.doc.addEventListener("focusin", this.focusIn)
    this.doc.addEventListener("wheel", this.wheel, {passive: false})
    this.doc.addEventListener("click", this.zoomClick)
    this.doc.addEventListener("phx:update", this.refresh)
    this.host.addEventListener("lostpointercapture", this.lostCapture)
    this.win.addEventListener("blur", this.blur)
  }

  refresh() {
    if (this.active && this.pane !== this.active.pane) {
      this.cancel(this.getCanvas() ? "pane_changed" : "canvas_removed")
    }
    const pane = this.pane
    const canvas = this.getCanvas()
    const grid = readGeometry(canvas?.dataset)
    if (!pane || !grid) return
    // Keep layout coordinates and transforms small, even when world coordinates
    // are distant. CSS subtracts this origin before applying layout limits.
    const originX = Math.floor(-this.position.x / (grid.step * this.zoom))
    const originY = Math.floor(-this.position.y / (grid.step * this.zoom))
    canvas.dataset.gridOriginX = String(originX)
    canvas.dataset.gridOriginY = String(originY)
    canvas.dataset.canvasZoom = String(this.zoom)
    pane.style.setProperty("--canvas-origin-x", `${originX * grid.step}px`)
    pane.style.setProperty("--canvas-origin-y", `${originY * grid.step}px`)
    pane.style.setProperty("--canvas-pan-x", `${this.position.x + originX * grid.step * this.zoom}px`)
    pane.style.setProperty("--canvas-pan-y", `${this.position.y + originY * grid.step * this.zoom}px`)
    pane.style.setProperty("--canvas-zoom", String(this.zoom))
    pane.style.setProperty("--canvas-grid-size", `${grid.step * this.zoom}px`)
    pane.style.setProperty("--canvas-grid-offset", `${(grid.padding % grid.step - grid.step / 2) * this.zoom}px`)
    pane.classList.toggle("canvas-panning", this.active?.dragging === true)
    const percent = Math.round(this.zoom * 100)
    const label = pane.querySelector?.("#canvas-zoom-level")
    if (label) {
      label.textContent = `${percent}%`
      label.setAttribute("aria-label", `Zoom ${percent}%. Reset zoom to 100%`)
    }
    const status = pane.querySelector?.("#canvas-zoom-status")
    if (status && status.textContent !== `Zoom ${percent}%`) status.textContent = `Zoom ${percent}%`
    const out = pane.querySelector?.("#canvas-zoom-out")
    const into = pane.querySelector?.("#canvas-zoom-in")
    if (out) out.disabled = this.zoom <= MIN_ZOOM
    if (into) into.disabled = this.zoom >= MAX_ZOOM
    updateCanvasLinks(canvas, undefined, true)
    this.onRender()
  }

  setZoom(value, anchor) {
    if (this.busy || this.isBusy() || !Number.isFinite(value) || !this.pane) return
    const zoom = Math.min(MAX_ZOOM, Math.max(MIN_ZOOM, value))
    if (zoom === this.zoom) return
    const bounds = this.pane.getBoundingClientRect()
    anchor ||= {x: (bounds.right - bounds.left) / 2, y: (bounds.bottom - bounds.top) / 2}
    // Keep the world point under the pointer (or viewport center) stationary.
    const ratio = zoom / this.zoom
    this.position = {
      x: anchor.x - (anchor.x - this.position.x) * ratio,
      y: anchor.y - (anchor.y - this.position.y) * ratio,
    }
    this.zoom = zoom
    this.refresh()
  }

  zoomClick(event) {
    const button = event.target.closest?.("[data-canvas-zoom]")
    if (!button || button.disabled || !this.pane?.contains(button)) return
    const action = button.dataset.canvasZoom
    if (!["in", "out", "reset"].includes(action)) return
    event.preventDefault()
    this.setZoom(action === "reset" ? 1 : this.zoom * (action === "in" ? ZOOM_STEP : 1 / ZOOM_STEP))
  }

  pointerDown(event) {
    this.clearClickSuppression()
    const pane = this.pane
    if (isCanvasControl(event.target) || !pane?.contains(event.target)) return
    // Every card, including read-only cards, keeps its own click interaction.
    if (event.target.closest("[data-metric-id], a, button, form, input, textarea, select, label, [contenteditable]")) {
      canvasDebug.record("pan.start_ignored", {reason: "interactive_target"})
      return
    }
    if (this.busy) {
      canvasDebug.record("pan.start_ignored", {reason: "busy"})
      return
    }
    if (this.isBusy()) {
      canvasDebug.record("pan.start_ignored", {reason: "another_gesture"})
      return
    }
    if (event.isPrimary === false || event.button !== 0 ||
        !["mouse", "pen", "touch"].includes(event.pointerType)) {
      canvasDebug.record("pan.start_ignored", {reason: "unsupported_pointer"})
      return
    }
    this.active = {
      pane, pointerId: event.pointerId, startX: event.clientX, startY: event.clientY,
      origin: {...this.position}, dragging: false, captured: false,
    }
    canvasDebug.record("pan.start_accepted", {pointerType: event.pointerType})
  }

  pointerMove(event, capture = true) {
    const state = this.active
    if (!state || event.pointerId !== state.pointerId) return
    if (this.pane !== state.pane) {
      this.cancel(this.getCanvas() ? "pane_changed" : "canvas_removed")
      return
    }
    if (capture && primaryButtonReleased(event)) {
      canvasDebug.record("pan.release_recovered", {source: "pointermove"})
      this.pointerUp(event)
      return
    }
    const dx = event.clientX - state.startX, dy = event.clientY - state.startY
    if (!state.dragging) {
      if (Math.hypot(dx, dy) < PAN_THRESHOLD) return
      state.dragging = true
      canvasDebug.record("pan.threshold_crossed")
      if (capture) {
        this.host.setPointerCapture(state.pointerId)
        state.captured = true
        canvasDebug.record("pan.capture_acquired")
      }
    }
    event.preventDefault()
    this.position = {x: state.origin.x + dx, y: state.origin.y + dy}
    this.refresh()
  }

  pointerUp(event) {
    const state = this.active
    if (!state || event.pointerId !== state.pointerId) return
    // Release is also a movement sample, even if no move event crossed the
    // threshold. The released pointer can no longer acquire capture.
    this.pointerMove(event, false)
    if (this.active !== state) return
    if (state.dragging) {
      event.preventDefault()
      this.suppressNextClick()
    }
    canvasDebug.record("pan.finished", {dragged: state.dragging})
    this.finish()
  }

  pointerCancel(event) {
    if (event.pointerId === this.active?.pointerId) this.cancel("pointercancel")
  }

  lostCapture(event) {
    if (event.pointerId === this.active?.pointerId && this.active.captured &&
        !this.host.hasPointerCapture(event.pointerId)) {
      canvasDebug.record("pan.capture_lost")
      if (primaryButtonReleased(event)) {
        canvasDebug.record("pan.release_recovered", {source: "lostpointercapture"})
        this.pointerUp(event)
      } else {
        this.cancel("capture_lost")
      }
    }
  }

  cancel(reason = "cancelled") {
    if (!this.active) return
    canvasDebug.record("pan.cancelled", {reason})
    this.position = this.active.origin
    if (this.active.dragging) this.suppressNextClick()
    this.finish()
  }

  finish() {
    const state = this.active
    this.active = null
    if (state?.captured && this.host.hasPointerCapture(state.pointerId)) {
      this.host.releasePointerCapture(state.pointerId)
      canvasDebug.record("pan.capture_released")
    }
    state?.pane.classList.remove("canvas-panning")
    this.refresh()
  }

  keyDown(event) {
    if (isCanvasControl(event.target)) return
    if (event.key === "Escape" && this.active) {
      event.preventDefault()
      this.cancel("escape")
      return
    }
    if (this.busy || this.isBusy() || event.target !== this.pane ||
        event.altKey || event.ctrlKey || event.metaKey) return
    if (["+", "=", "-", "0"].includes(event.key)) {
      event.preventDefault()
      this.setZoom(event.key === "0" ? 1 : this.zoom * (event.key === "-" ? 1 / ZOOM_STEP : ZOOM_STEP))
      return
    }
    const directions = {ArrowLeft: [1, 0], ArrowRight: [-1, 0], ArrowUp: [0, 1], ArrowDown: [0, -1]}
    const direction = directions[event.key]
    if (!direction) return
    event.preventDefault()
    const distance = event.shiftKey ? 200 : 40
    this.position.x += direction[0] * distance
    this.position.y += direction[1] * distance
    this.refresh()
  }

  focusIn(event) {
    if (isCanvasControl(event.target)) return
    const card = event.target.closest?.("[data-metric-id]")
    if (!card || this.busy || this.isBusy() || !this.getCanvas()?.contains(card)) return
    // Keyboard focus reveals a card using the same camera as pointer panning,
    // never a second, hidden browser scroll offset.
    const bounds = this.pane.getBoundingClientRect()
    const canvas = this.getCanvas()
    const grid = readGeometry(canvas.dataset)
    if (!grid) return
    // An offscreen card's DOM rectangle may already be clamped by the browser.
    const left = bounds.left + (grid.padding + Number(card.dataset.gridX) * grid.step) * this.zoom + this.position.x
    const top = bounds.top + (grid.padding + Number(card.dataset.gridY) * grid.step) * this.zoom + this.position.y
    const rect = {left, top, right: left + Number(canvas.dataset.cardWidth) * this.zoom,
      bottom: top + Number(canvas.dataset.cardHeight) * this.zoom}
    const dx = rect.left < bounds.left ? bounds.left + 16 - rect.left
      : rect.right > bounds.right ? bounds.right - 16 - rect.right : 0
    const dy = rect.top < bounds.top ? bounds.top + 16 - rect.top
      : rect.bottom > bounds.bottom ? bounds.bottom - 16 - rect.bottom : 0
    this.position.x += dx
    this.position.y += dy
    this.refresh()
  }

  wheel(event) {
    if (isCanvasControl(event.target) || this.busy || this.isBusy() ||
        !this.pane?.contains(event.target)) return
    event.preventDefault()
    const scale = event.deltaMode === 1 ? 20 : event.deltaMode === 2 ? this.pane.clientHeight : 1
    if (event.ctrlKey || event.metaKey) {
      const bounds = this.pane.getBoundingClientRect()
      const exponent = Math.min(4, Math.max(-4, -event.deltaY * scale * 0.01))
      this.setZoom(this.zoom * Math.exp(exponent), {
        x: event.clientX - bounds.left, y: event.clientY - bounds.top,
      })
      return
    }
    const dx = event.shiftKey && !event.deltaX ? event.deltaY : event.deltaX
    const dy = event.shiftKey && !event.deltaX ? 0 : event.deltaY
    this.position.x -= dx * scale
    this.position.y -= dy * scale
    this.refresh()
  }

  suppressNextClick() {
    this.clearClickSuppression()
    this.doc.addEventListener("click", this.click, true)
    this.doc.addEventListener("dblclick", this.click, true)
    this.clickTimer = this.win.setTimeout(() => this.clearClickSuppression(), 400)
  }

  click(event) {
    if (isCanvasControl(event.target) ||
        (!this.pane?.contains(event.target) && event.target !== this.host)) return
    canvasDebug.record("pan.click_suppressed")
    event.preventDefault()
    event.stopImmediatePropagation()
  }

  clearClickSuppression() {
    this.doc.removeEventListener("click", this.click, true)
    this.doc.removeEventListener("dblclick", this.click, true)
    if (this.clickTimer) this.win.clearTimeout(this.clickTimer)
    this.clickTimer = null
  }

  destroy() {
    this.cancel("destroy")
    this.clearClickSuppression()
    this.doc.removeEventListener("pointerdown", this.pointerDown)
    this.doc.removeEventListener("pointermove", this.pointerMove)
    this.doc.removeEventListener("pointerup", this.pointerUp)
    this.doc.removeEventListener("pointercancel", this.pointerCancel)
    this.doc.removeEventListener("keydown", this.keyDown)
    this.doc.removeEventListener("focusin", this.focusIn)
    this.doc.removeEventListener("wheel", this.wheel)
    this.doc.removeEventListener("click", this.zoomClick)
    this.doc.removeEventListener("phx:update", this.refresh)
    this.host.removeEventListener("lostpointercapture", this.lostCapture)
    this.win.removeEventListener("blur", this.blur)
  }
}
