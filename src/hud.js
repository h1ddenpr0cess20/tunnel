// HUD, whispers and the title / game-over / pause panels.
import { lightLeft } from './game.js';

const $ = id => document.getElementById(id);

export function fmtLight(L) {
  if (L >= 100) return L.toFixed(1);
  if (L >= 1) return L.toFixed(3);
  if (L < 1e-12) return L.toExponential(3);
  return L.toFixed(Math.min(14, 3 - Math.floor(Math.log10(L))));
}
const fmtM = m => Math.floor(m).toLocaleString('en-US');

const MILESTONES = [
  [60, 'keep going'], [160, "it's getting brighter"], [320, 'almost there'],
  [520, 'just a little further'], [800, 'you can almost touch it'],
  [1150, 'it was right there a second ago'], [1600, 'closer than ever'],
  [2200, 'nearly'], [3000, 'any moment now'], [4000, 'keep going'],
];
const HINTS = {
  pit: ['jump', 'swipe up'], pillar: ['change lanes', 'swipe sideways'],
  wall: ['jump', 'swipe up'], beam: ['slide', 'swipe down'],
};
const DEATH = { fall: 'you fell', wall: 'you tripped', beam: 'you hit your head', pillar: 'you ran into a pillar' };

export function createHud(store) {
  const el = {
    hud: $('hud'), dist: $('dist'), light: $('light'), whisper: $('whisper'),
    title: $('title'), bestTitle: $('best-title'),
    over: $('over'), overHead: $('over-head'), overDist: $('over-dist'), overLight: $('over-light'), overBest: $('over-best'),
    paused: $('paused'), pauseBtn: $('pause'), snd: $('snd'), error: $('error'), errorMsg: $('error-msg'),
  };
  let best = Number(store.get('nh-best')) || 0;
  let milestone = 0;
  let timer = 0;
  let last = '';
  const hinted = {};

  function whisper(text, ms = 2600) {
    el.whisper.textContent = text;
    el.whisper.classList.add('on');
    clearTimeout(timer);
    timer = setTimeout(() => el.whisper.classList.remove('on'), ms);
  }

  if (best) {
    el.bestTitle.hidden = false;
    el.bestTitle.textContent = `Your best: ${fmtM(best)} m. The light was ${fmtLight(lightLeft(best))} m away.`;
  }

  return {
    start() {
      milestone = 0; last = '';
      el.title.hidden = true; el.over.hidden = true; el.paused.hidden = true;
      el.hud.hidden = false; el.pauseBtn.hidden = false; el.pauseBtn.textContent = 'Pause';
    },
    progress(m) {
      const t = `${fmtM(m)} m|${fmtLight(lightLeft(m))} m`;
      if (t !== last) {
        last = t;
        const [d, l] = t.split('|');
        el.dist.textContent = d;
        el.light.textContent = l;
      }
      const ms = MILESTONES[milestone];
      if (ms && m >= ms[0]) { milestone++; whisper(ms[1]); }
    },
    approach(type, touch) {
      if (hinted[type]) return;
      hinted[type] = true;
      whisper(HINTS[type][touch ? 1 : 0], 1800);
    },
    die() { el.pauseBtn.hidden = true; },
    over(kind, m) {
      const isBest = m > best;
      if (isBest) { best = m; store.set('nh-best', String(Math.floor(m))); }
      el.overHead.textContent = DEATH[kind] || 'you stopped';
      el.overDist.textContent = `${fmtM(m)} m`;
      el.overLight.textContent = `The light is still ${fmtLight(lightLeft(m))} m away.`;
      el.overBest.textContent = isBest && m > 0 ? 'Your farthest run yet.' : `Your best: ${fmtM(best)} m`;
      el.hud.hidden = true; el.over.hidden = false;
    },
    pause(p) {
      el.paused.hidden = !p;
      el.pauseBtn.textContent = p ? 'Resume' : 'Pause';
    },
    sound(muted) { el.snd.textContent = muted ? 'Sound off' : 'Sound on'; },
    error(msg) {
      el.title.hidden = true;
      el.error.hidden = false;
      el.errorMsg.textContent = msg;
    },
    buttons: { pause: el.pauseBtn, sound: el.snd },
  };
}
