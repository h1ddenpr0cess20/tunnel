// WebGL2 fallback: the same full-screen pass as gpu.js, running the GLSL port in src/shaders.
import vertSource from './shaders/tunnel.vert?raw';
import fragSource from './shaders/tunnel.frag?raw';
import { UNIFORM_FLOATS } from './gpu.js';

function compile(gl, type, source, name) {
  const shader = gl.createShader(type);
  gl.shaderSource(shader, source);
  gl.compileShader(shader);
  if (!gl.getShaderParameter(shader, gl.COMPILE_STATUS)) {
    throw new Error(`${name}: ${gl.getShaderInfoLog(shader)}`);
  }
  return shader;
}

export function createGLRenderer(canvas) {
  const gl = canvas.getContext('webgl2', { antialias: false, alpha: false });
  if (!gl) throw new Error('This browser supports neither WebGPU nor WebGL 2.');

  const program = gl.createProgram();
  gl.attachShader(program, compile(gl, gl.VERTEX_SHADER, vertSource, 'tunnel.vert'));
  gl.attachShader(program, compile(gl, gl.FRAGMENT_SHADER, fragSource, 'tunnel.frag'));
  gl.linkProgram(program);
  if (!gl.getProgramParameter(program, gl.LINK_STATUS)) {
    throw new Error(`tunnel shader link: ${gl.getProgramInfoLog(program)}`);
  }
  gl.useProgram(program);
  const loc = gl.getUniformLocation(program, 'U');
  const vao = gl.createVertexArray();
  const data = new Float32Array(UNIFORM_FLOATS);

  return {
    data,
    resize() {
      const dpr = Math.min(2, window.devicePixelRatio || 1);
      const w = Math.max(1, Math.round(canvas.clientWidth * dpr));
      const h = Math.max(1, Math.round(canvas.clientHeight * dpr));
      if (canvas.width !== w || canvas.height !== h) { canvas.width = w; canvas.height = h; }
      return { w, h, dpr };
    },
    draw() {
      gl.viewport(0, 0, canvas.width, canvas.height);
      gl.bindVertexArray(vao);
      gl.uniform4fv(loc, data);
      gl.drawArrays(gl.TRIANGLES, 0, 3);
    },
  };
}
