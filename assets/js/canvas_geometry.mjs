// Coordinates sent to LiveView are indices on its dot grid, not card-sized cells.
// The world has no edges; only grid spacing and its origin come from the server.
export function readGeometry(dataset) {
  const keys = {step: "gridStep", padding: "gridPadding"}
  const geometry = {}

  for (const [key, attribute] of Object.entries(keys)) {
    const raw = dataset?.[attribute]
    if (typeof raw !== "string" || raw.trim() === "") return null
    const value = Number(raw)
    if (!Number.isSafeInteger(value) || value < 0) return null
    geometry[key] = value
  }

  for (const axis of ["X", "Y"]) {
    const value = Number(dataset[`gridOrigin${axis}`] ?? "0")
    if (!Number.isSafeInteger(value)) return null
    geometry[`origin${axis}`] = value
  }

  return geometry.step > 0 ? geometry : null
}

// Older canvases have no zoom attribute; malformed values must not produce NaN
// pointer coordinates or SVG paths.
export function readZoom(dataset) {
  const raw = dataset?.canvasZoom
  if (typeof raw !== "string" || raw.trim() === "") return 1
  const zoom = Number(raw)
  return Number.isFinite(zoom) && zoom > 0 ? zoom : 1
}

export function snapPosition({left, top}, {step, padding, originX = 0, originY = 0}) {
  return {
    x: originX + Math.round((left - padding) / step),
    y: originY + Math.round((top - padding) / step),
  }
}

export function centeredPosition({left, top}, {width, height}, geometry) {
  return snapPosition({left: left - width / 2, top: top - height / 2}, geometry)
}
