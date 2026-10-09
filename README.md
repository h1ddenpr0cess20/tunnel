# Neverending Hallway

A first-person runner through the Neverending Hallway. Run for the light at the
end of the tunnel. You never reach it.

The hallway is ray traced in a WebGPU fragment shader (`src/shaders/hallway.wgsl`)
using the original asset's tile hash, colours, 33-column corner warp, 24-ring
repeat and 1.7px grout.

## Run

```sh
npm install
npm run dev      # http://localhost:5173
npm run build    # static build in dist/
```

Needs a browser with WebGPU (current Chrome, Edge or Safari).

## Controls

- Space / ↑ / swipe up: jump pits and low walls
- ↓ / S / swipe down: slide under beams
- ← → / A D / swipe sideways: change lanes around pillars
- P: pause, M: sound

## Layout

- `src/shaders/hallway.wgsl`: tunnel, pits, obstacles and the light
- `src/gpu.js`: WebGPU device, pipeline and uniform buffer
- `src/game.js`: running, jumping, sliding, spawning and collisions
- `src/main.js`: frame loop and uniform packing
- `src/input.js`, `src/hud.js`, `src/sound.js`: controls, HUD, audio
- `src/constants.js`: shared geometry and movement numbers
