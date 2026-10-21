import './styles.css';
import { RING, LIGHT_D } from './constants.js';
import { createRenderer, OFF_PITS, OFF_BMIN, OFF_BMAX, MAX_PITS, MAX_BOXES } from './gpu.js';
import { createGame } from './game.js';
import { createHud } from './hud.js';
import { bindInput } from './input.js';
import { Sound, store } from './sound.js';

const RING_WRAP = 24 * 128;  // keeps the eye's ring index small without breaking the 24-ring pattern
const reduceMotion = window.matchMedia?.('(prefers-reduced-motion: reduce)').matches ?? false;

const hud = createHud(store);
hud.sound(Sound.muted);
let overAt = 0;
let input = null;

const game = createGame({
  start: () => hud.start(),
  jump: () => Sound.jump(),
  slide: () => Sound.slide(),
  lane: () => Sound.lane(),
  land: () => Sound.land(),
  step: () => Sound.step(),
  pause: p => { hud.pause(p); Sound.suspend(p); },
  die: kind => { hud.die(); kind === 'fall' ? Sound.fall() : Sound.crash(); },
  over: (kind, m) => { overAt = performance.now(); hud.over(kind, m); },
  approach: type => hud.approach(type, input?.touch),
  progress: m => hud.progress(m),
});
const S = game.S;

function primary() {
  Sound.init();
  if (S.mode === 'title') game.start();
  else if (S.mode === 'over') { if (performance.now() - overAt > 450) game.start(); }
  else if (S.paused) game.setPaused(false);
  else game.jump();
}
function toggleMute() {
  Sound.init();
  Sound.setMuted(!Sound.muted);
  hud.sound(Sound.muted);
}

input = bindInput({
  primary,
  slide: () => game.slide(),
  lane: d => game.lane(d),
  holdDown: v => { S.holdDown = v; },
  pause: () => game.setPaused(!S.paused),
  mute: toggleMute,
});
hud.buttons.sound.addEventListener('click', toggleMute);
hud.buttons.pause.addEventListener('click', () => game.setPaused(!S.paused));
document.addEventListener('visibilitychange', () => { if (document.hidden) game.setPaused(true); });
window.addEventListener('blur', () => game.setPaused(true));

function pack(data, view, t) {
  const cam = game.camera(reduceMotion);
  data[0] = view.w; data[1] = view.h; data[2] = t;
  data[3] = Math.min(1.1, Math.max(0.55, view.h / view.w));
  data[4] = cam.x; data[5] = cam.y; data[6] = cam.roll; data[7] = cam.pitch;
  data[8] = (((S.s / RING) % RING_WRAP) + RING_WRAP) % RING_WRAP;
  data[11] = LIGHT_D;
  data[12] = 1.7 * view.dpr;
  data[13] = S.fade;
  data[14] = S.flash;
  data[15] = 1;

  const near = S.obs
    .filter(o => o.s1 > S.s - 1 && o.s0 < S.s + LIGHT_D + 1)
    .sort((a, b) => a.s0 - b.s0);
  let np = 0, nb = 0;
  for (const o of near) {
    if (o.type === 'pit') {
      if (np >= MAX_PITS) continue;
      data.set([o.s0 - S.s, o.s1 - S.s, o.x0, o.x1], OFF_PITS + np++ * 4);
    } else {
      if (nb >= MAX_BOXES) continue;
      data.set([o.x0, o.y0, o.s0 - S.s, o.id % 4096], OFF_BMIN + nb * 4);
      data.set([o.x1, o.y1, o.s1 - S.s, 0], OFF_BMAX + nb++ * 4);
    }
  }
  data[9] = np;
  data[10] = nb;
}

const params = new URLSearchParams(location.search);
const tv = params.has('tv') || /FireTVApp|AFT/.test(navigator.userAgent);
const lite = params.has('lite') || (tv && !params.has('full'));
if (tv) {
  // No space bar on a remote: Select starts.
  for (const el of document.querySelectorAll('.go .kb-only')) {
    el.textContent = el.textContent.replace(/press space/i, 'Press Select').replace('Press P ', 'Press Play/Pause ');
  }
}

async function boot() {
  const canvas = document.getElementById('tunnel');
  let renderer;
  try {
    renderer = await createRenderer(canvas);
  } catch (err) {
    hud.error(err.message);
    console.error(err);
    return;
  }
  let last = null, tick = 0;
  // In lite mode, draw every other frame: a steady 30 beats a stuttering 60.
  const interval = lite ? 1000 / (Number(params.get('fps')) || 30) : 0;
  let drawn = -1e9;
  function frame(now) {
    requestAnimationFrame(frame);
    if (now - drawn < interval - 5) return;
    drawn = now;
    const dt = last == null ? 0 : Math.min(0.05, Math.max(0, (now - last) / 1000));
    last = now;
    game.update(dt);
    pack(renderer.data, renderer.resize(), now / 1000);
    renderer.draw();
    if (Sound.ac && ++tick % 12 === 0) Sound.drone(S.mode === 'run' ? S.speed : 0.35);
  }
  requestAnimationFrame(frame);
}

boot();

// Hook for automated checks.
window.__tunnel = game;
