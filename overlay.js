// Draws the light, pits and low walls on a second canvas over the hallway.
// Geometry matches Hallway._paint exactly (same base, ring ratio, tile grid and
// grout), so obstacles sit on the hallway's own tiles. The hallway is untouched.
(() => {
  const BASE = 600;

  function ringD(hall, k, N) {
    const f = 1 - 1.848 / N;
    return BASE * Math.pow(f, k - hall._phase);
  }

  class Overlay {
    constructor(canvas, hall) {
      this.cv = canvas;
      this.hall = hall;
      this.ctx = canvas.getContext('2d');
    }

    // Same sizing as the hallway canvas.
    _size() {
      const cv = this.cv;
      const W = cv.clientWidth, H = cv.clientHeight;
      if (!W || !H) return null;
      const dpr = Math.min(2, window.devicePixelRatio || 1);
      const bw = Math.round(W * dpr), bh = Math.round(H * dpr);
      if (cv.width !== bw || cv.height !== bh) { cv.width = bw; cv.height = bh; }
      this.ctx.setTransform(dpr, 0, 0, dpr, 0, 0);
      return { W, H };
    }

    _view() {
      const P = this.hall.props, h = this.hall;
      const s = this._size();
      if (!s || !h._g) return null;
      const N = h._g.length - 1;
      const gw = h._num(P.groutWidth, 1.7, 0, 12);
      return {
        W: s.W, H: s.H, N, g: h._g, gw, half: gw / 2,
        vx: s.W * h._num(P.vanishingX, 50, 0, 100) / 100,
        vy: s.H * h._num(P.vanishingY, 50, 0, 100) / 100,
        minD: Math.max(1, N * Math.max(gw, 0.6) * 0.45),
        fills: [P.darkTile || '#752327', P.midTile || '#a43639', P.brightTile || '#df484d'],
        grout: P.grout || '#100101',
      };
    }

    // Ring index (in the hallway's own ring numbering) where the floor leaves
    // the bottom of the screen; the runner's feet are just past it.
    playerRing() {
      const v = this._view();
      if (!v) return this.hall._phase + 3;
      const f = 1 - 1.848 / v.N;
      return this.hall._phase + Math.log((v.H - v.vy) * 1.12 / BASE) / Math.log(f);
    }

    draw(obstacles, fade, t) {
      const v = this._view();
      const ctx = this.ctx;
      if (!v) return;
      ctx.clearRect(0, 0, v.W, v.H);
      this._light(v, t);
      const list = obstacles.slice().sort((a, b) => b.k0 - a.k0);
      for (const o of list) (o.type === 'pit' ? this._pit : this._wall).call(this, v, o);
      if (fade > 0.002) {
        ctx.fillStyle = `rgba(16, 1, 1, ${Math.min(1, fade)})`;
        ctx.fillRect(0, 0, v.W, v.H);
      }
    }

    // The light at the end: fills the hallway's empty centre and blooms a little.
    _light(v, t) {
      const ctx = this.ctx, s = v.minD;
      const pulse = 0.92 + 0.08 * Math.sin(t * 1.3);
      const g = ctx.createRadialGradient(v.vx, v.vy, 0, v.vx, v.vy, s * 4);
      g.addColorStop(0, `rgba(255, 250, 240, ${pulse})`);
      g.addColorStop(0.25, `rgba(255, 236, 220, ${0.7 * pulse})`);
      g.addColorStop(1, 'rgba(255, 220, 200, 0)');
      ctx.fillStyle = '#fffaf2';
      ctx.fillRect(v.vx - s, v.vy - s, s * 2, s * 2);
      ctx.globalCompositeOperation = 'lighter';
      ctx.fillStyle = g;
      ctx.fillRect(v.vx - s * 4, v.vy - s * 4, s * 8, s * 8);
      ctx.globalCompositeOperation = 'source-over';
    }

    // A pit removes the floor tiles for its rings, leaving the grout colour.
    _pit(v, o) {
      const ctx = this.ctx;
      ctx.fillStyle = v.grout;
      ctx.beginPath();
      for (let k = o.k0; k < o.k1; k++) {
        const d0 = ringD(this.hall, k, v.N);
        if (d0 < v.minD) break;
        const d1 = d0 * (1 - 1.848 / v.N);
        if (v.vy + d1 > v.H) continue;
        ctx.rect(v.vx - d1, v.vy + d1, d1 * 2, d0 - d1);
      }
      ctx.fill();
    }

    // A knee-high wall built from the hallway's tiles: top face, then front face.
    _wall(v, o) {
      const ctx = this.ctx, g = v.g, N = v.N, R = o.row;
      const top = g[R];
      const lists = [[], [], []];
      const backs = [];
      const add = (x0, y0, x1, y1, r) => {
        if (x1 < 0 || y1 < 0 || x0 > v.W || y0 > v.H) return;
        const w = x1 - x0 - v.gw, h = y1 - y0 - v.gw;
        if (w <= 0.05 || h <= 0.05) return;
        lists[r < 0.516 ? 0 : (r < 0.875 ? 1 : 2)].push(x0 + v.half, y0 + v.half, w, h);
      };
      const dF = ringD(this.hall, o.k0, N);
      if (dF < v.minD) return;
      for (let k = o.k1 - 1; k >= o.k0; k--) {
        const d0 = ringD(this.hall, k, N), d1 = d0 * (1 - 1.848 / N);
        backs.push(v.vx - d1, v.vy + top * d1, d1 * 2, (d0 - d1) * top);
        for (let j = 0; j < N; j++) {
          add(v.vx + d1 * g[j], v.vy + top * d1, v.vx + d1 * g[j + 1], v.vy + top * d0, this.hall._rand(o.id, 4 + k - o.k0, j));
        }
      }
      backs.push(v.vx - dF, v.vy + top * dF, dF * 2, dF * (1 - top));
      for (let r = R; r < N; r++) {
        for (let j = 0; j < N; j++) {
          add(v.vx + dF * g[j], v.vy + dF * g[r], v.vx + dF * g[j + 1], v.vy + dF * g[r + 1], this.hall._rand(o.id, 1, r * N + j));
        }
      }
      ctx.fillStyle = v.grout;
      ctx.beginPath();
      for (let i = 0; i < backs.length; i += 4) ctx.rect(backs[i], backs[i + 1], backs[i + 2], backs[i + 3]);
      ctx.fill();
      for (let c = 0; c < 3; c++) {
        const L = lists[c];
        if (!L.length) continue;
        ctx.fillStyle = v.fills[c];
        ctx.beginPath();
        for (let i = 0; i < L.length; i += 4) ctx.rect(L[i], L[i + 1], L[i + 2], L[i + 3]);
        ctx.fill();
      }
    }
  }

  window.Overlay = Overlay;
})();
