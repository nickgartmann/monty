// Pointer Events may report primary-button release in a move or capture-loss
// event before pointerup. Other held buttons do not keep a primary drag alive.
export function primaryButtonReleased({buttons}) {
  return Number.isInteger(buttons) && buttons >= 0 && (buttons & 1) === 0
}
