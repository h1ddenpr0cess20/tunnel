// WebGPU setup: one full-screen triangle running src/shaders/tunnel.wgsl.
import shaderCode from './shaders/tunnel.wgsl?raw';

// Matches struct Uniforms in the shader: 4 vec4 header + 8 pits + 16 + 16 boxes.
export const UNIFORM_FLOATS = (4 + 8 + 16 + 16) * 4;
export const OFF_PITS = 16;
export const OFF_BMIN = 48;
export const OFF_BMAX = 112;
export const MAX_PITS = 8;
export const MAX_BOXES = 16;

export async function createRenderer(canvas) {
  if (!navigator.gpu) throw new Error('This browser does not support WebGPU.');
  const adapter = await navigator.gpu.requestAdapter();
  if (!adapter) throw new Error('No WebGPU adapter is available on this device.');
  const device = await adapter.requestDevice();
  const context = canvas.getContext('webgpu');
  const format = navigator.gpu.getPreferredCanvasFormat();
  context.configure({ device, format, alphaMode: 'opaque' });

  const module = device.createShaderModule({ code: shaderCode });
  const info = await module.getCompilationInfo();
  const errors = info.messages.filter(m => m.type === 'error');
  if (errors.length) throw new Error(errors.map(m => `tunnel.wgsl:${m.lineNum}: ${m.message}`).join('\n'));

  const pipeline = device.createRenderPipeline({
    layout: 'auto',
    vertex: { module, entryPoint: 'vs' },
    fragment: { module, entryPoint: 'fs', targets: [{ format }] },
    primitive: { topology: 'triangle-list' },
  });
  const ubuf = device.createBuffer({
    size: UNIFORM_FLOATS * 4,
    usage: GPUBufferUsage.UNIFORM | GPUBufferUsage.COPY_DST,
  });
  const bindGroup = device.createBindGroup({
    layout: pipeline.getBindGroupLayout(0),
    entries: [{ binding: 0, resource: { buffer: ubuf } }],
  });
  const data = new Float32Array(UNIFORM_FLOATS);

  return {
    data,
    resize() {
      // Lite (the TV default; `?full` turns it off) draws at a set lower height and lets the browser scale it up.
      let dpr = Math.min(2, window.devicePixelRatio || 1);
      const q = new URLSearchParams(location.search);
      const tv = q.has('tv') || /FireTVApp|AFT/.test(navigator.userAgent);
      if (q.has('lite') || (tv && !q.has('full'))) dpr = Math.min(dpr, (Number(q.get('height')) || 540) / Math.max(1, canvas.clientHeight));
      const w = Math.max(1, Math.round(canvas.clientWidth * dpr));
      const h = Math.max(1, Math.round(canvas.clientHeight * dpr));
      if (canvas.width !== w || canvas.height !== h) { canvas.width = w; canvas.height = h; }
      return { w, h, dpr };
    },
    draw() {
      device.queue.writeBuffer(ubuf, 0, data);
      const enc = device.createCommandEncoder();
      const pass = enc.beginRenderPass({
        colorAttachments: [{
          view: context.getCurrentTexture().createView(),
          loadOp: 'clear',
          storeOp: 'store',
          clearValue: { r: 16 / 255, g: 1 / 255, b: 1 / 255, a: 1 },
        }],
      });
      pass.setPipeline(pipeline);
      pass.setBindGroup(0, bindGroup);
      pass.draw(3);
      pass.end();
      device.queue.submit([enc.finish()]);
    },
  };
}
