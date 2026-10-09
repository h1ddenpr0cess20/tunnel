// Small synthesized sound effects. Audio starts on the first key press or tap.
(() => {
  let ac = null, noise = null;

  function init() {
    if (ac) { if (ac.state === 'suspended') ac.resume(); return; }
    const AC = window.AudioContext || window.webkitAudioContext;
    if (!AC) return;
    try { ac = new AC(); } catch (e) { return; }
    noise = ac.createBuffer(1, ac.sampleRate, ac.sampleRate);
    const d = noise.getChannelData(0);
    for (let i = 0; i < d.length; i++) d[i] = Math.random() * 2 - 1;
  }

  function env(node, gain, dur) {
    const g = ac.createGain(), t = ac.currentTime;
    g.gain.setValueAtTime(gain, t);
    g.gain.exponentialRampToValueAtTime(0.0001, t + dur);
    node.connect(g);
    g.connect(ac.destination);
  }

  function tone(f0, f1, dur, gain) {
    if (!ac) return;
    const o = ac.createOscillator(), t = ac.currentTime;
    o.frequency.setValueAtTime(f0, t);
    o.frequency.exponentialRampToValueAtTime(f1, t + dur);
    env(o, gain, dur);
    o.start(t);
    o.stop(t + dur);
  }

  function thud(freq, dur, gain) {
    if (!ac) return;
    const s = ac.createBufferSource(), f = ac.createBiquadFilter(), t = ac.currentTime;
    s.buffer = noise;
    f.type = 'lowpass';
    f.frequency.value = freq;
    s.connect(f);
    env(f, gain, dur);
    s.start(t);
    s.stop(t + dur);
  }

  window.Sound = {
    init,
    jump() { tone(160, 380, 0.2, 0.08); },
    land() { thud(220, 0.1, 0.35); },
    fall() { tone(300, 40, 1.1, 0.12); },
    crash() { thud(700, 0.45, 0.5); tone(90, 30, 0.4, 0.3); },
  };
})();
