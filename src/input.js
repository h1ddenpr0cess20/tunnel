// Keyboard, swipe and tap controls.
const GAME_KEYS = new Set(['Space', 'ArrowUp', 'ArrowDown', 'ArrowLeft', 'ArrowRight']);

// Keys sent by a TV remote or an app can arrive without a `code`, so fall
// back to what the key is.
const BY_KEY = {
  ArrowLeft: 'ArrowLeft', ArrowRight: 'ArrowRight', ArrowUp: 'ArrowUp', ArrowDown: 'ArrowDown',
  Enter: 'Enter', Escape: 'Escape', ' ': 'Space', a: 'KeyA', d: 'KeyD', w: 'KeyW', s: 'KeyS',
  m: 'KeyM', p: 'KeyP',
};
const BY_KEYCODE = { 13: 'Enter', 27: 'Escape', 32: 'Space', 37: 'ArrowLeft', 38: 'ArrowUp', 39: 'ArrowRight', 40: 'ArrowDown' };
const codeOf = e => e.code || BY_KEY[e.key?.length === 1 ? e.key.toLowerCase() : e.key] || BY_KEYCODE[e.keyCode] || '';

export function bindInput(h) {
  const tv = location.search.includes('tv') || /FireTVApp|AFT/.test(navigator.userAgent);
  const state = { touch: window.matchMedia?.('(pointer: coarse)').matches ?? false };

  window.addEventListener('keydown', e => {
    const k = codeOf(e);
    if (GAME_KEYS.has(k)) e.preventDefault();
    if (!tv && e.target?.closest?.('button') && (k === 'Space' || k === 'Enter')) return;
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
    const k = codeOf(e);
    if (k === 'ArrowDown' || k === 'KeyS') h.holdDown(false);
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
