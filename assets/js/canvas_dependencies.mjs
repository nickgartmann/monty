const PATHS = ".dependency-path[data-source-id][data-target-id]"
const HIGHLIGHT = "dependency-path-highlighted"

// Follow incoming edges only. Shared ancestors and cycles are visited once.
export function upstreamPaths(paths, targetId) {
  const incoming = new Map()
  for (const path of paths) {
    const target = path.dataset.targetId
    if (!incoming.has(target)) incoming.set(target, [])
    incoming.get(target).push(path)
  }
  const highlighted = new Set(), visited = new Set(), pending = [targetId]
  while (pending.length) {
    const target = pending.pop()
    if (target == null || visited.has(target)) continue
    visited.add(target)
    for (const path of incoming.get(target) || []) {
      highlighted.add(path)
      pending.push(path.dataset.sourceId)
    }
  }
  return highlighted
}

export class CanvasDependencies {
  constructor({host, getCanvas}) {
    this.doc = host.ownerDocument
    this.getCanvas = getCanvas
    this.hoveredId = null
    this.focusedId = null
    this.pointerOver = event => this.hover(event, event.target)
    this.pointerOut = event => this.hover(event, event.relatedTarget)
    this.focusIn = event => this.focus(event.target)
    this.focusOut = event => this.focus(event.relatedTarget)
    this.refresh = this.refresh.bind(this)
    this.listeners = {
      pointerover: this.pointerOver, pointerout: this.pointerOut,
      focusin: this.focusIn, focusout: this.focusOut,
      "phx:update": this.refresh,
    }
  }

  mount() {
    for (const [type, listener] of Object.entries(this.listeners)) {
      this.doc.addEventListener(type, listener)
    }
    this.focus(this.doc.activeElement)
  }

  metricId(target) {
    const card = target?.closest?.("[data-metric-id]")
    return card && this.getCanvas()?.contains(card) ? card.dataset.metricId : null
  }

  hover(event, target) {
    // Touch taps select/edit cards; they should not leave a sticky hover trail.
    if (event.pointerType === "touch") return
    const id = this.metricId(target)
    if (id === this.hoveredId) return
    this.hoveredId = id
    this.refresh()
  }

  focus(target) {
    this.focusedId = this.metricId(target)
    this.refresh()
  }

  refresh() {
    const canvas = this.getCanvas()
    if (!canvas) return
    const ids = new Set([...canvas.querySelectorAll("[data-metric-id]")].map(card => card.dataset.metricId))
    if (!ids.has(this.hoveredId)) this.hoveredId = null
    if (!ids.has(this.focusedId)) this.focusedId = null
    const paths = [...canvas.querySelectorAll(PATHS)]
    const highlighted = upstreamPaths(paths, this.hoveredId ?? this.focusedId)
    for (const path of paths) path.classList.toggle(HIGHLIGHT, highlighted.has(path))
  }

  destroy() {
    for (const [type, listener] of Object.entries(this.listeners)) {
      this.doc.removeEventListener(type, listener)
    }
    for (const path of this.getCanvas()?.querySelectorAll(PATHS) || []) {
      path.classList.remove(HIGHLIGHT)
    }
  }
}
