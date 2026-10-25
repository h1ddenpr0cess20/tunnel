#version 300 es
// Full-screen triangle for src/shaders/tunnel.frag (WebGL2 fallback).
void main() {
  vec2 p[3] = vec2[3](vec2(-1.0, -3.0), vec2(-1.0, 1.0), vec2(3.0, 1.0));
  gl_Position = vec4(p[gl_VertexID], 0.0, 1.0);
}
