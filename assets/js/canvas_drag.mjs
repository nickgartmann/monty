import {readGeometry, readZoom, snapPosition} from "./canvas_geometry.mjs"
import {canvasDebug} from "./canvas_debug.mjs"
import {updateCanvasLinks} from "./canvas_links.mjs"
import {primaryButtonReleased} from "./canvas_pointer.mjs"

const DRAG_THRESHOLD = 5

function editableCard(target) {
  const card = target?.closest?.("[data-metric-id]")
  return card && (card.dataset.movable === "true" || card.getAttribute("draggable") === "true")
    ? card
    : null
}

// Card surfaces move, but controls embedded in them own their pointer and keys.
export function isCardControl(target, card) {
  const control = target?.closest?.("a, button, input, select, textarea, label, [contenteditable], [data-card-controls]")
  return !!control && control !== card && card.contains(control)
}

function visibleBounds(rect, viewport) {
  const left = Math.max(0, rect.left)
  const top = Math.max(0, rect.top)
  const right = Math.min(viewport.innerWidth, rect.right)
  const bottom = Math.min(viewport.innerHeight, rect.bottom)
  return {left, top, width: Math.max(0, right - left), height: Math.max(0, bottom - top)}
}

// LiveView still owns card content and left/top. Preserve only the transient
// pointer presentation until the drag's acknowledged move clears it.
export function preserveDragStyles(from, to) {
  const phases = ["metric-card-dragging", "metric-card-settling"]
    .filter(name => from.classList?.contains(name))
  if (phases.length === 0) return
  to.style.transform = from.style.transform
  to.style.transition = from.style.transition
  to.classList.add(...phases)
}

export class CanvasDrag {
  constructor({host, getCanvas, onMove, onInvalidGeometry, isBusy = () => false}) {
    this.host = host
    this.getCanvas = getCanvas
    this.onMove = onMove
    this.onInvalidGeometry = onInvalidGeometry
    this.isBusy = isBusy
    this.doc = host.ownerDocument
    this.win = this.doc.defaultView
    this.active = null
    this.frame = null
    this.mounted = false
    this.suppressClick = false

    this.pointerDown = this.pointerDown.bind(this)
    this.pointerMove = this.pointerMove.bind(this)
    this.pointerUp = this.pointerUp.bind(this)
    this.pointerCancel = this.pointerCancel.bind(this)
    this.lostCapture = this.lostCapture.bind(this)
    this.keyDown = this.keyDown.bind(this)
    this.scroll = this.scroll.bind(this)
    this.dragStart = this.dragStart.bind(this)
    this.click = this.click.bind(this)
  }

  get busy() {
    return this.active !== null
  }

  get gesturing() {
    return this.active !== null && this.active.phase !== "settling"
  }

  mount() {
    if (this.mounted) return
    this.mounted = true
    this.layer = this.doc.createElement("div")
    this.layer.className = "canvas-drag-layer"
    this.layer.setAttribute("aria-hidden", "true")
    this.layer.style.position = "fixed"
    this.layer.style.overflow = "hidden"
    this.layer.style.pointerEvents = "none"
    this.layer.style.display = "none"
    this.preview = this.doc.createElement("div")
    this.preview.className = "canvas-drop-preview"
    this.preview.style.position = "absolute"
    this.layer.append(this.preview)
    this.host.append(this.layer)

    this.doc.addEventListener("pointerdown", this.pointerDown)
    this.doc.addEventListener("pointermove", this.pointerMove)
    this.doc.addEventListener("pointerup", this.pointerUp)
    this.doc.addEventListener("pointercancel", this.pointerCancel)
    this.doc.addEventListener("dragstart", this.dragStart, true)
    this.doc.addEventListener("keydown", this.keyDown)
    this.doc.addEventListener("phx:update", this.scroll)
    this.host.addEventListener("lostpointercapture", this.lostCapture)
    this.win.addEventListener("blur", this.cancelBound ||= () => this.cancel("blur"))
    this.win.addEventListener("scroll", this.scroll, true)
    if (!readGeometry(this.getCanvas()?.dataset)) this.onInvalidGeometry()
  }

  destroy() {
    if (!this.mounted) return
    this.cancel("destroy")
    this.clearClickSuppression()
    this.doc.removeEventListener("pointerdown", this.pointerDown)
    this.doc.removeEventListener("pointermove", this.pointerMove)
    this.doc.removeEventListener("pointerup", this.pointerUp)
    this.doc.removeEventListener("pointercancel", this.pointerCancel)
    this.doc.removeEventListener("dragstart", this.dragStart, true)
    this.doc.removeEventListener("keydown", this.keyDown)
    this.doc.removeEventListener("phx:update", this.scroll)
    this.host.removeEventListener("lostpointercapture", this.lostCapture)
    this.win.removeEventListener("blur", this.cancelBound)
    this.win.removeEventListener("scroll", this.scroll, true)
    this.layer.remove()
    this.layer = null
    this.preview = null
    this.mounted = false
  }

  dragStart(event) {
    const card = editableCard(event.target)
    if (card && this.getCanvas()?.contains(card) && !isCardControl(event.target, card)) event.preventDefault()
  }

  pointerDown(event) {
    // A new pointer gesture cannot inherit a click suppression from the last drag.
    this.clearClickSuppression()
    const candidate = event.target?.closest?.("[data-metric-id]")
    const canvas = this.getCanvas()
    if (!candidate || !canvas?.contains(candidate)) return
    if (isCardControl(event.target, candidate)) {
      canvasDebug.record("drag.start_ignored", {reason: "interactive_target"})
      return
    }
    if (this.busy) {
      canvasDebug.record("drag.start_ignored", {reason: "busy"})
      return
    }
    if (this.isBusy()) {
      canvasDebug.record("drag.start_ignored", {reason: "another_gesture"})
      return
    }
    if (event.isPrimary === false || event.button !== 0 ||
        !["mouse", "pen", "touch"].includes(event.pointerType)) {
      canvasDebug.record("drag.start_ignored", {reason: "unsupported_pointer"})
      return
    }
    const card = editableCard(event.target)
    if (!card) {
      canvasDebug.record("drag.start_ignored", {reason: "read_only_card"})
      return
    }
    const grid = readGeometry(canvas.dataset)
    if (!grid) {
      canvasDebug.record("drag.start_ignored", {reason: "invalid_geometry"})
      this.onInvalidGeometry()
      return
    }
    const rect = card.getBoundingClientRect()
    const canvasRect = canvas.getBoundingClientRect()
    const zoom = readZoom(canvas.dataset)
    this.active = {
      phase: "pending",
      pointerId: event.pointerId,
      card,
      canvas,
      grid,
      zoom,
      startX: event.clientX,
      startY: event.clientY,
      clientX: event.clientX,
      clientY: event.clientY,
      offsetX: event.clientX - rect.left,
      offsetY: event.clientY - rect.top,
      originLeft: (rect.left - canvasRect.left) / zoom,
      originTop: (rect.top - canvasRect.top) / zoom,
      width: rect.width,
      height: rect.height,
      transform: card.style.transform,
      transition: card.style.transition,
      source: {x: Number(card.dataset.gridX), y: Number(card.dataset.gridY)},
      links: this.incidentPaths(canvas, card.dataset.metricId),
      captured: false,
    }
    canvasDebug.record("drag.start_accepted", {pointerType: event.pointerType})
  }

  pointerMove(event, capture = true) {
    const state = this.active
    if (!state || state.phase === "settling" || event.pointerId !== state.pointerId) return
    if (!this.valid(state)) return
    if (capture && primaryButtonReleased(event)) {
      canvasDebug.record("drag.release_recovered", {source: "pointermove"})
      this.pointerUp(event)
      return
    }
    state.clientX = event.clientX
    state.clientY = event.clientY
    if (state.phase === "pending") {
      if (Math.hypot(event.clientX - state.startX, event.clientY - state.startY) < DRAG_THRESHOLD) return
      state.phase = "dragging"
      canvasDebug.record("drag.threshold_crossed")
      state.card.classList.add("metric-card-dragging")
      // Let the short CSS transform transition soften pointer samples.
      state.card.style.transition = ""
      if (capture) {
        this.host.setPointerCapture(state.pointerId)
        state.captured = true
        canvasDebug.record("drag.capture_acquired")
      }
    }
    event.preventDefault()
    this.scheduleFrame()
  }

  pointerUp(event) {
    const state = this.active
    if (!state || event.pointerId !== state.pointerId || state.phase === "settling") return
    if (!this.valid(state)) return
    // A fast gesture may reach the threshold only in its final pointer sample.
    // Reuse movement handling, but never acquire capture after release.
    this.pointerMove(event, false)
    if (state.phase === "pending") {
      this.cancel("below_threshold")
      return
    }
    event.preventDefault()
    this.cancelFrame()
    state.clientX = event.clientX
    state.clientY = event.clientY
    this.update(state)
    this.suppressNextClick()
    this.releaseCapture(state)
    this.layer.style.display = "none"
    const target = state.target
    if (state.invalid) {
      canvasDebug.record("drag.drop_rejected", {reason: "occupied"})
      this.cancel("rejected_drop")
      return
    }
    if (target.x === state.source.x && target.y === state.source.y) {
      canvasDebug.record("drag.drop_unchanged")
      this.cancel("unchanged_drop")
      return
    }
    canvasDebug.record("drag.drop_committed")
    state.phase = "settling"
    state.card.classList.remove("metric-card-dragging")
    state.card.classList.add("metric-card-settling")
    const dx = state.grid.padding + (target.x - state.grid.originX) * state.grid.step - state.originLeft
    const dy = state.grid.padding + (target.y - state.grid.originY) * state.grid.step - state.originTop
    this.transformCard(state, dx, dy)
    this.updateLinks(state)
    try {
      this.onMove(state.card.dataset.metricId, target, () => {
        if (this.active !== state) {
          canvasDebug.record("drag.move_stale_acknowledgement")
          return false
        }
        canvasDebug.record("drag.move_acknowledged")
        this.cancel("ack_cleanup")
        return true
      })
    } catch (error) {
      this.cancel("move_exception")
      throw error
    }
  }

  pointerCancel(event) {
    if (event.pointerId === this.active?.pointerId) this.cancel("pointercancel")
  }

  lostCapture(event) {
    if (event.pointerId === this.active?.pointerId && this.active.captured &&
        !this.host.hasPointerCapture(event.pointerId)) {
      canvasDebug.record("drag.capture_lost")
      if (primaryButtonReleased(event)) {
        canvasDebug.record("drag.release_recovered", {source: "lostpointercapture"})
        this.pointerUp(event)
      } else {
        this.cancel("capture_lost")
      }
    }
  }

  keyDown(event) {
    if (event.key === "Escape" && this.active && this.active.phase !== "settling") {
      event.preventDefault()
      this.cancel("escape")
    }
  }

  scroll() {
    const state = this.active
    if (state?.phase === "dragging") {
      this.scheduleFrame()
    }
  }

  scheduleFrame() {
    if (this.frame !== null) return
    this.frame = this.win.requestAnimationFrame(() => {
      this.frame = null
      const state = this.active
      if (state?.phase !== "dragging" || !this.valid(state)) return
      // Paint only the latest pointer sample, and keep links attached throughout
      // the CSS interpolation, including when the pointer pauses.
      this.update(state)
      this.scheduleFrame()
    })
  }

  cancelFrame() {
    if (this.frame === null) return
    this.win.cancelAnimationFrame(this.frame)
    this.frame = null
  }

  valid(state) {
    const canvas = this.getCanvas()
    if (canvas === state.canvas && state.canvas.contains(state.card) &&
        state.card.isConnected && readGeometry(state.canvas.dataset)) return true
    if (!readGeometry(this.getCanvas()?.dataset)) this.onInvalidGeometry()
    const reason = canvas !== state.canvas ? "canvas_removed"
      : !state.canvas.contains(state.card) || !state.card.isConnected ? "card_removed"
        : "invalid_geometry"
    this.cancel(reason)
    return false
  }

  update(state) {
    const {step, padding, originX, originY} = state.grid
    const rect = state.canvas.getBoundingClientRect()
    const left = (state.clientX - rect.left - state.offsetX) / state.zoom
    const top = (state.clientY - rect.top - state.offsetY) / state.zoom
    this.transformCard(state, left - state.originLeft, top - state.originTop)
    this.updateLinks(state)
    const target = snapPosition({left, top}, state.grid)
    state.target = target
    state.invalid = [...state.canvas.querySelectorAll("[data-metric-id]")]
      .some(card => card !== state.card &&
        Number(card.dataset.gridX) === target.x && Number(card.dataset.gridY) === target.y)
    const pane = state.canvas.closest(".canvas-scroll")
    const bounds = visibleBounds((pane || state.canvas).getBoundingClientRect(), this.win)
    Object.assign(this.layer.style, {
      display: "block",
      left: `${bounds.left}px`,
      top: `${bounds.top}px`,
      width: `${bounds.width}px`,
      height: `${bounds.height}px`,
    })
    Object.assign(this.preview.style, {
      left: "0px",
      top: "0px",
      width: `${state.width}px`,
      height: `${state.height}px`,
    })
    const previewTransform = `translate3d(${rect.left + (padding + (target.x - originX) * step) * state.zoom - bounds.left}px, ${rect.top + (padding + (target.y - originY) * step) * state.zoom - bounds.top}px, 0)`
    if (this.preview.style.transform !== previewTransform) this.preview.style.transform = previewTransform
    this.preview.dataset.gridX = String(target.x)
    this.preview.dataset.gridY = String(target.y)
    if (state.invalid) this.preview.dataset.invalid = "true"
    else delete this.preview.dataset.invalid
  }

  transformCard(state, dx, dy) {
    const transform = `translate3d(${dx}px, ${dy}px, 0)${state.transform ? ` ${state.transform}` : ""}`
    if (state.card.style.transform !== transform) state.card.style.transform = transform
  }

  incidentPaths(canvas, id) {
    return [...canvas.querySelectorAll(".dependency-path[data-source-id][data-target-id]")]
      .filter(path => path.dataset.sourceId === id || path.dataset.targetId === id)
  }

  updateLinks(state, paths = state.links) {
    updateCanvasLinks(state.canvas, paths)
  }

  refreshLinks() {
    const state = this.active
    if (!state || state.phase === "pending") return
    state.links = this.incidentPaths(state.canvas, state.card.dataset.metricId)
    this.updateLinks(state)
  }

  releaseCapture(state) {
    if (state.captured) {
      state.captured = false
      if (this.host.hasPointerCapture(state.pointerId)) {
        this.host.releasePointerCapture(state.pointerId)
        canvasDebug.record("drag.capture_released")
      }
    }
  }

  cancel(reason = "cancelled") {
    this.cancelFrame()
    const state = this.active
    if (!state) return
    canvasDebug.record(reason === "ack_cleanup" ? "drag.finished" : "drag.cancelled", {reason})
    this.active = null
    // A cancelled drag can still generate a browser click when its pointer is released.
    if (state.phase === "dragging") this.suppressNextClick()
    this.releaseCapture(state)
    state.card.style.transform = state.transform
    state.card.style.transition = state.transition
    state.card.classList.remove("metric-card-dragging", "metric-card-settling")
    this.updateLinks(state, this.incidentPaths(state.canvas, state.card.dataset.metricId))
    this.layer.style.display = "none"
    delete this.preview.dataset.invalid
  }

  suppressNextClick() {
    this.suppressClick = true
    this.doc.addEventListener("click", this.click, true)
  }

  click(event) {
    if (event.detail > 0) {
      canvasDebug.record("drag.click_suppressed")
      event.preventDefault()
      event.stopImmediatePropagation()
      this.clearClickSuppression()
    }
  }

  clearClickSuppression() {
    if (!this.suppressClick) return
    this.suppressClick = false
    this.doc.removeEventListener("click", this.click, true)
  }
}
