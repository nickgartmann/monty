// LiveView owns all cards and results. This ignored event bridge only handles
// browser drag gestures, downloads, and an asset-compatibility notice. It never
// renders model content.
import {clampPosition, readGeometry, snapPosition} from "./canvas_geometry.mjs"

export const ModelInteractions = {
  mounted() {
    const canvas = () => document.getElementById(this.el.dataset.canvasId)
    const geometry = element => {
      const value = readGeometry(element?.dataset)
      if (!value) this.showCompatibilityNotice()
      return value
    }
    geometry(canvas())
    this.dragstart = event => {
      const card = event.target.closest("[data-metric-id][draggable=true]")
      if (!card || !canvas()?.contains(card)) return
      if (!geometry(canvas())) {
        event.preventDefault()
        return
      }
      const rect = card.getBoundingClientRect()
      event.dataTransfer.setData("text/monty-metric", JSON.stringify({
        id: card.dataset.metricId,
        offsetX: event.clientX - rect.left,
        offsetY: event.clientY - rect.top,
      }))
      event.dataTransfer.effectAllowed = "move"
    }
    this.dragover = event => {
      if (canvas()?.contains(event.target) && [...event.dataTransfer.types].includes("text/monty-metric")) {
        event.preventDefault()
        event.dataTransfer.dropEffect = "move"
      }
    }
    this.drop = event => {
      const element = canvas()
      if (!element?.contains(event.target)) return
      const grid = geometry(element)
      if (!grid) {
        event.preventDefault()
        return
      }
      let payload
      try {
        payload = JSON.parse(event.dataTransfer.getData("text/monty-metric"))
      } catch {
        return
      }
      if (!payload?.id || !Number.isFinite(payload.offsetX) || !Number.isFinite(payload.offsetY)) return
      event.preventDefault()
      const rect = element.getBoundingClientRect()
      const position = snapPosition({
        left: event.clientX - rect.left - payload.offsetX,
        top: event.clientY - rect.top - payload.offsetY,
      }, grid)
      this.pushEvent("move-metric", {id: payload.id, ...position})
    }
    this.keydown = event => {
      const card = event.target.closest("[data-metric-id][draggable=true]")
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
    document.addEventListener("dragstart", this.dragstart)
    document.addEventListener("dragover", this.dragover)
    document.addEventListener("drop", this.drop)
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
  destroyed() {
    document.removeEventListener("dragstart", this.dragstart)
    document.removeEventListener("dragover", this.dragover)
    document.removeEventListener("drop", this.drop)
    document.removeEventListener("keydown", this.keydown)
  }
}
