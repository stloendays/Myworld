// 暮色湖畔的全部声音：用代码合成，写进 assets/audio/*.wav（32 kHz、16 bit、单声道，原创，CC0）。
//   node devtools/audio/synth.mjs            全部重新生成
//   node devtools/audio/synth.mjs fire rain  只生成名字里含这些词的
// 随机数有固定种子，同样的代码每次生成一模一样的文件。循环音在尾部和开头之间做等功率交叉淡化，首尾无缝；
// 循环的起止点还写进 WAV 的 smpl 块（SoundBank 运行时也会按 sounds.json 设循环，两边一致）。
// 生成完打印每个文件的时长、峰值、RMS，写 assets/audio/_stats.json（自动检查读它确认没有削波、没有直流偏移）。

import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const SR = 32000;
const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..', '..');
const OUT = path.join(ROOT, 'assets', 'audio');
const ONLY = process.argv.slice(2);

// ---------------------------------------------------------------- 基础

function rng(seed) {
  let a = seed >>> 0;
  return () => {
    a = (a + 0x6D2B79F5) | 0;
    let t = Math.imul(a ^ (a >>> 15), 1 | a);
    t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t;
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  };
}
const N = (s) => Math.max(1, Math.round(s * SR));
const buf = (s) => new Float32Array(N(s));
const TAU = Math.PI * 2;
const clamp = (v, a, b) => Math.min(b, Math.max(a, v));
const lerp = (a, b, t) => a + (b - a) * t;
const midiHz = (m) => 440 * Math.pow(2, (m - 69) / 12);

function white(n, r) { const o = new Float32Array(n); for (let i = 0; i < n; i++) o[i] = r() * 2 - 1; return o; }
function pink(n, r) {
  let b0 = 0, b1 = 0, b2 = 0, b3 = 0, b4 = 0, b5 = 0, b6 = 0;
  const o = new Float32Array(n);
  for (let i = 0; i < n; i++) {
    const w = r() * 2 - 1;
    b0 = 0.99886 * b0 + w * 0.0555179; b1 = 0.99332 * b1 + w * 0.0750759; b2 = 0.969 * b2 + w * 0.153852;
    b3 = 0.8665 * b3 + w * 0.3104856; b4 = 0.55 * b4 + w * 0.5329522; b5 = -0.7616 * b5 - w * 0.016898;
    o[i] = (b0 + b1 + b2 + b3 + b4 + b5 + b6 + w * 0.5362) * 0.11; b6 = w * 0.115926;
  }
  return o;
}
function brown(n, r) { let l = 0; const o = new Float32Array(n); for (let i = 0; i < n; i++) { l = (l + 0.02 * (r() * 2 - 1)) / 1.02; o[i] = l * 3.5; } return o; }

// RBJ 双二阶滤波；freq 可以是常数或 (i) => Hz（每 32 个采样更新一次系数）
function biquad(x, type, freq, q = 0.707, gainDb = 0) {
  const y = new Float32Array(x.length);
  let x1 = 0, x2 = 0, y1 = 0, y2 = 0, b0 = 0, b1 = 0, b2 = 0, a1 = 0, a2 = 0;
  const upd = (f) => {
    f = clamp(f, 10, SR * 0.45);
    const w = TAU * f / SR, c = Math.cos(w), s = Math.sin(w), al = s / (2 * q);
    let B0, B1, B2, A0, A1, A2;
    if (type === 'lp') { B0 = (1 - c) / 2; B1 = 1 - c; B2 = (1 - c) / 2; A0 = 1 + al; A1 = -2 * c; A2 = 1 - al; }
    else if (type === 'hp') { B0 = (1 + c) / 2; B1 = -(1 + c); B2 = (1 + c) / 2; A0 = 1 + al; A1 = -2 * c; A2 = 1 - al; }
    else if (type === 'bp') { B0 = al; B1 = 0; B2 = -al; A0 = 1 + al; A1 = -2 * c; A2 = 1 - al; }
    else { const A = Math.pow(10, gainDb / 40); B0 = 1 + al * A; B1 = -2 * c; B2 = 1 - al * A; A0 = 1 + al / A; A1 = -2 * c; A2 = 1 - al / A; }
    b0 = B0 / A0; b1 = B1 / A0; b2 = B2 / A0; a1 = A1 / A0; a2 = A2 / A0;
  };
  const dyn = typeof freq === 'function';
  if (!dyn) upd(freq);
  for (let i = 0; i < x.length; i++) {
    if (dyn && (i & 31) === 0) upd(freq(i));
    const v = b0 * x[i] + b1 * x1 + b2 * x2 - a1 * y1 - a2 * y2;
    x2 = x1; x1 = x[i]; y2 = y1; y1 = v; y[i] = v;
  }
  return y;
}
const lp = (x, f, q) => biquad(x, 'lp', f, q);
const hp = (x, f, q) => biquad(x, 'hp', f, q);
const bp = (x, f, q) => biquad(x, 'bp', f, q);

function scale(x, g) { for (let i = 0; i < x.length; i++) x[i] *= g; return x; }
function mul(x, fn) { for (let i = 0; i < x.length; i++) x[i] *= fn(i / SR, i); return x; }
function add(dst, src, at = 0, g = 1) { const o = N(at) ; for (let i = 0; i < src.length && o + i < dst.length; i++) if (o + i >= 0) dst[o + i] += src[i] * g; return dst; }
function mix(...parts) { const n = Math.max(...parts.map(([x]) => x.length)); const o = new Float32Array(n); for (const [x, g] of parts) add(o, x, 0, g); return o; }
function rms(x) { let s = 0; for (const v of x) s += v * v; return Math.sqrt(s / x.length); }
function peak(x) { let m = 0; for (const v of x) m = Math.max(m, Math.abs(v)); return m; }
function toRms(x, db) { const r = rms(x); return r > 0 ? scale(x, Math.pow(10, db / 20) / r) : x; }
function toPeak(x, db) { const p = peak(x); return p > 0 ? scale(x, Math.pow(10, db / 20) / p) : x; }
function dcBlock(x) { let px = 0, py = 0; for (let i = 0; i < x.length; i++) { const v = x[i] - px + 0.9995 * py; px = x[i]; py = v; x[i] = v; } return x; }
// 柔和限幅：超过 0.9 的部分压进去，不会硬削波
function soft(x) { for (let i = 0; i < x.length; i++) { const v = x[i]; x[i] = Math.abs(v) < 0.9 ? v : Math.sign(v) * (0.9 + 0.09 * Math.tanh((Math.abs(v) - 0.9) / 0.09)); } return x; }

// 慢慢变化的 0..1 随机曲线（几条不同频率的正弦叠加，循环长度内自洽）
function drift(r, freqs = [0.05, 0.11, 0.023]) {
  const ph = freqs.map(() => r() * TAU);
  return (t) => { let s = 0; freqs.forEach((f, k) => { s += Math.sin(TAU * f * t + ph[k]); }); return 0.5 + 0.5 * s / freqs.length; };
}

// 指数衰减包络（attack 秒线性上升，decay 为时间常数）
const env = (attack, decay) => (t) => (t < attack ? t / Math.max(attack, 1e-4) : Math.exp(-(t - attack) / decay));
const hann = (len) => (t) => (t < 0 || t > len ? 0 : 0.5 - 0.5 * Math.cos(TAU * t / len));

// 按频率轨迹 f(t) 积分出的正弦（可加二次谐波）
function sweep(dur, fFn, ampFn, h2 = 0, h3 = 0) {
  const o = buf(dur); let ph = 0;
  for (let i = 0; i < o.length; i++) {
    const t = i / SR; ph += TAU * fFn(t) / SR;
    o[i] = (Math.sin(ph) + h2 * Math.sin(2 * ph) + h3 * Math.sin(3 * ph)) * ampFn(t);
  }
  return o;
}

// 一小段滤过的噪声爆发
function burst(r, dur, kind, f, q, a, d, src = 'white') {
  const n = N(dur);
  let x = src === 'pink' ? pink(n, r) : src === 'brown' ? brown(n, r) : white(n, r);
  x = biquad(x, kind, f, q);
  return mul(x, env(a, d));
}

// 简单的单声道混响（4 个梳状 + 2 个全通，Freeverb 的思路）
function reverb(x, wet = 0.3, room = 0.82, damp = 0.35, tail = 1.5) {
  const n = x.length + N(tail);
  const inp = new Float32Array(n); inp.set(x);
  const out = new Float32Array(n);
  const combs = [1116, 1188, 1277, 1356, 1422, 1491].map((d) => Math.round(d * SR / 44100));
  for (const d of combs) {
    const line = new Float32Array(d); let idx = 0, filt = 0;
    for (let i = 0; i < n; i++) {
      const y = line[idx]; filt = y * (1 - damp) + filt * damp;
      line[idx] = inp[i] + filt * room; idx = (idx + 1) % d; out[i] += y / combs.length;
    }
  }
  for (const d of [556, 441, 341].map((v) => Math.round(v * SR / 44100))) {
    const line = new Float32Array(d); let idx = 0;
    for (let i = 0; i < n; i++) { const b = line[idx]; const y = -out[i] + b; line[idx] = out[i] + b * 0.5; idx = (idx + 1) % d; out[i] = y; }
  }
  const o = new Float32Array(n);
  for (let i = 0; i < n; i++) o[i] = (i < x.length ? x[i] : 0) * (1 - wet * 0.5) + out[i] * wet;
  return o;
}

// 循环：生成 len + fade 秒，再把尾巴交叉淡化进开头，得到长 len 的无缝循环
function loopify(x, fade) {
  const F = N(fade), L = x.length - F, o = new Float32Array(L);
  for (let i = 0; i < L; i++) o[i] = x[i];
  for (let i = 0; i < F; i++) { const t = i / F; o[i] = x[i] * Math.sin(t * Math.PI / 2) + x[L + i] * Math.cos(t * Math.PI / 2); }
  return o;
}

// 在 [0, dur) 里按泊松过程撒事件，fn(t, k) 返回要加进去的片段（或 null）
function scatter(dst, r, rate, fn) {
  const dur = dst.length / SR; let t = 0, k = 0;
  while (true) { t += -Math.log(1 - r()) / rate; if (t >= dur) break; const s = fn(t, k++); if (s) add(dst, s, t); }
  return dst;
}

// ---------------------------------------------------------------- 乐器与音色

// Karplus-Strong 拨弦（竖琴 / 吉他）
function pluck(freq, dur, r, bright = 0.5, decay = 0.996) {
  const o = buf(dur); const P = Math.round(SR / freq);
  const line = lp(white(P, r), 1500 + 5000 * bright);
  let idx = 0, prev = 0;
  for (let i = 0; i < o.length; i++) {
    const v = line[idx]; const nv = decay * (0.5 * v + 0.5 * prev); prev = v; line[idx] = nv; o[i] = v; idx = (idx + 1) % P;
  }
  // 补一点柔和的基频，让音色更暖
  add(o, sweep(dur, () => freq, env(0.004, 0.9)), 0, 0.25);
  return dcBlock(o);
}
// FM 钟声（音叉 / 钢片琴 / 风铃）
function bell(freq, dur, ratio = 3.5, index = 2.4, decay = 0.9) {
  const o = buf(dur); let pc = 0, pm = 0;
  for (let i = 0; i < o.length; i++) {
    const t = i / SR; pm += TAU * freq * ratio / SR; const I = index * Math.exp(-t / (decay * 0.4));
    pc += TAU * freq / SR; o[i] = Math.sin(pc + I * Math.sin(pm)) * (t < 0.003 ? t / 0.003 : Math.exp(-t / decay));
  }
  add(o, sweep(dur, () => freq * 2.0, env(0.002, decay * 0.35)), 0, 0.18);
  return o;
}
// 马林巴（正弦 + 4 倍频，快衰减）
function mallet(freq, dur) { return mix([sweep(dur, () => freq, env(0.002, 0.35)), 1], [sweep(dur, () => freq * 4, env(0.001, 0.05)), 0.35], [sweep(dur, () => freq * 10, env(0.0005, 0.01)), 0.1]); }

// ---------------------------------------------------------------- 写文件

const STATS = path.join(OUT, '_stats.json');
const stats = ONLY.length && fs.existsSync(STATS) ? JSON.parse(fs.readFileSync(STATS, 'utf8')) : {};
function write(name, x, opts = {}) {
  if (ONLY.length && !ONLY.some((w) => name.includes(w))) return;
  const loop = !!opts.loop;
  if (loop) { let m = 0; for (const v of x) m += v; m /= x.length; for (let i = 0; i < x.length; i++) x[i] -= m; }   // 循环不过滤波器（起点的瞬态会破坏无缝），只减掉均值
  else x = dcBlock(x);
  if (opts.peak !== undefined) toPeak(x, opts.peak);
  if (opts.rms !== undefined) toRms(x, opts.rms);
  soft(x);
  const n = x.length;
  const smpl = loop ? 68 : 0;
  const b = Buffer.alloc(44 + n * 2 + smpl);
  b.write('RIFF', 0); b.writeUInt32LE(36 + n * 2 + smpl, 4); b.write('WAVE', 8);
  b.write('fmt ', 12); b.writeUInt32LE(16, 16); b.writeUInt16LE(1, 20); b.writeUInt16LE(1, 22);
  b.writeUInt32LE(SR, 24); b.writeUInt32LE(SR * 2, 28); b.writeUInt16LE(2, 32); b.writeUInt16LE(16, 34);
  b.write('data', 36); b.writeUInt32LE(n * 2, 40);
  for (let i = 0; i < n; i++) b.writeInt16LE(Math.round(clamp(x[i], -1, 1) * 32767), 44 + i * 2);
  if (loop) {
    const o = 44 + n * 2; b.write('smpl', o); b.writeUInt32LE(60, o + 4);
    b.writeUInt32LE(0, o + 8); b.writeUInt32LE(0, o + 12); b.writeUInt32LE(Math.round(1e9 / SR), o + 16); b.writeUInt32LE(60, o + 20);
    b.writeUInt32LE(0, o + 24); b.writeUInt32LE(0, o + 28); b.writeUInt32LE(0, o + 32); b.writeUInt32LE(1, o + 36); b.writeUInt32LE(0, o + 40);
    b.writeUInt32LE(0, o + 44); b.writeUInt32LE(0, o + 48); b.writeUInt32LE(opts.loopStart ? N(opts.loopStart) : 0, o + 52); b.writeUInt32LE(n - 1, o + 56);
    b.writeUInt32LE(0, o + 60); b.writeUInt32LE(0, o + 64);
  }
  fs.writeFileSync(path.join(OUT, name + '.wav'), b);
  let mean = 0; for (const v of x) mean += v; mean /= n;
  const seam = loop ? Math.abs(x[n - 1] - x[opts.loopStart ? N(opts.loopStart) : 0]) : 0;
  stats[name] = { seconds: +(n / SR).toFixed(3), peak: +peak(x).toFixed(3), rms_db: +(20 * Math.log10(rms(x) + 1e-9)).toFixed(1), dc: +mean.toFixed(5), loop, seam: +seam.toFixed(4) };
  console.log(name.padEnd(22), String(stats[name].seconds).padStart(7), 's  peak', stats[name].peak, ' rms', stats[name].rms_db, 'dB', loop ? ' loop seam ' + stats[name].seam : '');
}

fs.mkdirSync(OUT, { recursive: true });

// ================================================================ 环境循环

// 松林里的风：棕噪声过一道随阵风上下移动的带通，阵风来时更亮、更响；高处一缕细细的呼啸
{
  const r = rng(11), L = 24, F = 4, n = N(L + F);
  const g = drift(r, [0.045, 0.09, 0.021]);
  const base = bp(mix([brown(n, r), 0.7], [pink(n, r), 0.6]), (i) => 420 + 650 * g(i / SR), 0.7);
  const whistle = bp(white(n, r), (i) => 850 + 500 * g(i / SR), 7);
  const leaves = bp(pink(n, r), 2600, 0.6);
  const x = mix([base, 1.0], [whistle, 0.05], [leaves, 0.45]);
  mul(x, (t) => 0.45 + 0.55 * g(t));
  write('amb_wind', loopify(x, F), { loop: true, rms: -21 });
}
// 雪天的寒风：更高、更细、更空
{
  const r = rng(12), L = 24, F = 4, n = N(L + F);
  const g = drift(r, [0.06, 0.13, 0.03]);
  const x = mix([bp(pink(n, r), (i) => 700 + 900 * g(i / SR), 0.9), 1], [bp(white(n, r), (i) => 1600 + 700 * g(i / SR), 5), 0.07]);
  mul(x, (t) => 0.35 + 0.65 * g(t));
  write('amb_cold_wind', loopify(x, F), { loop: true, rms: -23 });
}
// 小雨：细密的沙沙声 + 一颗颗雨点
{
  const r = rng(21), L = 16, F = 2, n = N(L + F);
  const x = scale(lp(hp(pink(n, r), 700), 8000), 0.5);
  scatter(x, r, 70, () => { const a = Math.pow(r(), 2.2); return mix([burst(r, 0.012, 'bp', 2500 + r() * 4500, 1.4, 0.0005, 0.003), a], [sweep(0.03, () => 1800 + r() * 2500, env(0.0005, 0.006)), a * 0.3]); });
  write('amb_rain_light', loopify(x, F), { loop: true, rms: -24 });
}
// 大雨：更厚、更低，密集的雨点
{
  const r = rng(22), L = 16, F = 2, n = N(L + F);
  const g = drift(r, [0.08, 0.17]);
  const x = mix([lp(hp(pink(n, r), 300), 7000), 1], [lp(brown(n, r), 280), 0.5]);
  mul(x, (t) => 0.85 + 0.15 * g(t));
  scatter(x, r, 260, () => burst(r, 0.01, 'bp', 1800 + r() * 5000, 1.2, 0.0004, 0.0025, 'white').map((v) => v * Math.pow(r(), 2) * 1.5));
  write('amb_rain_heavy', loopify(x, F), { loop: true, rms: -19 });
}
// 屋顶上的雨（屋里听）：闷闷的嗒嗒声，偶尔一滴从檐口落下
{
  const r = rng(23), L = 16, F = 2, n = N(L + F);
  const x = scale(lp(pink(n, r), 2100), 0.35);
  scatter(x, r, 32, () => { const a = 0.3 + r() * 0.7; return mix([sweep(0.05, () => 170 + r() * 160, env(0.001, 0.018)), a], [burst(r, 0.04, 'bp', 1800 + r() * 1200, 1.2, 0.001, 0.01), a * 0.9]); });
  scatter(x, r, 0.7, () => sweep(0.3, () => 950 + r() * 400, env(0.001, 0.07)).map((v) => v * 0.5));
  write('amb_rain_roof', loopify(x, F), { loop: true, rms: -23 });
}
// 夏夜的虫鸣：几只蟋蟀各自按节奏三连唧，远处一片很轻的夜风
{
  const r = rng(31), L = 20, F = 2, n = N(L + F);
  const x = scale(lp(pink(n, r), 1200), 0.08);
  for (const [f, gain, period] of [[4300, 1.0, 0.62], [4650, 0.6, 0.71], [3950, 0.45, 0.83], [4900, 0.3, 0.55]]) {
    let t = r() * period;
    while (t < L + F) {
      const pulses = 3 + (r() < 0.3 ? 1 : 0);
      for (let k = 0; k < pulses; k++) add(x, sweep(0.022, () => f * (1 + 0.004 * k), hann(0.022)), t + k * 0.034, gain * (0.85 + 0.3 * r()));
      t += period * (0.9 + 0.2 * r());
    }
  }
  // 一只纺织娘：高一些的连续颤音
  const kat = sweep(L + F, () => 6200, (t) => (0.5 + 0.5 * Math.sin(TAU * 31 * t)) * (0.5 + 0.5 * Math.sin(TAU * 0.07 * t)));
  add(x, kat, 0, 0.12);
  write('amb_crickets', loopify(x, F), { loop: true, rms: -27 });
}
// 白天的林子：树叶沙沙（鸟叫是单独的一声声，见 bird_*）
{
  const r = rng(41), L = 24, F = 3, n = N(L + F);
  const g = drift(r, [0.07, 0.15, 0.033]);
  const x = bp(pink(n, r), (i) => 2200 + 900 * g(i / SR), 0.5);
  mul(x, (t) => 0.25 + 0.75 * Math.pow(g(t), 1.5));
  write('amb_forest', loopify(x, F), { loop: true, rms: -31 });
}
// 湖水拍岸：一下一下涌上来的低沉水声，退下去时带一点细碎的水花
{
  const r = rng(51), L = 18, F = 2, n = N(L + F);
  const x = scale(lp(brown(n, r), 380), 0.1);
  let t = r();
  while (t < L + F) {
    const len = 1.4 + r() * 0.8;
    add(x, burst(r, len, 'bp', 750, 0.55, 0.35 + r() * 0.2, 0.45, 'pink'), t, 1.2 + r() * 0.5);
    add(x, burst(r, 0.35, 'hp', 1500, 0.7, 0.02, 0.09, 'pink'), t + 0.45 + r() * 0.2, 0.5 + r() * 0.3);
    t += 1.4 + r() * 1.6;
  }
  write('amb_lake', loopify(x, F), { loop: true, rms: -23 });
}
// 小溪：哗哗的底子 + 不停冒的小水泡
{
  const r = rng(52), L = 12, F = 2, n = N(L + F);
  const x = scale(bp(pink(n, r), 1700, 0.45), 0.8);
  scatter(x, r, 38, () => { const f0 = 380 + r() * 1100, d = 0.02 + r() * 0.045; return sweep(d, (t) => f0 * Math.pow(1.7, t / d), hann(d)).map((v) => v * (0.15 + 0.4 * r())); });
  write('amb_creek', loopify(x, F), { loop: true, rms: -22 });
}
// 瀑布：宽频的轰鸣
{
  const r = rng(53), L = 12, F = 2, n = N(L + F);
  const g = drift(r, [0.3, 0.71]);
  const x = mix([lp(pink(n, r), 6500), 1], [lp(brown(n, r), 220), 0.35], [hp(white(n, r), 3200), 0.08]);
  mul(x, (t) => 0.9 + 0.1 * g(t));
  write('amb_waterfall', loopify(x, F), { loop: true, rms: -19 });
}
// 炉火 / 篝火：低低的呼呼声，噼啪的火星一阵一阵
{
  const r = rng(61), L = 16, F = 2, n = N(L + F);
  const g = drift(r, [0.4, 0.9, 0.17]);
  const x = mix([lp(brown(n, r), 300), 0.5], [hp(pink(n, r), 3000), 0.08]);
  mul(x, (t) => 0.6 + 0.4 * g(t));
  scatter(x, r, 3.5, () => {
    const c = buf(0.3); const k = 1 + Math.floor(r() * 5);
    for (let j = 0; j < k; j++) {
      const a = 0.35 + r() * 0.8;
      add(c, burst(r, 0.006, 'hp', 1500 + r() * 2500, 0.7, 0.0002, 0.0012), r() * 0.2, a);
      if (r() < 0.4) add(c, sweep(0.02, () => 700 + r() * 900, env(0.0005, 0.004)), r() * 0.2, a * 0.4);
    }
    return c;
  });
  write('amb_fire', loopify(x, F), { loop: true, rms: -26 });
}
// 水下：闷闷的低频，偶尔一串气泡
{
  const r = rng(71), L = 16, F = 2, n = N(L + F);
  const g = drift(r, [0.09, 0.2]);
  const x = lp(brown(n, r), 220);
  mul(x, (t) => 0.7 + 0.3 * g(t));
  scatter(x, r, 0.45, () => {
    const c = buf(0.9); const k = 3 + Math.floor(r() * 6);
    for (let j = 0; j < k; j++) { const f0 = 300 + r() * 500, d = 0.04 + r() * 0.05; add(c, sweep(d, (t) => f0 * (1 + 1.2 * t / d), hann(d)), r() * 0.7, 0.15 + r() * 0.25); }
    return lp(c, 1600);
  });
  write('amb_underwater', loopify(x, F), { loop: true, rms: -21 });
}
// 山洞：很低的空洞底噪，远处偶尔一滴水带回声
{
  const r = rng(72), L = 18, F = 2, n = N(L + F);
  const x = scale(lp(brown(n, r), 160), 0.4);
  const drips = buf(L + F);
  scatter(drips, r, 0.35, () => sweep(0.25, () => 1300 + r() * 800, env(0.0008, 0.05)).map((v) => v * (0.3 + 0.5 * r())));
  add(x, reverb(drips, 0.6, 0.86, 0.3, 0).slice(0, x.length));
  write('amb_cave', loopify(x, F), { loop: true, rms: -31 });
}
// 云海：高处的风，时不时一声很轻的风铃
{
  const r = rng(81), L = 24, F = 3, n = N(L + F);
  const g = drift(r, [0.05, 0.12]);
  const x = mix([bp(pink(n, r), (i) => 1000 + 700 * g(i / SR), 0.7), 1], [bp(brown(n, r), 420, 0.8), 0.6]);
  mul(x, (t) => 0.5 + 0.5 * g(t));
  const ch = buf(L + F); const notes = [84, 86, 88, 91, 93, 96];
  scatter(ch, r, 0.25, () => bell(midiHz(notes[Math.floor(r() * notes.length)]), 2.0, 3.5, 1.4, 0.7).map((v) => v * (0.1 + 0.1 * r())));
  add(x, reverb(ch, 0.5, 0.85, 0.3, 0).slice(0, x.length), 0, 1.0);
  write('amb_cloud_wind', loopify(x, F), { loop: true, rms: -23 });
}
// 沙丘：干燥的风，沙子贴着地面刷过去
{
  const r = rng(82), L = 24, F = 3, n = N(L + F);
  const g = drift(r, [0.04, 0.1, 0.027]);
  const x = mix([bp(pink(n, r), (i) => 1500 + 900 * g(i / SR), 0.6), 1], [hp(white(n, r), 4500), 0.12], [bp(brown(n, r), 300, 0.8), 0.5]);
  mul(x, (t) => 0.35 + 0.65 * g(t));
  write('amb_desert_wind', loopify(x, F), { loop: true, rms: -23 });
}
// 亚特兰蒂斯的穹顶：很低的嗡鸣，远处鲸鱼的长鸣
{
  const r = rng(83), L = 24, F = 3;
  const hum = sweep(L + F, () => 55, (t) => 0.6 + 0.4 * Math.sin(TAU * 0.09 * t), 0.5, 0.25);
  const whale = buf(L + F);
  for (const at of [3.5, 14.5]) {
    const d = 3.2;
    const call = sweep(d, (t) => { const u = t / d; return (u < 0.5 ? lerp(170, 310, u * 2) : lerp(310, 210, (u - 0.5) * 2)) + 6 * Math.sin(TAU * 5 * t); }, (t) => Math.sin(Math.PI * t / d) ** 1.5, 0.3);
    add(whale, call, at, 0.6);
  }
  const x = mix([hum, 0.5], [lp(reverb(whale, 0.65, 0.88, 0.4, 0).slice(0, N(L + F)), 1200), 1]);
  add(x, lp(brown(N(L + F), r), 150), 0, 0.3);
  write('amb_dome', loopify(x, F), { loop: true, rms: -24 });
}
// 仙境：细细碎碎的亮晶晶的铃声
{
  const r = rng(84), L = 16, F = 2;
  const x = buf(L + F); const notes = [96, 98, 100, 103, 105, 108];
  scatter(x, r, 3.2, () => bell(midiHz(notes[Math.floor(r() * notes.length)]), 0.8, 2.0, 1.2, 0.25).map((v) => v * (0.08 + 0.15 * r())));
  const sh = bp(white(N(L + F), r), 7500, 1.5); mul(sh, (t) => 0.5 + 0.5 * Math.sin(TAU * 0.3 * t));
  add(x, sh, 0, 0.04);
  write('amb_fairy', loopify(reverb(x, 0.5, 0.85, 0.25, 0).slice(0, N(L + F)), F), { loop: true, rms: -29 });
}
// 泳池馆：室内的轻轻水声
{
  const r = rng(85), L = 12, F = 2, n = N(L + F);
  const x = scale(lp(brown(n, r), 500), 0.08);
  let t = 0.3;
  while (t < L + F) { add(x, burst(r, 0.6, 'bp', 1400 + r() * 700, 0.8, 0.08, 0.15, 'pink'), t, 0.5 + r() * 0.3); t += 0.8 + r() * 1.3; }
  write('amb_pool', loopify(reverb(x, 0.45, 0.8, 0.3, 0).slice(0, n), F), { loop: true, rms: -27 });
}

// ================================================================ 鸟、虫、雷

{
  const r = rng(91);
  const birds = [
    // 两声口哨
    () => { const x = buf(0.42); add(x, sweep(0.12, (t) => 2700 + 1600 * t, hann(0.12), 0.12)); add(x, sweep(0.17, (t) => 2300 - 900 * t, hann(0.17), 0.12), 0.18); return x; },
    // 一串颤音
    () => sweep(0.55, (t) => 3700 - 1000 * t, (t) => (0.5 + 0.5 * Math.sin(TAU * 22 * t)) * Math.sin(Math.PI * t / 0.55), 0.1),
    // 三声往下的啾
    () => { const x = buf(0.5); [4300, 4000, 3700].forEach((f, k) => add(x, sweep(0.06, (t) => f - 18000 * t, hann(0.06), 0.15), k * 0.14)); return x; },
    // 婉转的鸣唱
    () => sweep(0.75, (t) => 2900 + 600 * t + 500 * Math.sin(TAU * 11 * t), (t) => Math.sin(Math.PI * t / 0.75) ** 0.7, 0.1),
    // 斑鸠一样的“咕—咕”
    () => { const x = buf(1.0); add(x, sweep(0.3, () => 520, (t) => Math.sin(Math.PI * t / 0.3) ** 2, 0.3, 0.1)); add(x, sweep(0.45, (t) => 480 - 30 * t, (t) => Math.sin(Math.PI * t / 0.45) ** 2, 0.3, 0.1), 0.42); return lp(x, 1800); },
    // 四声往上挑的“啾”
    () => { const x = buf(0.5); for (let k = 0; k < 4; k++) add(x, sweep(0.05, (t) => 2500 + 30000 * t, hann(0.05), 0.1), k * 0.1); return x; },
  ];
  birds.forEach((fn, i) => write(`bird_${i + 1}`, fn(), { peak: -4 }));
  // 猫头鹰：夜里两三声“呼—呼呼”
  {
    const x = buf(1.6); const hoo = (d) => mix([sweep(d, (t) => 370 - 40 * t, (t) => Math.sin(Math.PI * t / d) ** 1.4, 0.15), 1], [burst(r, d, 'bp', 400, 1.5, d * 0.4, d * 0.4, 'pink'), 0.05]);
    add(x, hoo(0.45)); add(x, hoo(0.18), 0.75); add(x, hoo(0.4), 1.0);
    write('owl', lp(reverb(x, 0.25, 0.7, 0.4, 0.3), 1400), { peak: -6 });
  }
  // 青蛙：一串短促的呱
  for (let v = 0; v < 2; v++) {
    const x = buf(0.45); const pulses = 6 + v * 3; const f = v ? 520 : 430;
    for (let k = 0; k < pulses; k++) add(x, mix([burst(r, 0.025, 'bp', f, 5, 0.002, 0.008), 1.2], [sweep(0.025, () => f / 2, env(0.002, 0.008)), 0.6]), k * 0.033);
    write(`frog_${v + 1}`, x, { peak: -6 });
  }
  // 雷：近的先一声炸裂，远的只有闷闷的滚动
  for (let v = 0; v < 3; v++) {
    const d = 7.5, x = buf(d), near = v === 0;
    const rumble = brown(N(d), r);
    // 几阵先后滚过来的轰隆：每阵 0.25 s 涌起、再慢慢退下去
    const k = 3 + Math.floor(r() * 3);
    const onsets = Array.from({ length: k }, (_, j) => (j / k) * 2.4 + r() * 0.3);
    const envf = (t) => { let s = 0; for (let j = 0; j < k; j++) { const t0 = onsets[j]; s += (t > t0 ? (t - t0 < 0.25 ? (t - t0) / 0.25 : Math.exp(-(t - t0 - 0.25) / (1.2 + 0.5 * j))) : 0) * (1 - j * 0.15); } return s; };
    const body = mul(lp(rumble, (i) => lerp(near ? 600 : 260, 110, Math.min(1, i / N(d))), 0.8), envf);
    add(x, body);
    if (near) add(x, burst(r, 0.5, 'hp', 1200, 0.7, 0.003, 0.09), 0, 1.2);
    write(`thunder_${v + 1}`, x, { peak: -2 });
  }
}

// ================================================================ 脚步、跳、水

{
  const r = rng(101);
  const thump = (f, d, a) => sweep(d, () => f, env(0.002, d * 0.3)).map((v) => v * a);
  const kinds = {
    grass: () => { const x = buf(0.22); for (let j = 0; j < 3; j++) add(x, burst(r, 0.08, 'bp', 2200 + r() * 2500, 0.6, 0.004, 0.022, 'pink'), j * 0.018 + r() * 0.01, 1.0 + r() * 0.6); add(x, thump(85, 0.08, 0.12)); return lp(x, 7000); },
    gravel: () => { const x = buf(0.2); for (let j = 0; j < 16; j++) add(x, burst(r, 0.008, 'bp', 1500 + r() * 4000, 1.5, 0.0004, 0.0025), r() * 0.08, 0.6 + r() * 0.9); add(x, thump(90, 0.08, 0.18)); return x; },
    wood: () => { const x = buf(0.3); add(x, thump(150 + r() * 40, 0.15, 0.6)); add(x, burst(r, 0.12, 'bp', 360 + r() * 60, 4, 0.002, 0.035), 0, 1.1); add(x, burst(r, 0.12, 'bp', 820, 6, 0.002, 0.03), 0.002, 0.55); add(x, burst(r, 0.01, 'hp', 2500, 0.7, 0.0005, 0.002), 0, 0.3); return x; },
    stone: () => { const x = buf(0.18); add(x, burst(r, 0.05, 'hp', 1600, 0.7, 0.0005, 0.008), 0, 0.9); add(x, burst(r, 0.08, 'bp', 2400 + r() * 500, 3, 0.001, 0.018), 0, 0.6); add(x, thump(105, 0.06, 0.25)); return x; },
    snow: () => { const x = buf(0.3); for (let j = 0; j < 24; j++) { const t = r() * 0.13; add(x, burst(r, 0.01, 'bp', 1100 + r() * 2200, 1.2, 0.001, 0.003), t, (0.4 + r() * 0.7) * Math.min(1, t / 0.05 + 0.3)); } add(x, thump(70, 0.1, 0.12)); return lp(x, 6000); },
    sand: () => { const x = buf(0.25); add(x, burst(r, 0.2, 'bp', 2600 + r() * 800, 0.6, 0.02, 0.055, 'pink'), 0, 1.4); add(x, thump(80, 0.08, 0.12)); return x; },
    water: () => { const x = buf(0.4); add(x, burst(r, 0.3, 'lp', 2800, 0.7, 0.01, 0.07, 'pink'), 0, 1); for (let j = 0; j < 3; j++) { const f0 = 450 + r() * 500; add(x, sweep(0.05, (t) => f0 * (1 + 10 * t), hann(0.05)), 0.03 + r() * 0.15, 0.3); } add(x, thump(70, 0.06, 0.3)); return x; },
  };
  for (const [k, fn] of Object.entries(kinds)) for (let v = 1; v <= 4; v++) write(`step_${k}_${v}`, fn(), { peak: -7 });
  // 落地：重一点的闷响（运行时再叠一声对应地面的脚步）
  { const x = buf(0.35); add(x, thump(65, 0.25, 1)); add(x, burst(r, 0.2, 'lp', 700, 0.7, 0.002, 0.05, 'pink'), 0, 0.6); write('land', x, { peak: -5 }); }
  // 跳进水里、游泳划水、出水时的水滴
  for (let v = 1; v <= 2; v++) {
    const x = buf(1.2); add(x, burst(r, 0.9, 'lp', 4200, 0.7, 0.004, 0.16, 'pink'), 0, 1);
    add(x, sweep(0.3, () => 60, env(0.002, 0.08)), 0, 0.7);
    for (let j = 0; j < 12; j++) { const f0 = 350 + r() * 700, d = 0.04 + r() * 0.05; add(x, sweep(d, (t) => f0 * (1 + 1.5 * t / d), hann(d)), 0.05 + r() * 0.7, 0.2 + r() * 0.2); }
    write(`splash_${v}`, x, { peak: -3 });
  }
  for (let v = 1; v <= 3; v++) {
    const x = buf(0.6); add(x, burst(r, 0.5, 'lp', 2200, 0.7, 0.12, 0.12, 'pink'), 0, 1);
    for (let j = 0; j < 3; j++) { const f0 = 400 + r() * 500, d = 0.05; add(x, sweep(d, (t) => f0 * (1 + 12 * t), hann(d)), 0.12 + r() * 0.3, 0.2); }
    write(`swim_${v}`, x, { peak: -8 });
  }
  { const x = buf(1.2); for (let j = 0; j < 7; j++) add(x, sweep(0.12, () => 750 + r() * 900, env(0.001, 0.025)), 0.05 + j * 0.13 + r() * 0.08, 0.4 + r() * 0.4); add(x, burst(r, 0.3, 'lp', 2500, 0.7, 0.01, 0.08, 'pink'), 0, 0.5); write('drip', x, { peak: -8 }); }
}

// ================================================================ 门、灯、火、交互

{
  const r = rng(111);
  const click = (f = 3000, a = 1) => burst(r, 0.012, 'bp', f, 2.5, 0.0003, 0.002).map((v) => v * a);
  const thud = (f, d) => mix([sweep(d, () => f, env(0.002, d * 0.3)), 1], [burst(r, d, 'bp', f * 2.4, 2, 0.002, d * 0.25), 0.8]);
  // 木门开：门闩一响，门轴吱一声，带起一点风
  for (let v = 1; v <= 2; v++) {
    const x = buf(0.8); add(x, click(2600, 1)); add(x, click(1900, 0.6), 0.03);
    const creak = buf(0.45); let ph = 0; for (let i = 0; i < creak.length; i++) { const t = i / SR; ph += TAU * (95 + 45 * t / 0.45 + 15 * Math.sin(TAU * 7 * t) + (r() - 0.5) * 30) / SR; creak[i] = (ph % TAU < 0.6 ? 1 : 0) * Math.sin(Math.PI * t / 0.45); }
    add(x, bp(creak, 950 + v * 150, 3), 0.08, 0.35);
    add(x, burst(r, 0.4, 'bp', 600, 0.7, 0.15, 0.1, 'pink'), 0.12, 0.15);
    write(`door_open_${v}`, x, { peak: -5 });
  }
  for (let v = 1; v <= 2; v++) { const x = buf(0.5); add(x, thud(105 + v * 10, 0.3)); add(x, click(2400, 0.8), 0.015); write(`door_close_${v}`, x, { peak: -4 }); }
  { const x = buf(0.4); for (let j = 0; j < 3; j++) add(x, burst(r, 0.04, 'bp', 2900 + r() * 400, 8, 0.0005, 0.012), j * 0.07, 0.8); add(x, thud(140, 0.1), 0.02, 0.4); write('door_locked', x, { peak: -6 }); }
  { const x = buf(0.9); [2600, 2900, 3300].forEach((f, k) => add(x, burst(r, 0.05, 'bp', f, 9, 0.0005, 0.015), k * 0.16, 0.9)); add(x, thud(160, 0.2), 0.55, 0.9); add(x, click(2000), 0.55); write('unlock', x, { peak: -5 }); }
  { const x = buf(0.12); add(x, click(3500, 1)); add(x, click(2800, 0.7), 0.035); write('switch', x, { peak: -8 }); }
  // 生火：一阵呼的火苗声，跟着几声噼啪
  { const x = buf(1.3); add(x, mul(bp(pink(N(1.3), r), (i) => 300 + 1800 * Math.min(1, i / N(0.5)), 0.8), (t) => (t < 0.35 ? t / 0.35 : Math.exp(-(t - 0.35) / 0.35))), 0, 1); for (let j = 0; j < 6; j++) add(x, burst(r, 0.006, 'hp', 2500, 0.7, 0.0002, 0.0012), 0.3 + r() * 0.8, 0.6 + r()); write('fire_ignite', x, { peak: -4 }); }
  { const x = buf(1.1); add(x, mul(lp(hp(white(N(1.1), r), 1800), (i) => lerp(9000, 2500, i / N(1.1))), env(0.02, 0.35)), 0, 1); write('fire_out', x, { peak: -7 }); }
  // 坐下 / 躺下：衣服摩擦的窸窣
  for (let v = 1; v <= 2; v++) { const x = buf(0.5); const g = drift(r, [9, 17, 31]); add(x, mul(bp(pink(N(0.5), r), 2600, 0.8), (t) => Math.sin(Math.PI * t / 0.5) * (0.3 + 0.7 * g(t))), 0, 1); add(x, thud(90, 0.12), 0.25, 0.25); write(`cloth_${v}`, x, { peak: -9 }); }
  // 风灯点亮：呼的一声，跟一个三和弦的铃
  { const x = buf(2.6); add(x, mul(bp(pink(N(1), r), (i) => 400 + 2400 * i / N(1), 0.8), env(0.25, 0.3)), 0, 0.6); [84, 88, 91].forEach((m, k) => add(x, bell(midiHz(m), 2.2, 3.5, 1.6, 0.8), 0.25 + k * 0.09, 0.35)); write('beacon', reverb(x, 0.35, 0.82, 0.3, 0.8), { peak: -4 }); }
  // 石雕像转动：石头摩擦的嘎嘎声
  { const x = buf(0.8); add(x, mul(bp(brown(N(0.7), r), 380, 1.6), (t) => Math.sin(Math.PI * t / 0.7) * (0.6 + 0.4 * Math.sin(TAU * 28 * t))), 0, 1); add(x, thud(130, 0.12), 0.68, 0.6); write('stone_turn', x, { peak: -5 }); }
  // 碎片嵌回祭坛：咚的一声石头，跟一声钟
  { const x = buf(2.2); add(x, thud(120, 0.25)); add(x, bell(midiHz(79), 2.0, 3.5, 1.2, 0.8), 0.06, 0.5); write('altar', reverb(x, 0.3, 0.8, 0.3, 0.6), { peak: -4 }); }
  // 穿过光门：一阵往上扬的风声，带一串亮晶晶的琶音
  { const x = buf(2.0); add(x, mul(bp(pink(N(1.6), r), (i) => 200 * Math.pow(15, i / N(1.6)), 0.9), (t) => Math.sin(Math.PI * t / 1.6)), 0, 0.8); [84, 88, 91, 96].forEach((m, k) => add(x, bell(midiHz(m), 1.2, 2.0, 1.0, 0.4), 0.6 + k * 0.1, 0.25)); write('portal', reverb(x, 0.4, 0.84, 0.3, 0.6), { peak: -4 }); }
  // 摄影的快门
  { const x = buf(0.2); add(x, click(3200, 1)); add(x, burst(r, 0.06, 'bp', 1400, 1.2, 0.002, 0.015), 0.01, 0.5); add(x, click(2600, 0.8), 0.08); write('shutter', x, { peak: -7 }); }
  // 钓鱼：甩竿的呼、浮漂 / 石子落水的噗通、咬钩的小水花
  { const x = buf(0.45); add(x, mul(bp(white(N(0.4), r), (i) => 900 + 2200 * i / N(0.4), 1.2), (t) => Math.sin(Math.PI * t / 0.4) ** 2), 0, 1); write('whoosh', x, { peak: -8 }); }
  { const x = buf(0.3); add(x, sweep(0.06, (t) => 950 * Math.exp(-t * 18), env(0.001, 0.02)), 0, 1); add(x, burst(r, 0.12, 'lp', 3000, 0.7, 0.002, 0.03, 'pink'), 0, 0.5); write('plop', x, { peak: -6 }); }
  { const x = buf(0.6); add(x, burst(r, 0.4, 'lp', 3500, 0.7, 0.005, 0.08, 'pink'), 0, 1); for (let j = 0; j < 4; j++) add(x, sweep(0.05, (t) => (500 + r() * 400) * (1 + 10 * t), hann(0.05)), 0.02 + r() * 0.2, 0.3); write('splash_small', x, { peak: -5 }); }
  // 挖：铲子插进土里
  { const x = buf(0.4); add(x, thud(95, 0.18)); for (let j = 0; j < 12; j++) add(x, burst(r, 0.006, 'bp', 1500 + r() * 2500, 1.5, 0.0004, 0.002), 0.02 + r() * 0.12, 0.5); write('dig', x, { peak: -6 }); }
  // 棋子落盘：木头清脆的一下
  { const x = buf(0.15); add(x, sweep(0.08, () => 1050, env(0.0005, 0.012)), 0, 1); add(x, burst(r, 0.05, 'bp', 2200, 3, 0.0005, 0.008), 0, 0.5); write('chess', x, { peak: -8 }); }
  // 炉子上煎东西：滋滋
  { const r2 = rng(112); const x = mul(hp(white(N(1.6), r2), 2500), (t) => Math.min(1, t / 0.08) * Math.exp(-Math.max(0, t - 1.1) / 0.15) * (0.7 + 0.3 * Math.sin(TAU * 13 * t))); scatter(x, r2, 12, () => burst(r2, 0.006, 'hp', 3000, 0.7, 0.0002, 0.0015).map((v) => v * 2)); write('sizzle', x, { peak: -8 }); }
  // 划船：桨入水的哗
  { const x = buf(0.7); add(x, mul(bp(pink(N(0.6), r), (i) => 600 + 900 * i / N(0.6), 0.7), (t) => Math.sin(Math.PI * t / 0.6) ** 1.5), 0, 1); add(x, sweep(0.1, () => 700, hann(0.1)), 0.35, 0.15); write('paddle', x, { peak: -8 }); }
}

// ================================================================ 界面

{
  const r = rng(121);
  { write('ui_click', mix([sweep(0.03, () => 880, env(0.001, 0.008)), 1], [burst(r, 0.01, 'bp', 3200, 2, 0.0003, 0.002), 0.3]), { peak: -10 }); }
  { write('ui_open', sweep(0.09, (t) => 520 + 3500 * t, env(0.005, 0.03), 0.2), { peak: -11 }); }
  { write('ui_close', sweep(0.09, (t) => 830 - 3500 * t, env(0.005, 0.03), 0.2), { peak: -12 }); }
  { write('blip', sweep(0.05, () => 1180, env(0.002, 0.012), 0.15), { peak: -16 }); }
  // 纸：展开信纸的沙沙
  { const x = buf(0.55); const g = drift(r, [23, 41, 67]); add(x, mul(bp(white(N(0.5), r), 4200, 0.7), (t) => Math.sin(Math.PI * t / 0.5) * Math.pow(g(t), 2)), 0, 1); write('paper', x, { peak: -10 }); }
  { const x = buf(0.35); add(x, mul(bp(white(N(0.3), r), (i) => 1800 + 3500 * i / N(0.3), 0.8), (t) => Math.sin(Math.PI * t / 0.3) ** 2), 0, 1); add(x, burst(r, 0.03, 'lp', 1200, 0.7, 0.001, 0.008, 'pink'), 0.27, 0.4); write('page', x, { peak: -10 }); }
  // 捡到东西：上行的三个亮音
  { const x = buf(1.0); [84, 88, 91].forEach((m, k) => add(x, bell(midiHz(m), 0.8, 2.0, 1.0, 0.3), k * 0.06, 0.5)); write('pickup', reverb(x, 0.25, 0.75, 0.3, 0.4), { peak: -6 }); }
  // 发现新地方：两声柔和的钟
  { const x = buf(1.6); add(x, bell(midiHz(79), 1.4, 3.5, 1.0, 0.6), 0, 0.6); add(x, bell(midiHz(86), 1.4, 3.5, 1.0, 0.6), 0.18, 0.5); write('discover', reverb(x, 0.35, 0.82, 0.3, 0.6), { peak: -7 }); }
  // 任务完成：马林巴上行
  { const x = buf(1.2); [72, 76, 79, 84].forEach((m, k) => add(x, mallet(midiHz(m), 0.6), k * 0.09, 0.6)); write('quest', reverb(x, 0.25, 0.75, 0.3, 0.4), { peak: -5 }); }
  // 成就：慢一点的四个钟 + 一层亮光
  { const x = buf(2.4); [72, 79, 84, 88].forEach((m, k) => add(x, bell(midiHz(m), 1.6, 3.5, 1.4, 0.8), k * 0.16, 0.45)); write('achievement', reverb(x, 0.4, 0.84, 0.3, 0.8), { peak: -5 }); }
}

// ================================================================ 音乐用的乐器（MusicDirector 按音高换算 pitch_scale）

{
  const r = rng(131);
  write('inst_harp', reverb(pluck(midiHz(60), 4.0, r, 0.45, 0.9965), 0.12, 0.7, 0.4, 0.5), { peak: -3 });            // C4
  write('inst_bell', bell(midiHz(72), 4.0, 3.5, 1.8, 1.1), { peak: -3 });                                           // C5
  write('inst_bass', mul(lp(mix([sweep(3.5, () => midiHz(36), () => 1), 1], [sweep(3.5, () => midiHz(48), () => 1), 0.3], [sweep(3.5, () => midiHz(55), () => 1), 0.08]), 900), env(0.01, 1.1)), { peak: -3 });  // C2
  // 柔和的长音铺底：三个略微走调的锯齿波过低通，2 s 以后循环
  {
    const f = midiHz(48), d = 7.0, x = buf(d);
    for (const det of [-0.006, 0, 0.0055]) { let ph = r(); for (let i = 0; i < x.length; i++) { ph += f * (1 + det) / SR; ph -= Math.floor(ph); x[i] += (2 * ph - 1) * 0.33; } }
    add(x, sweep(d, () => f / 2, () => 1), 0, 0.35);
    const y = lp(x, 1100, 0.6);
    mul(y, (t) => Math.min(1, t / 0.9));
    // 循环段 [2, 6] s：把 [6, 7] 交叉淡化进 2 s 处
    const s = N(2), e = N(6), F = N(1), o = y.slice(0, e);
    for (let i = 0; i < F; i++) { const t = i / F; o[s + i] = y[s + i] * Math.sin(t * Math.PI / 2) + y[e + i] * Math.cos(t * Math.PI / 2); }
    write('inst_pad', o, { peak: -4, loop: true, loopStart: 2 });
  }
}

fs.writeFileSync(STATS, JSON.stringify(stats, null, 1));
console.log(Object.keys(stats).length, 'files →', OUT);
