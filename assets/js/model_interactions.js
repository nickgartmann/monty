// LiveView owns all cards and results. This ignored event bridge only handles
// browser drag gestures and downloads; it never renders model content.
export const ModelInteractions = {
  mounted() {
    const canvas = () => document.getElementById(this.el.dataset.canvasId)
    this.dragstart = event => {
      const card = event.target.closest("[data-metric-id][draggable=true]")
      if (!card || !canvas()?.contains(card)) return
      event.dataTransfer.setData("text/monty-metric", card.dataset.metricId)
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
      const id = event.dataTransfer.getData("text/monty-metric")
      if (!id) return
      event.preventDefault()
      const rect = element.getBoundingClientRect()
      const x = Math.max(0, Math.min(11, Math.floor((event.clientX - rect.left - 32) / 280)))
      const y = Math.max(0, Math.min(99, Math.floor((event.clientY - rect.top - 32) / 224)))
      this.pushEvent("move-metric", {id, x, y})
    }
    document.addEventListener("dragstart", this.dragstart)
    document.addEventListener("dragover", this.dragover)
    document.addEventListener("drop", this.drop)
    this.handleEvent("download-model", ({name, content}) => {
      const url = URL.createObjectURL(new Blob([content], {type: "application/json"}))
      const link = document.createElement("a")
      link.href = url
      link.download = name
      link.click()
      setTimeout(() => URL.revokeObjectURL(url), 1000)
    })
  },
  destroyed() {
    document.removeEventListener("dragstart", this.dragstart)
    document.removeEventListener("dragover", this.dragover)
    document.removeEventListener("drop", this.drop)
  }
}
