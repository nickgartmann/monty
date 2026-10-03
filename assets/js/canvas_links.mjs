import {readGeometry} from "./canvas_geometry.mjs"

// Pan uses canonical grid positions rebased near the camera. Card dragging uses
// actual DOM rectangles so its connections follow the animated pointer preview.
export function updateCanvasLinks(canvas, paths, fromGrid = false) {
  paths ||= [...canvas.querySelectorAll(".dependency-path[data-source-id][data-target-id]")]
  if (paths.length === 0) return
  const grid = readGeometry(canvas.dataset)
  const canvasRect = fromGrid ? null : canvas.getBoundingClientRect()
  const cards = new Map([...canvas.querySelectorAll("[data-metric-id]")].map(card => {
    const rect = fromGrid ? {
      left: grid.padding + (Number(card.dataset.gridX) - grid.originX) * grid.step,
      top: grid.padding + (Number(card.dataset.gridY) - grid.originY) * grid.step,
      width: Number(canvas.dataset.cardWidth),
      height: Number(canvas.dataset.cardHeight),
    } : card.getBoundingClientRect()
    const left = rect.left - (canvasRect?.left || 0)
    const top = rect.top - (canvasRect?.top || 0)
    return [card.dataset.metricId, {
      left, top,
      right: left + (rect.width ?? rect.right - rect.left),
      middle: top + (rect.height ?? rect.bottom - rect.top) / 2,
    }]
  }))
  const bend = Number(canvas.dataset.linkBend)
  const curve = Number.isFinite(bend) ? bend : 50
  for (const path of paths) {
    if (!canvas.contains(path)) continue
    const source = cards.get(path.dataset.sourceId), target = cards.get(path.dataset.targetId)
    if (!source || !target) continue
    const sx = source.right, sy = source.middle, tx = target.left, ty = target.middle
    const d = `M ${sx} ${sy} C ${sx + curve} ${sy}, ${tx - curve} ${ty}, ${tx} ${ty}`
    if (path.getAttribute("d") !== d) path.setAttribute("d", d)
  }
}
