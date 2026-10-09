// Shared numbers. Tile geometry matches the original tunnel and src/shaders/tunnel.wgsl.

export const N = 33;              // tiles per side
export const RING = 0.056;        // ring depth in tunnel half-widths
export const LIGHT_D = 29;        // the light always sits this far ahead
export const M_PER_UNIT = 1.25;   // one tunnel half-width in metres, for the HUD

// The original corner warp: tiles a touch wider near the corners.
export const G = Array.from({ length: N + 1 }, (_, j) => {
  const u = -1 + 2 * j / N;
  return u - 0.0098 * Math.sin(Math.PI * u);
});

// Three lanes, 11 tile columns each, edges on the floor's grout lines.
export const LANE_EDGES = [G[0], G[11], G[22], G[33]];
export const LANE_X = [0, 1, 2].map(i => (LANE_EDGES[i] + LANE_EDGES[i + 1]) / 2);

// Movement, in tunnel half-widths and seconds.
export const AIR = 0.75;
export const JUMP_H = 0.75;
export const GRAV = 8 * JUMP_H / (AIR * AIR);
export const V0 = 4 * JUMP_H / AIR;
export const DUCK = 0.55;
export const SLIDE_T = 0.8;

// Obstacle heights (y up, floor at -1, ceiling at +1).
export const WALL_TOP = -0.6;
export const BEAM_BOTTOM = -0.2;
