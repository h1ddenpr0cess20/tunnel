// Plays one round with a simple bot (it deliberately slips now and then so rounds end)
// and dumps frames as PPM files. Usage: node record_round.mjs <outdir> [seed] [maxFrames]
import { NES, Controller as C } from 'jsnes'; import fs from 'fs'; import path from 'path'; import { fileURLToPath } from 'url';
const here = path.dirname(fileURLToPath(import.meta.url));
const out = process.argv[2], seed = +process.argv[3] || 1, maxF = +process.argv[4] || 1500;
fs.mkdirSync(out, { recursive: true });
let fb; const nes = new NES({ onFrame(b) { fb = b.slice(); }, onAudioSample() {} });
nes.loadROM(fs.readFileSync(path.join(here, '../tunnel.nes'), 'binary')); nes.ppu.clipToTvSize = false;
const L = {}; for (const l of fs.readFileSync(path.join(here, '../tunnel.lbl'), 'utf8').split('\n')) { const m = l.match(/al ([0-9A-F]+) \.(\w+)/); if (m) L[m[2]] = parseInt(m[1], 16); }
const M = nes.cpu.mem, g = n => M[L[n]];
let rs = seed * 7919; const rnd = () => (rs = (rs * 1103515245 + 12345) & 0x7fffffff) / 0x7fffffff;
const ppm = () => { const b = Buffer.alloc(256*240*3); for (let i=0;i<256*240;i++){const c=fb[i];b[i*3]=c&255;b[i*3+1]=(c>>8)&255;b[i*3+2]=(c>>16)&255;} return Buffer.concat([Buffer.from('P6\n256 240\n255\n'), b]); };
for (let i = 0; i < 30 + seed; i++) nes.frame();
nes.buttonDown(1, C.BUTTON_START); nes.frame(); nes.buttonUp(1, C.BUTTON_START);
let n = 0, deadAt = -1;
for (let f = 0; f < maxF; f++) {
  for (const b of [C.BUTTON_A, C.BUTTON_DOWN, C.BUTTON_LEFT, C.BUTTON_RIGHT]) nes.buttonUp(1, b);
  const st = g('state');
  if (st === 1) {
    const spd = g('spd'), lane = g('lane');
    const obs = [0,1,2].map(i => ({ t: M[L.o_type+i], l: M[L.o_lane+i], d: M[L.o_dh+i], c: M[L.o_chk+i] })).filter(o => o.t && !o.c);
    for (const o of obs) {
      if (o.l !== lane) continue;
      const slip = f > 300 && rnd() < 0.012;           // an occasional mistake, after a warm-up
      if (slip) continue;
      if ((o.t === 1 || o.t === 3) && Math.abs(o.d - (Math.floor(14*spd/256)+7)) <= 1 && !g('jt')) nes.buttonDown(1, C.BUTTON_A);
      if (o.t === 4 && Math.abs(o.d - (Math.floor(8*spd/256)+7)) <= 1 && !g('slt')) nes.buttonDown(1, C.BUTTON_DOWN);
      if (o.t === 2 && o.d < 40) {
        const busy = new Set(obs.filter(x => x.d < 60).map(x => x.l));
        const free = [0,1,2].filter(x => !busy.has(x)).sort((a,b)=>Math.abs(a-lane)-Math.abs(b-lane))[0];
        if (free !== undefined) nes.buttonDown(1, free < lane ? C.BUTTON_LEFT : C.BUTTON_RIGHT);
      }
    }
  }
  nes.frame();
  if (f % 3 === 0) fs.writeFileSync(path.join(out, `f${String(n++).padStart(5,'0')}.ppm`), ppm());
  if (g('state') === 3 && deadAt < 0) deadAt = f;
  if (deadAt >= 0 && f > deadAt + 90) break;
}
console.log(`frames ${n}, died ${deadAt >= 0}, dist ${Array.from(M.slice(L.digits, L.digits+6)).reverse().join('')}`);
