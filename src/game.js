// Game state: running, jumping, sliding, lanes, obstacles and collisions.
// Positions are in tunnel half-widths; s is distance down the hallway.
import {
  RING, LIGHT_D, M_PER_UNIT, LANE_EDGES, LANE_X,
  AIR, GRAV, V0, DUCK, SLIDE_T, WALL_TOP, BEAM_BOTTOM,
} from './constants.js';

const clamp = (v, lo, hi) => Math.min(hi, Math.max(lo, v));
const snap = s => Math.round(s / RING) * RING;
const runSpeed = t => 5 + 6 * (1 - Math.exp(-t / 100));

export const lightLeft = m => 1000 * Math.pow(0.5, m / 250);

export function createGame(events) {
  const S = {
    mode: 'title', paused: false,
    s: 0, speed: 0.35, runT: 0, start: 0,
    lane: 1, x: 0, h: 0, vh: 0, slideT: 0, duck: 0, jumpBuf: 0, stepPhase: 0,
    obs: [], next: 0, id: 1, spawned: 0,
    deathT: 0, kind: '', fallPit: null, bounce: 0, shake: 0, flash: 0, fade: 0, fadeTo: 0,
    holdDown: false,
  };

  const meters = () => Math.max(0, (S.s - S.start) * M_PER_UNIT);

  function makeObs(type, s0, len, l0, l1) {
    const y = { pit: [-1, -1], wall: [-1, WALL_TOP], beam: [BEAM_BOTTOM, 1], pillar: [-1, 1] }[type];
    return {
      id: S.id++, type, s0: snap(s0), s1: snap(s0 + len),
      x0: LANE_EDGES[l0], x1: LANE_EDGES[l1], y0: y[0], y1: y[1],
    };
  }

  function spawn() {
    const diff = Math.min(1, S.runT / 150);
    const v = Math.max(S.speed, 5);
    const ri = n => Math.floor(Math.random() * n);
    let type = ['pit', 'pillar', 'wall', 'beam'][S.spawned];
    if (!type) {
      const r = Math.random();
      type = r < 0.34 ? 'pit' : r < 0.6 ? 'pillar' : r < 0.8 ? 'wall' : 'beam';
    }
    const late = S.spawned > 3;
    let o;
    if (type === 'pit') {
      let lanes = [0, 3];
      if (late && Math.random() < 0.35) lanes = [[0, 1], [2, 3], [1, 2], [0, 2], [1, 3]][ri(5)];
      const len = clamp(v * AIR * (0.3 + 0.25 * Math.random() + 0.12 * diff), 1, v * AIR - 0.7);
      o = makeObs('pit', S.next, len, lanes[0], lanes[1]);
    } else if (type === 'pillar') {
      let lanes;
      if (late && Math.random() < 0.35 + 0.2 * diff) lanes = Math.random() < 0.5 ? [0, 2] : [1, 3];
      else { const l = Math.random() < 0.5 ? S.lane : ri(3); lanes = [l, l + 1]; }
      o = makeObs('pillar', S.next, 0.25 + Math.random() * 0.25, lanes[0], lanes[1]);
    } else if (type === 'wall') {
      let lanes = [0, 3];
      if (late && Math.random() < 0.3) lanes = Math.random() < 0.5 ? [0, 2] : [1, 3];
      o = makeObs('wall', S.next, 0.08 + Math.random() * 0.08, lanes[0], lanes[1]);
    } else {
      o = makeObs('beam', S.next, 0.15 + Math.random() * 0.15, 0, 3);
    }
    S.obs.push(o);
    S.spawned++;
    S.next = o.s1 + Math.max(4, v * (1.0 - 0.3 * diff) + Math.random() * v * (0.9 - 0.4 * diff));
  }

  function overPit(s, x) {
    for (const o of S.obs) {
      if (o.type === 'pit' && s > o.s0 + 0.08 && s < o.s1 - 0.08 && x > o.x0 + 0.05 && x < o.x1 - 0.05) return o;
    }
    return null;
  }

  // ---- actions --------------------------------------------------------------
  function start() {
    S.mode = 'run'; S.paused = false;
    S.runT = 0; S.start = S.s;
    S.lane = 1; S.h = 0; S.vh = 0; S.slideT = 0; S.duck = 0; S.jumpBuf = 0;
    S.obs = []; S.spawned = 0; S.next = S.s + LIGHT_D + 2; S.fallPit = null;
    S.fadeTo = 0; S.shake = 0; S.flash = 0;
    S.speed = Math.max(S.speed, 2);
    events.start();
  }

  function doJump() {
    S.vh = V0; S.h = Math.max(S.h, 0); S.slideT = 0; S.jumpBuf = 0;
    events.jump();
  }
  function grounded() { return S.h <= 0.001 && S.h > -0.1 && S.vh <= 0.01; }
  function jump() {
    if (S.mode !== 'run' || S.paused) return;
    if (grounded()) doJump(); else S.jumpBuf = 0.14;
  }
  function slide() {
    if (S.mode !== 'run' || S.paused) return;
    if (S.h > 0.02) S.vh = Math.min(S.vh, -6);
    S.slideT = SLIDE_T; S.jumpBuf = 0;
    events.slide();
  }
  function lane(dir) {
    if (S.mode !== 'run' || S.paused) return;
    const n = clamp(S.lane + dir, 0, 2);
    if (n !== S.lane) { S.lane = n; events.lane(); }
  }
  function setPaused(p) {
    if (S.mode !== 'run') return;
    S.paused = p;
    events.pause(p);
  }

  function die(kind) {
    S.mode = 'dying'; S.kind = kind; S.deathT = 0;
    if (kind === 'fall') {
      S.fallPit = overPit(S.s, S.x);
      S.fadeTo = 1;
    } else {
      S.bounce = Math.min(3, S.speed * 0.4);
      S.speed = 0; S.shake = 1; S.flash = 1; S.fadeTo = 0.8;
    }
    events.die(kind);
  }

  // ---- simulation -----------------------------------------------------------
  function step(dt) {
    S.s += S.speed * dt;
    S.x += (LANE_X[S.lane] - S.x) * (1 - Math.exp(-16 * dt));
    if (S.slideT > 0) {
      S.slideT -= dt;
      if (S.holdDown && S.slideT < 0.1) S.slideT = 0.1;
    }
    const pit = overPit(S.s, S.x);
    const onGround = S.h <= 0 && S.vh <= 0 && !pit;
    if (!onGround) { S.vh -= GRAV * dt; S.h += S.vh * dt; }
    if (!pit && S.h <= 0) {
      if (S.h < -0.14) return die('fall');
      if (S.vh < -1.5) events.land();
      S.h = 0; S.vh = 0;
    }
    if (pit && S.h < -0.12) return die('fall');
    if (S.jumpBuf > 0) {
      S.jumpBuf -= dt;
      if (grounded()) doJump();
    }
    const duckTarget = S.slideT > 0 && S.h <= 0.02 ? 1 : 0;
    S.duck += (duckTarget - S.duck) * (1 - Math.exp(-20 * dt));

    if (S.h <= 0 && S.slideT <= 0) {
      const prev = S.stepPhase;
      S.stepPhase += dt * (1.8 + S.speed * 0.2);
      if (Math.floor(prev) !== Math.floor(S.stepPhase)) events.step();
    }

    const eye = S.h - S.duck * DUCK;
    for (const o of S.obs) {
      if (o.type === 'pit') continue;
      if (S.s + 0.15 <= o.s0 || S.s - 0.15 >= o.s1) continue;
      if (S.x + 0.15 <= o.x0 || S.x - 0.15 >= o.x1) continue;
      if (o.type === 'wall' && eye - 1 > o.y1 - 0.03) continue;
      if (o.type === 'beam' && eye + 0.12 < o.y0) continue;
      return die(o.type);
    }
  }

  function update(dt) {
    if (S.paused) return;
    S.flash = Math.max(0, S.flash - dt * 2.5);
    S.shake = Math.max(0, S.shake - dt * 2.2);
    const rate = S.fadeTo > S.fade ? (S.kind === 'fall' ? 3.2 : 2.4) : 4;
    S.fade += (S.fadeTo - S.fade) * (1 - Math.exp(-dt * rate));

    if (S.mode === 'title' || S.mode === 'over') {
      const target = S.mode === 'title' ? 0.35 : 0;
      S.speed += (target - S.speed) * (1 - Math.exp(-dt * 2));
      S.s += S.speed * dt;
      return;
    }

    if (S.mode === 'dying') {
      S.deathT += dt;
      if (S.kind === 'fall') {
        S.speed *= Math.exp(-dt * 5);
        S.s += S.speed * dt;
        if (S.fallPit) S.s = Math.min(S.s, S.fallPit.s1 - 0.3);
        S.vh -= GRAV * dt;
        S.h = Math.max(-0.95, S.h + S.vh * dt);
      } else {
        S.bounce *= Math.exp(-dt * 6);
        S.s -= S.bounce * dt;
        if (S.h > 0) { S.vh -= GRAV * dt; S.h = Math.max(0, S.h + S.vh * dt); }
      }
      if (S.deathT > 1.15) {
        S.mode = 'over';
        events.over(S.kind, meters());
      }
      return;
    }

    S.runT += dt;
    S.speed += (runSpeed(S.runT) - S.speed) * (1 - Math.exp(-dt * 1.5));
    let rem = dt;
    while (rem > 1e-6 && S.mode === 'run') {
      const h = Math.min(rem, 1 / 120);
      step(h);
      rem -= h;
    }
    if (S.mode !== 'run') return;
    while (S.next < S.s + LIGHT_D + 4) spawn();
    S.obs = S.obs.filter(o => o.s1 > S.s - 1);
    for (const o of S.obs) {
      if (!o.seen && o.s0 - S.s < LIGHT_D * 0.6) { o.seen = true; events.approach(o.type); }
    }
    events.progress(meters());
  }

  // Camera for the shader: eye position, roll and pitch.
  function camera(reduceMotion) {
    const running = S.mode === 'run' && S.h <= 0 && S.slideT <= 0 && !reduceMotion;
    const bobAmt = running ? Math.min(1, S.speed / 6) : 0;
    const ph = Math.PI * S.stepPhase;
    const sh = reduceMotion ? 0 : S.shake * S.shake * 0.05;
    let y = S.h - S.duck * DUCK + (0.02 * Math.abs(Math.sin(ph)) - 0.01) * bobAmt;
    let pitch = 0;
    if (S.mode !== 'run' && S.kind === 'fall' && S.fallPit) pitch = -Math.min(0.75, S.deathT * 1.4);
    y = Math.max(-0.95, Math.min(0.9, y));
    return {
      x: S.x + 0.008 * Math.sin(ph) * bobAmt + (Math.random() - 0.5) * sh,
      y: y + (Math.random() - 0.5) * sh,
      roll: reduceMotion ? 0 : (S.x - LANE_X[S.lane]) * 0.07,
      pitch,
    };
  }

  return { S, start, jump, slide, lane, setPaused, update, camera, meters, makeObs };
}
