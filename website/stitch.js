/*
  The embroidered look: draws thread stitches onto the page with <canvas>.
  Each element listed in STITCH_PLAN gets one canvas per "layer" (a satin edge, a zigzag edge,
  a running stitch, or a tatami / satin fill). Every stitch is drawn as a little shaded thread,
  and its sheen changes with its direction, the same way real thread catches the light.
  Without JavaScript the page keeps its plain dashed borders (see embroidered.css).
*/

// Thread colors (the site's palette, plus darker shades for satin edges).
const THREADS = {
  gold: '#f2b33d', goldDark: '#b97f17',
  tomato: '#c4412a', tomatoDark: '#8d2716',
  sage: '#8fbf8a', sageDark: '#5d8a59',
  cream: '#f4e6c8', white: '#fff8ec',
  denim: '#1b2a44', denimLine: '#6f84a8',
  wood: '#c9955a',
};

// What gets stitched. Layers are drawn in order, so fills come before edges.
// width = stitch column width in px, inset = how far inside the element's edge the stitch line runs.
const STITCH_PLAN = [
  // On filled shapes the edge stitch straddles the edge (inset ≈ 1), covering where the fill ends,
  // the way a satin border covers the raw edge of a real patch.
  ['.nav-pill:not(.nav-source)', [{ type: 'run', inset: 1, thread: 'denimLine' }]],
  ['.nav-source', [{ type: 'zigzag', width: 5, inset: 1, thread: 'denim' }]],
  ['.hero-tag', [{ type: 'tatami', thread: 'tomato', angle: 30 }, { type: 'satin', width: 5, inset: 1, thread: 'white' }]],
  // Filled buttons stay flat inside: a thread texture behind the text made it hard to read.
  ['.button-gold', [{ type: 'zigzag', width: 6, inset: 1, thread: 'denim' }]],
  ['.button-denim', [{ type: 'zigzag', width: 6, inset: 1, thread: 'gold' }]],
  ['.band .button-stitched, .hero .button-stitched', [{ type: 'zigzag', width: 6, inset: 3, thread: 'cream' }]],
  ['.start-main .button-stitched', [{ type: 'zigzag', width: 6, inset: 3, thread: 'white' }]],
  ['.pill-group', [{ type: 'run', inset: -1, thread: 'denimLine' }]],
  ['.pill-button', [{ type: 'zigzag', width: 4, inset: 1, thread: 'goldDark' }]],
  ['.inspect-button', [{ type: 'run', inset: 1, thread: 'denimLine' }]],
  ['.restart-button', [{ type: 'run', inset: 1, thread: 'cream' }]],
  ['.patch-gold', [{ type: 'satin', width: 11, inset: 5, thread: 'gold' }, { type: 'run', inset: 21, thread: 'cream' }]],
  ['.patch-tomato', [{ type: 'satin', width: 11, inset: 5, thread: 'tomato' }, { type: 'run', inset: 21, thread: 'cream' }]],
  ['.patch-sage', [{ type: 'satin', width: 11, inset: 5, thread: 'sage' }, { type: 'run', inset: 21, thread: 'cream' }]],
  ['.workspace-list article', [{ type: 'run', inset: 1, thread: 'denimLine' }]],
  ['.dot-gold', [{ type: 'satinFill', thread: 'gold', angle: 60 }]],
  ['.dot-tomato', [{ type: 'satinFill', thread: 'tomato', angle: 60 }]],
  ['.dot-sage', [{ type: 'satinFill', thread: 'sage', angle: 60 }]],
  ['.badge-gold', [{ type: 'tatami', thread: 'gold' }, { type: 'satin', width: 9, inset: 2, thread: 'goldDark' }, { type: 'run', inset: 16, thread: 'denim' }]],
  ['.badge-tomato', [{ type: 'tatami', thread: 'tomato' }, { type: 'satin', width: 9, inset: 2, thread: 'tomatoDark' }, { type: 'run', inset: 16, thread: 'white' }]],
  ['.badge-sage', [{ type: 'tatami', thread: 'sage' }, { type: 'satin', width: 9, inset: 2, thread: 'sageDark' }, { type: 'run', inset: 16, thread: 'denim' }]],
  ['.badge-cream', [{ type: 'tatami', thread: 'cream' }, { type: 'satin', width: 9, inset: 2, thread: 'wood' }, { type: 'run', inset: 16, thread: 'denim' }]],
  ['.labels li', [{ type: 'run', inset: 6, thread: 'gold', stitch: 5 }]],
  ['.labels .label-tomato', [{ type: 'run', inset: 6, thread: 'white', stitch: 5 }]],
  ['.labels .label-gold, .labels .label-sage', [{ type: 'run', inset: 6, thread: 'denim', stitch: 5 }]],
  ['.start-main', [{ type: 'tatami', thread: 'tomato', angle: -20 }, { type: 'satin', width: 12, inset: 6, thread: 'white' }, { type: 'run', inset: 24, thread: 'white' }]],
  ['.band-cream', [{ type: 'zigzag', edge: 'top', width: 7, inset: 0, thread: 'gold' }, { type: 'zigzag', edge: 'bottom', width: 7, inset: 0, thread: 'gold' }]],
  ['.site-footer', [{ type: 'run', edge: 'top', inset: 0, thread: 'denimLine' }]],
];

const LIGHT_ANGLE = -Math.PI * 0.75; // light comes from the top left

/* ---------- Colors ---------- */

function hexToRgb(hex) {
  const n = parseInt(hex.slice(1), 16);
  return [(n >> 16) & 255, (n >> 8) & 255, n & 255];
}
// Blends two RGB colors; t = 0 gives a, t = 1 gives b. Returns a CSS rgba() string.
function mix(a, b, t, alpha = 1) {
  const c = a.map((v, i) => Math.round(v + (b[i] - v) * t));
  return `rgba(${c[0]},${c[1]},${c[2]},${alpha})`;
}
// Precomputes every shade one thread needs, so drawing doesn't build color strings per stitch.
const shadeCache = new Map();
function threadShades(name) {
  if (shadeCache.has(name)) return shadeCache.get(name);
  const base = hexToRgb(THREADS[name] || name);
  const black = [5, 10, 22], white = [255, 255, 255];
  const shades = {
    shadow: mix(base, black, 0.55, 0.9),
    // Six tones from slightly dark to slightly bright; a stitch picks one by its direction.
    tones: [0, 1, 2, 3, 4, 5].map(i => i < 2 ? mix(base, black, 0.18 - i * 0.09) : mix(base, white, (i - 2) * 0.07)),
    highlight: mix(base, white, 0.55, 0.75),
  };
  shadeCache.set(name, shades);
  return shades;
}

/* ---------- Drawing one stitch ---------- */

// Draws one thread from (ax, ay) to (bx, by): a shadow, the thread body, then a thin shine.
function drawThread(ctx, ax, ay, bx, by, shades, width) {
  const dx = bx - ax, dy = by - ay;
  const length = Math.hypot(dx, dy) || 1;
  const sheen = Math.abs(Math.sin(Math.atan2(dy, dx) - LIGHT_ANGLE)); // 0 = dull, 1 = shiny
  ctx.lineWidth = width;
  ctx.strokeStyle = shades.shadow;
  line(ctx, ax + 0.35, ay + 0.55, bx + 0.35, by + 0.55);
  ctx.lineWidth = width * 0.8;
  ctx.strokeStyle = shades.tones[Math.round(sheen * 5)];
  line(ctx, ax, ay, bx, by);
  // The shine sits on the lit side of the thread and stops short of both ends.
  const ox = (dy / length) * width * 0.18, oy = (-dx / length) * width * 0.18;
  ctx.lineWidth = width * 0.28;
  ctx.strokeStyle = shades.highlight;
  ctx.globalAlpha = 0.25 + sheen * 0.6;
  line(ctx, ax + dx * 0.2 - ox, ay + dy * 0.2 - oy, ax + dx * 0.8 - ox, ay + dy * 0.8 - oy);
  ctx.globalAlpha = 1;
}
function line(ctx, ax, ay, bx, by) {
  ctx.beginPath();
  ctx.moveTo(ax, ay);
  ctx.lineTo(bx, by);
  ctx.stroke();
}

/* ---------- Paths the stitches follow ---------- */

// The outline of a rounded rectangle as a path you can walk along.
// at(s) returns the point s pixels along it, plus the outward-facing direction (nx, ny).
function roundedRectPath(x, y, w, h, r) {
  r = Math.max(0, Math.min(r, w / 2, h / 2));
  const flatW = w - 2 * r, flatH = h - 2 * r, corner = (Math.PI * r) / 2;
  const segments = [
    { len: flatW, line: [x + r, y, 1, 0, 0, -1] },
    { len: corner, arc: [x + w - r, y + r, -Math.PI / 2] },
    { len: flatH, line: [x + w, y + r, 0, 1, 1, 0] },
    { len: corner, arc: [x + w - r, y + h - r, 0] },
    { len: flatW, line: [x + w - r, y + h, -1, 0, 0, 1] },
    { len: corner, arc: [x + r, y + h - r, Math.PI / 2] },
    { len: flatH, line: [x, y + h - r, 0, -1, -1, 0] },
    { len: corner, arc: [x + r, y + r, Math.PI] },
  ];
  const length = segments.reduce((sum, seg) => sum + seg.len, 0);
  return {
    length,
    closed: true,
    pieces: segments.map(seg => seg.len).filter(len => len > 0.01), // each side and corner, in order
    at(s) {
      s = ((s % length) + length) % length;
      for (const seg of segments) {
        if (s > seg.len && seg !== segments[segments.length - 1]) { s -= seg.len; continue; }
        if (seg.line) {
          const [x0, y0, dx, dy, nx, ny] = seg.line;
          return { x: x0 + dx * s, y: y0 + dy * s, nx, ny };
        }
        const [cx, cy, a0] = seg.arc;
        const a = a0 + (r ? s / r : 0);
        return { x: cx + r * Math.cos(a), y: cy + r * Math.sin(a), nx: Math.cos(a), ny: Math.sin(a) };
      }
    },
  };
}
// A straight line across the element's top or bottom edge.
function edgePath(w, y, normalY) {
  return { length: w, closed: false, pieces: [w], at: s => ({ x: s, y, nx: 0, ny: normalY }) };
}

// True when (px, py) is inside the rounded rectangle (x, y, w, h, r).
function insideRoundedRect(px, py, x, y, w, h, r) {
  r = Math.min(r, w / 2, h / 2);
  const cx = Math.min(Math.max(px, x + r), x + w - r);
  const cy = Math.min(Math.max(py, y + r), y + h - r);
  return px >= x && px <= x + w && py >= y && py <= y + h && Math.hypot(px - cx, py - cy) <= r + 0.01;
}

// A small repeatable random generator, so stitches land in the same spots on every redraw.
function seededRandom(seed) {
  return () => {
    seed = (seed + 0x6d2b79f5) | 0;
    let t = Math.imul(seed ^ (seed >>> 15), 1 | seed);
    t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t;
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296 - 0.5;
  };
}

/* ---------- Stitch types ---------- */

// Satin and zigzag are the same stitch: the needle swings side to side along the path.
// Satin packs the swings tightly (a solid shiny band); zigzag spaces them out.
// Each side and each corner gets a whole number of swings that start and end on the inner side,
// so every corner gets the same pattern and the outline looks even all the way round.
function swingStitch(ctx, path, layer, shades, spacing, threadWidth, jitter) {
  const half = layer.width / 2;
  const points = [];
  let pieceStart = 0;
  for (const pieceLength of path.pieces) {
    const count = Math.max(1, Math.round(pieceLength / spacing));
    const step = pieceLength / count;
    // Skip the first point after the first piece: it's the same spot the last piece ended on.
    for (let i = points.length ? 1 : 0; i <= count * 2; i++) {
      const p = path.at(pieceStart + (i * step) / 2);
      const side = i % 2 ? half : -half; // even = inner side, odd = outer side
      points.push([p.x + p.nx * side + jitter(), p.y + p.ny * side + jitter()]);
    }
    pieceStart += pieceLength;
  }
  for (let i = 1; i < points.length; i++) {
    drawThread(ctx, points[i - 1][0], points[i - 1][1], points[i][0], points[i][1], shades, threadWidth);
  }
}

// A running stitch: short stitches end to end, with a small gap where the needle went down.
function runStitch(ctx, path, layer, shades, jitter) {
  const stitch = layer.stitch || 7, gap = 2.6;
  const count = Math.max(3, Math.round(path.length / (stitch + gap)));
  const step = path.length / count;
  for (let i = 0; i < count; i++) {
    const a = path.at(i * step), b = path.at(i * step + step - gap);
    drawThread(ctx, a.x + jitter(), a.y + jitter(), b.x + jitter(), b.y + jitter(), shades, 2.1);
  }
}

// Tatami fill: rows of short stitches, each row shifted a third, like brickwork. Clipped to the shape.
function tatamiFill(ctx, shape, layer, shades, jitter) {
  const { x, y, w, h, r } = shape;
  const angle = ((layer.angle ?? 0) * Math.PI) / 180;
  const ux = Math.cos(angle), uy = Math.sin(angle); // along the row
  const vx = -uy, vy = ux;                           // across rows
  const rowGap = 2.4, stitch = 9, cx = x + w / 2, cy = y + h / 2;
  const reach = Math.hypot(w, h) / 2 + stitch;
  ctx.save();
  ctx.beginPath();
  ctx.roundRect(x, y, w, h, Math.min(r, w / 2, h / 2));
  ctx.clip();
  for (let row = -Math.ceil(reach / rowGap); row * rowGap <= reach; row++) {
    const shift = (((row % 3) + 3) % 3) * (stitch / 3);
    for (let u = -reach - shift; u <= reach; u += stitch) {
      const mx = cx + ux * (u + stitch / 2) + vx * row * rowGap;
      const my = cy + uy * (u + stitch / 2) + vy * row * rowGap;
      if (mx < x - stitch || mx > x + w + stitch || my < y - stitch || my > y + h + stitch) continue;
      const ax = cx + ux * u + vx * row * rowGap, ay = cy + uy * u + vy * row * rowGap;
      drawThread(ctx, ax + jitter(), ay + jitter(), ax + ux * (stitch - 1.2), ay + uy * (stitch - 1.2), shades, 2.3);
    }
  }
  ctx.restore();
}

// Satin fill: one long stitch straight across the shape per row. Only good for small shapes.
function satinFill(ctx, shape, layer, shades, jitter) {
  const { x, y, w, h, r } = shape;
  const angle = ((layer.angle ?? 70) * Math.PI) / 180;
  const ux = Math.cos(angle), uy = Math.sin(angle);
  const vx = -uy, vy = ux;
  const cx = x + w / 2, cy = y + h / 2, reach = Math.hypot(w, h) / 2;
  for (let v = -reach; v <= reach; v += 1.7) {
    // Walk along the stitch line to find where it enters and leaves the shape.
    let start = null, end = null;
    for (let u = -reach; u <= reach; u += 0.5) {
      const px = cx + ux * u + vx * v, py = cy + uy * u + vy * v;
      if (insideRoundedRect(px, py, x + 1, y + 1, w - 2, h - 2, r - 1)) { start ??= [px, py]; end = [px, py]; }
    }
    if (start && Math.hypot(end[0] - start[0], end[1] - start[1]) > 1) {
      drawThread(ctx, start[0] + jitter(), start[1] + jitter(), end[0] + jitter(), end[1] + jitter(), shades, 2.2);
    }
  }
}

/* ---------- Putting canvases on the page ---------- */

// Reads the element's corner radius in px ("999px" and "50%" both work).
function cornerRadius(el, w, h) {
  const value = getComputedStyle(el).borderTopLeftRadius;
  const radius = value.endsWith('%') ? (parseFloat(value) / 100) * Math.min(w, h) : parseFloat(value) || 0;
  return Math.min(radius, w / 2, h / 2);
}

// Draws one layer of stitches into its own canvas inside the element.
function drawLayer(el, canvas, layer, seed) {
  const w = el.offsetWidth, h = el.offsetHeight; // layout size, before any rotate()
  if (!w || !h) return;
  const margin = 10;
  // Edge stitches only need a thin strip; everything else covers the element plus a margin.
  const lineY = layer.edge === 'top' ? layer.inset : layer.edge === 'bottom' ? h - layer.inset : null;
  const box = lineY === null
    ? { x: -margin, y: -margin, w: w + margin * 2, h: h + margin * 2 }
    : { x: 0, y: lineY - margin, w, h: margin * 2 };
  const dpr = Math.min(window.devicePixelRatio || 1, 2);
  canvas.width = Math.round(box.w * dpr);
  canvas.height = Math.round(box.h * dpr);
  Object.assign(canvas.style, { left: `${box.x}px`, top: `${box.y}px`, width: `${box.w}px`, height: `${box.h}px` });

  const ctx = canvas.getContext('2d');
  ctx.setTransform(dpr, 0, 0, dpr, -box.x * dpr, -box.y * dpr);
  ctx.lineCap = 'round';
  const shades = threadShades(layer.thread);
  const jitter = (rand => () => rand() * 0.5)(seededRandom(seed));
  const r = cornerRadius(el, w, h);
  const inset = layer.inset || 0;
  const shape = { x: inset, y: inset, w: w - inset * 2, h: h - inset * 2, r: Math.max(0, r - inset) };
  const path = lineY === null
    ? roundedRectPath(shape.x, shape.y, shape.w, shape.h, shape.r)
    : edgePath(w, lineY, layer.edge === 'top' ? -1 : 1);

  if (layer.type === 'satin') swingStitch(ctx, path, layer, shades, 1.9, 2.1, jitter);
  else if (layer.type === 'zigzag') swingStitch(ctx, path, layer, shades, 5.5, 1.8, jitter);
  else if (layer.type === 'run') runStitch(ctx, path, layer, shades, jitter);
  else if (layer.type === 'tatami') tatamiFill(ctx, { x: 0, y: 0, w, h, r }, layer, shades, jitter);
  else if (layer.type === 'satinFill') satinFill(ctx, { x: 0, y: 0, w, h, r }, layer, shades, jitter);
}

// Creates the canvases for every planned element and redraws them whenever the element resizes.
function stitchPage() {
  let seed = 1;
  const jobs = new Map(); // element → its canvases
  for (const [selector, layers] of STITCH_PLAN) {
    for (const el of document.querySelectorAll(selector)) {
      // A more specific rule later in the plan replaces an earlier one for the same element.
      jobs.get(el)?.forEach(({ canvas }) => canvas.remove());
      el.classList.add('is-stitched');
      const firstChild = el.firstChild;
      const canvases = layers.map(layer => {
        const canvas = document.createElement('canvas');
        canvas.className = `stitches stitches-${layer.type}`;
        canvas.setAttribute('aria-hidden', 'true');
        el.insertBefore(canvas, firstChild); // keeps plan order, so fills sit under edges
        return { canvas, layer, seed: seed++ };
      });
      jobs.set(el, canvases);
    }
  }
  const lastSize = new Map();
  const observer = new ResizeObserver(entries => {
    for (const { target: el } of entries) {
      const size = `${el.offsetWidth}x${el.offsetHeight}`;
      if (lastSize.get(el) === size) continue;
      lastSize.set(el, size);
      jobs.get(el).forEach(({ canvas, layer, seed }) => drawLayer(el, canvas, layer, seed));
    }
  });
  jobs.forEach((canvases, el) => observer.observe(el));
}

// The class switches embroidered.css on, so the dashed borders only hide once real thread replaces them.
document.documentElement.classList.add('embroidered');
stitchPage();
