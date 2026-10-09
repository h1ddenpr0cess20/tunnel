// Synthesized sound: a low drone for the tunnel and short effects.
// Audio starts on the first key press or tap.
const store = {
  get(k) { try { return localStorage.getItem(k); } catch { return null; } },
  set(k, v) { try { localStorage.setItem(k, v); } catch { /* storage unavailable */ } },
};

export const Sound = {
  ac: null, out: null, noise: null, droneF: null,
  muted: store.get('nt-muted') === '1',

  init() {
    if (this.ac) { if (this.ac.state === 'suspended') this.ac.resume(); return; }
    const AC = window.AudioContext || window.webkitAudioContext;
    if (!AC) return;
    try { this.ac = new AC(); } catch { return; }
    const ac = this.ac;
    this.out = ac.createGain();
    this.out.gain.value = this.muted ? 0 : 0.6;
    this.out.connect(ac.destination);
    const buf = ac.createBuffer(1, ac.sampleRate, ac.sampleRate);
    const d = buf.getChannelData(0);
    for (let i = 0; i < d.length; i++) d[i] = Math.random() * 2 - 1;
    this.noise = buf;
    const lp = ac.createBiquadFilter();
    lp.type = 'lowpass'; lp.frequency.value = 160; lp.Q.value = 2;
    const g = ac.createGain(); g.gain.value = 0.045;
    for (const f of [55, 55.7, 82.4]) {
      const o = ac.createOscillator(); o.type = 'sawtooth'; o.frequency.value = f; o.connect(lp); o.start();
    }
    lp.connect(g); g.connect(this.out);
    this.droneF = lp;
  },

  setMuted(m) {
    this.muted = m;
    store.set('nt-muted', m ? '1' : '0');
    if (this.out) this.out.gain.setTargetAtTime(m ? 0 : 0.6, this.ac.currentTime, 0.05);
  },

  suspend(p) { if (this.ac) (p ? this.ac.suspend() : this.ac.resume()); },

  ok() { return this.ac && !this.muted && this.ac.state === 'running'; },

  burst(dur, freq, gain, type = 'lowpass', q = 0.8, f1 = freq) {
    if (!this.ok()) return;
    const ac = this.ac, t = ac.currentTime;
    const src = ac.createBufferSource(); src.buffer = this.noise;
    const f = ac.createBiquadFilter(); f.type = type; f.Q.value = q;
    f.frequency.setValueAtTime(freq, t); f.frequency.exponentialRampToValueAtTime(f1, t + dur);
    const g = ac.createGain();
    g.gain.setValueAtTime(gain, t); g.gain.exponentialRampToValueAtTime(0.0001, t + dur);
    src.connect(f); f.connect(g); g.connect(this.out);
    src.start(t, Math.random() * 0.5); src.stop(t + dur + 0.02);
  },

  tone(f0, f1, dur, gain, type = 'sine') {
    if (!this.ok()) return;
    const ac = this.ac, t = ac.currentTime;
    const o = ac.createOscillator(); o.type = type;
    o.frequency.setValueAtTime(f0, t); o.frequency.exponentialRampToValueAtTime(f1, t + dur);
    const g = ac.createGain();
    g.gain.setValueAtTime(gain, t); g.gain.exponentialRampToValueAtTime(0.0001, t + dur);
    o.connect(g); g.connect(this.out);
    o.start(t); o.stop(t + dur + 0.02);
  },

  step() { this.burst(0.06, 260 + Math.random() * 90, 0.28); },
  jump() { this.tone(150, 360, 0.2, 0.07, 'triangle'); this.burst(0.18, 900, 0.05, 'bandpass', 1, 2400); },
  land() { this.burst(0.1, 200, 0.4); },
  slide() { this.burst(0.45, 2200, 0.07, 'bandpass', 1.2, 500); },
  lane() { this.burst(0.08, 1400, 0.035, 'bandpass', 1, 2600); },
  fall() { this.tone(300, 38, 1.2, 0.12); this.burst(1.0, 1600, 0.05, 'bandpass', 0.8, 200); },
  crash() { this.burst(0.5, 900, 0.5, 'lowpass', 0.8, 120); this.tone(90, 30, 0.45, 0.35); },
  drone(speed) {
    if (this.droneF) this.droneF.frequency.setTargetAtTime(140 + speed * 25, this.ac.currentTime, 0.4);
  },
};

export { store };
