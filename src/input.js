// Keyboard, swipe and tap controls.
const GAME_KEYS = new Set(['Space', 'ArrowUp', 'ArrowDown', 'ArrowLeft', 'ArrowRight']);

export function bindInput(h) {
  const state = { touch: window.matchMedia?.('(pointer: coarse)').matches ?? false };

  window.addEventListener('keydown', e => {
    const k = e.code;
    if (GAME_KEYS.has(k)) e.preventDefault();
    if (e.target?.closest?.('button') && (k === 'Space' || k === 'Enter')) return;
    if (e.repeat) {
      if (k === 'ArrowDown' || k === 'KeyS') h.holdDown(true);
      return;
    }
    switch (k) {
      case 'KeyM': h.mute(); break;
      case 'KeyP': case 'Escape': h.pause(); break;
      case 'Space': case 'Enter': case 'ArrowUp': case 'KeyW': h.primary(); break;
      case 'ArrowDown': case 'KeyS': h.holdDown(true); h.slide(); break;
      case 'ArrowLeft': case 'KeyA': h.lane(-1); break;
      case 'ArrowRight': case 'KeyD': h.lane(1); break;
    }
  });
  window.addEventListener('keyup', e => {
    if (e.code === 'ArrowDown' || e.code === 'KeyS') h.holdDown(false);
  });

  let ptr = null;
  window.addEventListener('pointerdown', e => {
    if (e.target.closest('button')) return;
    if (e.pointerType === 'touch') state.touch = true;
    ptr = { id: e.pointerId, x: e.clientX, y: e.clientY, done: false };
  });
  window.addEventListener('pointermove', e => {
    if (!ptr || ptr.id !== e.pointerId || ptr.done) return;
    const dx = e.clientX - ptr.x, dy = e.clientY - ptr.y;
    if (Math.hypot(dx, dy) < 26) return;
    ptr.done = true;
    if (Math.abs(dx) > Math.abs(dy)) h.lane(dx > 0 ? 1 : -1);
    else if (dy < 0) h.primary();
    else h.slide();
  });
  window.addEventListener('pointerup', e => {
    if (!ptr || ptr.id !== e.pointerId) return;
    if (!ptr.done) h.primary();
    ptr = null;
  });
  window.addEventListener('pointercancel', () => { ptr = null; });

  return state;
}
