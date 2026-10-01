// Coordinates sent to LiveView are indices on its dot grid, not card-sized cells.
// Geometry comes from server-rendered data attributes, including bounds.
export function readGeometry(dataset) {
  const keys = {step: "gridStep", padding: "gridPadding", maxX: "gridMaxX", maxY: "gridMaxY"}
  const geometry = {}

  for (const [key, attribute] of Object.entries(keys)) {
    const raw = dataset?.[attribute]
    if (typeof raw !== "string" || raw.trim() === "") return null
    const value = Number(raw)
    if (!Number.isSafeInteger(value) || value < 0) return null
    geometry[key] = value
  }

  return geometry.step > 0 ? geometry : null
}

export function clampPosition({x, y}, {maxX, maxY}) {
  return {
    x: Math.max(0, Math.min(maxX, x)),
    y: Math.max(0, Math.min(maxY, y)),
  }
}

export function snapPosition({left, top}, {step, padding, maxX, maxY}) {
  return clampPosition({
    x: Math.round((left - padding) / step),
    y: Math.round((top - padding) / step),
  }, {maxX, maxY})
}
