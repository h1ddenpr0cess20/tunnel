// The runner: drives the hallway's speed, spawns pits and low walls, handles
// jumping, collisions, the HUD and the title / game-over panels.
(() => {
  // The hallway's own defaults, from the original file's props.
  const props = {
    speed: 1.6,
    vanishingX: 50,
    vanishingY: 50,
    tilesPerSide: 33,
    groutWidth: 1.7,
    repeatEvery: 24,
    darkTile: '#752327',
    midTile: '#a43639',
    brightTile: '#df484d',
    grout: '#100101',
  };

  const hall = new Hallway(document.querySelector('canvas[data-dc-hallway="main"]'), props);
  hall._run();
  const overlay = new Overlay(document.getElementById('overlay'), hall);

  const AIR = 0.9;                 // seconds in the air per jump
  const GRAV = 8 / (AIR * AIR);    // jump peaks at height 1
  const V0 = 4 / AIR;
  const CLEAR = 0.45;              // height needed to clear a low wall
  const WALL_ROW = 24;             // wall top sits on this tile row
  const M_PER_RING = 0.5;

  const S = {
    mode: 'title', paused: false,
    start: 0, runT: 0, h: 0, vh: 0, overPitT: 0,
    obs: [], next: 0, id: 1,
    deathT: 0, kind: '', fade: 0, fadeTo: 0, overAt: 0,
  };

  const $ = id => document.getElementById(id);
  const ui = {
    hud: $('hud'), dist: $('dist'), light: $('light'),
    title: $('title'), over: $('over'),
    overHead: $('over-head'), overDist: $('over-dist'), overLight: $('over-light'),
  };

  const runSpeed = t => 5 + 6 * (1 - Math.exp(-t / 90));
  const meters = () => Math.max(0, (hall._phase - S.start) * M_PER_RING);
  const lightLeft = m => 1000 * Math.pow(0.5, m / 250);
  function fmtLight(L) {
    if (L >= 100) return L.toFixed(1);
    if (L >= 1) return L.toFixed(3);
    if (L < 1e-12) return L.toExponential(3);
    return L.toFixed(Math.min(14, 3 - Math.floor(Math.log10(L))));
  }

  function spawn() {
    const v = Math.max(props.speed, 5);
    const k0 = Math.round(S.next);
    let o;
    if (Math.random() < 0.6) {
      const len = Math.max(2, Math.min(Math.floor(v * AIR - 1.5), Math.round(v * AIR * (0.35 + 0.25 * Math.random()))));
      o = { type: 'pit', k0, k1: k0 + len };
    } else {
      o = { type: 'wall', k0, k1: k0 + 1 + (Math.random() < 0.5 ? 1 : 0), row: WALL_ROW };
    }
    o.id = S.id++;
    S.obs.push(o);
    S.next = o.k1 + v * (1.3 + Math.random() * 1.4);
  }

  function start() {
    Sound.init();
    S.mode = 'run';
    S.start = hall._phase;
    S.runT = 0; S.h = 0; S.vh = 0; S.overPitT = 0;
    S.obs = [];
    S.next = overlay.playerRing() + 60;
    S.fadeTo = 0;
    ui.title.hidden = true; ui.over.hidden = true; ui.hud.hidden = false;
  }

  function die(kind) {
    S.mode = 'dying'; S.kind = kind; S.deathT = 0;
    if (kind === 'fall') { S.fadeTo = 1; Sound.fall(); }
    else { props.speed = 0; S.fadeTo = 0.85; Sound.crash(); }
  }

  function showOver() {
    S.mode = 'over'; S.overAt = performance.now();
    const m = meters();
    ui.overHead.textContent = S.kind === 'fall' ? 'You fell' : 'You tripped';
    ui.overDist.textContent = `You ran ${Math.floor(m)} m.`;
    ui.overLight.textContent = `The light is still ${fmtLight(lightLeft(m))} m away.`;
    ui.hud.hidden = true; ui.over.hidden = false;
  }

  function jump() {
    if (S.mode !== 'run' || S.paused) return;
    if (S.h <= 0 && S.vh <= 0) { S.vh = V0; S.overPitT = 0; Sound.jump(); }
  }

  function press() {
    if (S.mode === 'title') start();
    else if (S.mode === 'over') { if (performance.now() - S.overAt > 450) start(); }
    else jump();
  }

  function overPit(kp) {
    return S.obs.some(o => o.type === 'pit' && kp >= o.k0 + 0.3 && kp < o.k1 - 0.3);
  }

  function update(dt) {
    S.fade += (S.fadeTo - S.fade) * (1 - Math.exp(-dt * 3));
    if (S.paused) return;

    if (S.mode === 'title') { props.speed = 1.6; return; }
    if (S.mode === 'over') { props.speed = 0; return; }
    if (S.mode === 'dying') {
      S.deathT += dt;
      if (S.kind === 'fall') props.speed *= Math.exp(-dt * 4);
      if (S.deathT > 1) showOver();
      return;
    }

    S.runT += dt;
    props.speed = runSpeed(S.runT);
    const kp = overlay.playerRing();

    if (S.h > 0 || S.vh > 0) {
      S.vh -= GRAV * dt;
      S.h += S.vh * dt;
      if (S.h <= 0) { S.h = 0; S.vh = 0; Sound.land(); }
    }

    if (S.h <= 0 && overPit(kp)) {
      S.overPitT += dt;
      if (S.overPitT > 0.08) return die('fall');
    } else {
      S.overPitT = 0;
    }

    for (const o of S.obs) {
      if (o.type === 'wall' && kp >= o.k0 - 0.3 && kp < o.k1 + 0.3 && S.h < CLEAR) return die('wall');
    }

    while (S.next < kp + 70) spawn();
    S.obs = S.obs.filter(o => o.k1 > kp - 2);

    const m = meters();
    ui.dist.textContent = `${Math.floor(m)} m`;
    ui.light.textContent = `${fmtLight(lightLeft(m))} m`;
  }

  let last = null;
  function frame(now) {
    requestAnimationFrame(frame);
    const dt = last == null ? 0 : Math.min(0.1, Math.max(0, (now - last) / 1000));
    last = now;
    update(dt);
    overlay.draw(S.mode === 'title' ? [] : S.obs, S.fade, now / 1000);
  }
  requestAnimationFrame(frame);

  window.addEventListener('keydown', e => {
    if (['Space', 'ArrowUp', 'KeyW', 'Enter'].includes(e.code)) {
      e.preventDefault();
      if (!e.repeat) press();
    }
  });
  window.addEventListener('pointerdown', press);
  document.addEventListener('visibilitychange', () => {
    if (S.mode !== 'run') return;
    S.paused = document.hidden;
    props.speed = S.paused ? 0 : runSpeed(S.runT);
  });

  // Hook for automated checks.
  window.__runner = { S, hall, overlay, start, jump };
})();
