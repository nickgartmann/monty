// LiveView owns all cards and results. This ignored event bridge only handles
// pointer gestures, downloads, and an asset-compatibility notice. Persisted card
// positions and content remain server-owned.
import {centeredPosition, clampPosition, readGeometry} from "./canvas_geometry.mjs"
import {CanvasDrag} from "./canvas_drag.mjs"

export const ModelInteractions = {
  mounted() {
    const canvas = () => document.getElementById(this.el.dataset.canvasId)
    const geometry = element => {
      const value = readGeometry(element?.dataset)
      if (!value) this.showCompatibilityNotice()
      return value
    }
    geometry(canvas())
    this.canvasDrag = new CanvasDrag({
      host: this.el,
      getCanvas: canvas,
      onInvalidGeometry: () => this.showCompatibilityNotice(),
      onMove: (id, position, done) => {
        this.pushEvent("move-metric", {id, ...position}, () => {
          if (done() && this.el.isConnected) this.pushEvent("select", {id})
        })
      },
    })
    this.canvasDrag.mount()
    this.dblclick = event => {
      const element = canvas()
      const pane = element?.closest(".canvas-scroll")
      if (this.canvasDrag.busy || element?.dataset.editable !== "true" || !pane?.contains(event.target)) return
      if (event.target.closest("[data-metric-id]")) return
      const grid = geometry(element)
      const width = Number(element.dataset.cardWidth), height = Number(element.dataset.cardHeight)
      if (!grid || !Number.isSafeInteger(width) || width <= 0 || !Number.isSafeInteger(height) || height <= 0) {
        this.showCompatibilityNotice()
        return
      }
      event.preventDefault()
      const rect = element.getBoundingClientRect()
      const position = centeredPosition({
        left: event.clientX - rect.left,
        top: event.clientY - rect.top,
      }, {width, height}, grid)
      const previousSelection = document.getElementById("metric-id")?.value
      this.pushEvent("add-metric", position, () => {
        if (!this.el.isConnected) return
        const selected = document.getElementById("metric-id")?.value
        if (!selected || selected === previousSelection) return
        const name = document.getElementById("metric_name")
        const bounds = name?.getBoundingClientRect()
        if (bounds && bounds.top >= 0 && bounds.bottom <= window.innerHeight) {
          name.focus({preventScroll: true})
          name.select()
        }
      })
    }
    this.keydown = event => {
      if (this.canvasDrag.busy) return
      const card = event.target.closest("[data-metric-id][data-movable=true], [data-metric-id][draggable=true]")
      const element = canvas()
      if (!card || !element?.contains(card) || event.altKey || event.ctrlKey || event.metaKey) return
      const directions = {ArrowLeft: [-1, 0], ArrowUp: [0, -1], ArrowDown: [0, 1], ArrowRight: [1, 0]}
      const direction = directions[event.key]
      if (!direction) return
      event.preventDefault()
      const grid = geometry(element)
      if (!grid) return
      const distance = event.shiftKey ? 5 : 1
      const current = {x: Number(card.dataset.gridX), y: Number(card.dataset.gridY)}
      const position = clampPosition({
        x: current.x + direction[0] * distance,
        y: current.y + direction[1] * distance,
      }, grid)
      if (position.x !== current.x || position.y !== current.y) {
        this.pushEvent("move-metric", {id: card.dataset.metricId, ...position})
      }
    }
    document.addEventListener("dblclick", this.dblclick)
    document.addEventListener("keydown", this.keydown)
    this.handleEvent("download-model", ({name, content}) => {
      const url = URL.createObjectURL(new Blob([content], {type: "application/json"}))
      const link = document.createElement("a")
      link.href = url
      link.download = name
      link.click()
      setTimeout(() => URL.revokeObjectURL(url), 1000)
    })
  },
  showCompatibilityNotice() {
    if (this.el.querySelector("#canvas-update-notice")) return
    const notice = document.createElement("div")
    notice.id = "canvas-update-notice"
    notice.setAttribute("role", "alert")
    notice.className = "fixed bottom-4 right-4 z-50 max-w-sm rounded-xl border border-amber-200 bg-amber-50 p-4 text-sm text-amber-950 shadow-lg"
    const message = document.createElement("p")
    message.textContent = "The canvas and its assets are from different versions. Reload the page before moving cards."
    const reload = document.createElement("button")
    reload.type = "button"
    reload.className = "button-secondary mt-3"
    reload.textContent = "Reload page"
    reload.addEventListener("click", () => window.location.reload())
    notice.append(message, reload)
    this.el.append(notice)
  },
  disconnected() {
    this.canvasDrag?.cancel()
  },
  destroyed() {
    this.canvasDrag?.destroy()
    document.removeEventListener("dblclick", this.dblclick)
    document.removeEventListener("keydown", this.keydown)
  }
}
