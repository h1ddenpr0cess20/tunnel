// The Neverending Hallway painter, copied unchanged from the original file.
// Only the wrapper changed: the original ran inside a DCLogic component, so the
// renderVals/componentDidMount hooks are replaced by this constructor.
// Everything from componentWillUnmount down is byte-for-byte the original.
class Hallway {
  constructor(canvas, props) {
    this._cv = canvas;
    this.props = props;
  }

  componentWillUnmount() { this._halt(); this._cv = null; }

  _run() {
    if (this._raf) return;
    if (typeof this._phase !== 'number') this._phase = 0;
    this._last = null;
    const tick = (now) => {
      this._raf = requestAnimationFrame(tick);
      if (!this._cv) this._cv = document.querySelector('canvas[data-dc-hallway="main"]');
      const dt = this._last == null ? 0 : Math.min(0.1, Math.max(0, (now - this._last) / 1000));
      this._last = now;
      if (this._cv && this._cv.isConnected) this._paint(dt);
    };
    this._raf = requestAnimationFrame(tick);
  }

  _halt() {
    if (this._raf) cancelAnimationFrame(this._raf);
    this._raf = 0;
  }

  _num(v, d, lo, hi) {
    let n = Number(v);
    if (v == null || v === '' || !isFinite(n)) n = d;
    return Math.min(hi, Math.max(lo, n));
  }

  _rand(ring, side, j) {
    let h = Math.imul(ring | 0, 0x9E3779B1) ^ Math.imul(side + 1, 0x85EBCA77) ^ Math.imul(j + 1, 0xC2B2AE3D) ^ 7;
    h = Math.imul(h ^ (h >>> 16), 0x7FEB352D);
    h = Math.imul(h ^ (h >>> 15), 0x846CA68B);
    h ^= h >>> 16;
    return (h >>> 0) / 4294967296;
  }

  _paint(dt) {
    const cv = this._cv, P = this.props;
    this._phase += this._num(P.speed, 1.6, -20, 20) * dt;

    const W = cv.clientWidth, H = cv.clientHeight;
    if (!W || !H) return;
    const dpr = Math.min(2, window.devicePixelRatio || 1);
    const bw = Math.round(W * dpr), bh = Math.round(H * dpr);
    if (cv.width !== bw || cv.height !== bh) { cv.width = bw; cv.height = bh; }
    const ctx = cv.getContext('2d');
    if (!ctx) return;
    ctx.setTransform(dpr, 0, 0, dpr, 0, 0);

    const fills = [P.darkTile || '#752327', P.midTile || '#a43639', P.brightTile || '#df484d'];
    ctx.fillStyle = P.grout || '#100101';
    ctx.fillRect(0, 0, W, H);

    // Geometry measured from the reference: 33 tiles per side, each ring 0.944x the one before,
    // side columns own the corners, tiles a touch wider near the corners than mid-wall.
    const N = Math.round(this._num(P.tilesPerSide, 33, 3, 99));
    const f = 1 - 1.848 / N;
    const lnf = Math.log(f);
    const gw = this._num(P.groutWidth, 1.7, 0, 12), half = gw / 2;
    const rep = Math.round(this._num(P.repeatEvery, 24, 0, 100000));
    const vx = W * this._num(P.vanishingX, 50, 0, 100) / 100;
    const vy = H * this._num(P.vanishingY, 50, 0, 100) / 100;
    const ext = Math.max(vx, W - vx, vy, H - vy, 1);

    if (!this._g || this._g.length !== N + 1) {
      this._g = new Float64Array(N + 1);
      for (let j = 0; j <= N; j++) {
        const u = -1 + 2 * j / N;
        this._g[j] = u - 0.0098 * Math.sin(Math.PI * u);
      }
    }
    const g = this._g;
    const base = 600, ph = this._phase;
    const minD = Math.max(1, N * Math.max(gw, 0.6) * 0.45);

    const lists = this._lists || (this._lists = [[], [], []]);
    lists[0].length = 0; lists[1].length = 0; lists[2].length = 0;
    const add = (x0, y0, x1, y1, r) => {
      if (x1 < 0 || y1 < 0 || x0 > W || y0 > H) return;
      const w = x1 - x0 - gw, hgt = y1 - y0 - gw;
      if (w <= 0.05 || hgt <= 0.05) return;
      lists[r < 0.516 ? 0 : (r < 0.875 ? 1 : 2)].push(x0 + half, y0 + half, w, hgt);
    };

    let k = Math.floor(ph + Math.log(ext / base) / lnf) - 1;
    for (let n = 0; n < 900; n++, k++) {
      const d0 = base * Math.pow(f, k - ph);
      if (d0 < minD) break;
      const d1 = d0 * f;
      const rk = rep > 0 ? ((k % rep) + rep) % rep : k;
      for (let j = 0; j < N; j++) {
        const ya = vy + d0 * g[j], yb = vy + d0 * g[j + 1];
        add(vx - d0, ya, vx - d1, yb, this._rand(rk, 0, j));
        add(vx + d1, ya, vx + d0, yb, this._rand(rk, 1, j));
        const xa = vx + d1 * g[j], xb = vx + d1 * g[j + 1];
        add(xa, vy - d0, xb, vy - d1, this._rand(rk, 2, j));
        add(xa, vy + d1, xb, vy + d0, this._rand(rk, 3, j));
      }
    }

    for (let c = 0; c < 3; c++) {
      const L = lists[c];
      if (!L.length) continue;
      ctx.fillStyle = fills[c];
      ctx.beginPath();
      for (let i = 0; i < L.length; i += 4) ctx.rect(L[i], L[i + 1], L[i + 2], L[i + 3]);
      ctx.fill();
    }
  }
}

window.Hallway = Hallway;
