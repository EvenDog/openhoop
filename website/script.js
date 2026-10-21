const clamp = (value, min, max) => Math.min(max, Math.max(min, value));

// Workspace and appearance toggles preserve each other’s selection.
document.querySelectorAll('[data-preview]').forEach(preview => {
  const surface = preview.querySelector('[data-preview-surface]');
  const light = preview.querySelector('[data-light]');
  const dark = preview.querySelector('[data-dark]');
  const inspect = preview.querySelector('[data-inspect]');
  const lens = preview.querySelector('[data-lens]');
  const lensLight = preview.querySelector('[data-lens-light]');
  const lensDark = preview.querySelector('[data-lens-dark]');
  const hint = preview.querySelector('[data-hint]');
  let theme = 'light';
  let workspace = 'guided';
  let inspecting = false;
  let point = { x: .42, y: .35 };
  let modeRequest = 0;

  function positionLens() {
    const rect = surface.getBoundingClientRect();
    if (!rect.width) return;
    const size = lens.offsetWidth || 190;
    const zoom = rect.width < 600 ? 4 : 2.6;
    const x = point.x * rect.width;
    const y = point.y * rect.height;
    lens.style.left = `${clamp(x - size / 2, 0, rect.width - size)}px`;
    lens.style.top = `${clamp(y - size / 2, 0, rect.height - size)}px`;
    for (const layer of [lensLight, lensDark]) {
      layer.style.backgroundSize = `${rect.width * zoom}px ${rect.height * zoom}px`;
      layer.style.backgroundPosition = `${size / 2 - x * zoom}px ${size / 2 - y * zoom}px`;
    }
  }
  function updateLabels() {
    const view = workspace === 'pro' ? 'Pro' : 'Guided';
    const appearance = theme === 'dark' ? 'Dark' : 'Light';
    preview.querySelector('[data-preview-label]').textContent = `${view} · ${appearance}`;
    preview.querySelector('[data-preview-caption]').textContent = `${view} · ${appearance} mode · Garden Flower`;
  }
  function setTheme(value) {
    theme = value;
    light.hidden = lensLight.hidden = theme !== 'light';
    dark.hidden = lensDark.hidden = theme !== 'dark';
    preview.querySelectorAll('[data-theme]').forEach(button => {
      const selected = button.dataset.theme === theme;
      button.classList.toggle('is-active', selected);
      button.setAttribute('aria-pressed', String(selected));
    });
    updateLabels();
    positionLens();
  }
  function setInspect(enabled) {
    inspecting = enabled;
    inspect.setAttribute('aria-pressed', String(enabled));
    surface.classList.toggle('is-inspecting', enabled);
    lens.hidden = !enabled;
    surface.tabIndex = enabled ? 0 : -1;
    hint.textContent = enabled ? 'Move or tap to explore. Arrow keys move the lens.' : 'Choose your view and lighting.';
    positionLens();
  }
  async function setMode(mode, button) {
    const request = ++modeRequest;
    const urls = ['light', 'dark'].map(theme => `assets/screenshot-${mode}-${theme}.jpg`);
    surface.setAttribute('aria-busy', 'true');
    try {
      // Decode the pair before swapping, so mismatched workspaces never flash.
      await Promise.all(urls.map(src => { const img = new Image(); img.src = src; return img.decode(); }));
      if (request !== modeRequest) return;
      [light.src, dark.src] = urls;
      lensLight.style.backgroundImage = `url("${urls[0]}")`;
      lensDark.style.backgroundImage = `url("${urls[1]}")`;
      const name = mode === 'pro' ? 'Pro' : 'Guided';
      light.alt = `OpenHoop’s ${name} view in light mode showing the Garden Flower design.`;
      dark.alt = `The same Garden Flower design in ${name} view, dark mode.`;
      workspace = mode;
      updateLabels();
      preview.querySelectorAll('[data-mode]').forEach(option => {
        option.classList.toggle('is-active', option === button);
        option.setAttribute('aria-pressed', String(option === button));
      });
      positionLens();
    } catch {
      hint.textContent = 'That view could not load. Please try again.';
    } finally {
      if (request === modeRequest) surface.removeAttribute('aria-busy');
    }
  }
  lensLight.style.backgroundImage = `url("${light.getAttribute('src')}")`;
  lensDark.style.backgroundImage = `url("${dark.getAttribute('src')}")`;
  preview.querySelectorAll('[data-mode]').forEach(button => button.addEventListener('click', () => setMode(button.dataset.mode, button)));
  inspect.addEventListener('click', () => setInspect(!inspecting));
  preview.querySelectorAll('[data-theme]').forEach(button => button.addEventListener('click', () => setTheme(button.dataset.theme)));
  function interact(event) {
    const rect = surface.getBoundingClientRect();
    point = { x: clamp((event.clientX - rect.left) / rect.width, 0, 1), y: clamp((event.clientY - rect.top) / rect.height, 0, 1) };
    if (inspecting) positionLens();
  }
  surface.addEventListener('pointerdown', event => {
    if (!inspecting || event.button !== 0) return;
    surface.setPointerCapture(event.pointerId);
    interact(event);
  });
  surface.addEventListener('pointermove', event => {
    if (inspecting || surface.hasPointerCapture(event.pointerId)) interact(event);
  });
  surface.addEventListener('keydown', event => {
    if (event.key === 'Escape') { setInspect(false); inspect.focus(); return; }
    if (!inspecting || !['ArrowLeft', 'ArrowRight', 'ArrowUp', 'ArrowDown'].includes(event.key)) return;
    event.preventDefault();
    if (inspecting) {
      point.x = clamp(point.x + (event.key === 'ArrowRight' ? .025 : event.key === 'ArrowLeft' ? -.025 : 0), 0, 1);
      point.y = clamp(point.y + (event.key === 'ArrowDown' ? .025 : event.key === 'ArrowUp' ? -.025 : 0), 0, 1);
      positionLens();
    }
  });
  new ResizeObserver(positionLens).observe(surface);
});

// Millimeter coordinates and sewing order are exported from OpenHoop's stitch engine.
async function initStitchPlayer() {
  const player = document.querySelector('[data-stitch-player]');
  const canvas = player.querySelector('canvas');
  const ctx = canvas.getContext('2d');
  const play = player.querySelector('[data-play]');
  const restart = player.querySelector('[data-restart]');
  const progress = player.querySelector('[data-progress]');
  const speed = player.querySelector('[data-speed]');
  const count = player.querySelector('[data-stitch-count]');
  const threadName = player.querySelector('[data-thread-name]');
  const status = player.querySelector('[data-player-status]');
  try {
    const response = await fetch('assets/garden-flower-stitches.json');
    if (!response.ok) throw new Error('Stitch data unavailable');
    const data = await response.json();
    if (!ctx) throw new Error('Canvas unavailable');
    const segments = [];
    let previous = null;
    for (const command of data.commands) {
      const [x, y, thread, stitch] = command;
      if (stitch) segments.push({ x, y, thread, from: previous || [x, y] });
      previous = [x, y];
    }
    if (segments.length !== data.stitchCount) throw new Error('Incomplete stitch data');
    const xs = data.commands.map(c => c[0]);
    const ys = data.commands.map(c => c[1]);
    const bounds = { minX: Math.min(...xs), maxX: Math.max(...xs), minY: Math.min(...ys), maxY: Math.max(...ys) };
    const scale = Math.min(790 / (bounds.maxX - bounds.minX), 600 / (bounds.maxY - bounds.minY));
    const centerX = (bounds.maxX + bounds.minX) / 2;
    const centerY = (bounds.maxY + bounds.minY) / 2;
    const xy = (x, y) => [500 + (x - centerX) * scale, 390 - (y - centerY) * scale];
    const key = document.querySelector('[data-thread-key]');
    data.threads.forEach(thread => {
      const swatch = document.createElement('span');
      const dot = document.createElement('i');
      dot.style.backgroundColor = thread.color;
      swatch.append(dot, document.createTextNode(thread.name));
      key.append(swatch);
    });
    let shown = 0;
    let position = segments.length;
    let running = false;
    let frame = 0;
    let lastTime = 0;
    function draw(target) {
      target = clamp(Math.floor(target), 0, segments.length);
      if (target < shown) { ctx.clearRect(0, 0, 1000, 800); shown = 0; }
      ctx.lineCap = 'round';
      for (let i = shown; i < target; i++) {
        const s = segments[i];
        const a = xy(...s.from), b = xy(s.x, s.y);
        ctx.beginPath(); ctx.moveTo(...a); ctx.lineTo(...b);
        ctx.strokeStyle = '#31302224'; ctx.lineWidth = scale * .36; ctx.stroke();
        ctx.strokeStyle = data.threads[s.thread].color; ctx.lineWidth = scale * .23; ctx.stroke();
        ctx.strokeStyle = '#ffffff35'; ctx.lineWidth = scale * .065; ctx.stroke();
      }
      shown = target;
      progress.value = target;
      count.textContent = `${target.toLocaleString()} / ${segments.length.toLocaleString()} stitches`;
      const thread = target ? data.threads[segments[target - 1].thread] : null;
      threadName.textContent = target === segments.length ? 'Design complete' : thread ? thread.name : 'Ready for the first stitch';
    }
    function setRunning(value) {
      running = value;
      cancelAnimationFrame(frame);
      play.textContent = running ? 'Pause stitching Ⅱ' : position >= segments.length ? 'Watch it stitch ▷' : 'Resume stitching ▷';
      status.textContent = running ? 'Stitch preview playing.' : position >= segments.length ? 'Stitch preview complete.' : 'Stitch preview paused.';
      if (running) { lastTime = 0; frame = requestAnimationFrame(tick); }
    }
    function tick(time) {
      if (!running) return;
      if (lastTime) position = Math.min(segments.length, position + Math.min(time - lastTime, 80) / 1000 * Number(speed.value));
      lastTime = time;
      draw(position);
      if (position >= segments.length) setRunning(false);
      else frame = requestAnimationFrame(tick);
    }
    play.addEventListener('click', () => {
      if (!running && position >= segments.length) { position = 0; draw(0); }
      setRunning(!running);
    });
    restart.addEventListener('click', () => { position = 0; draw(0); setRunning(true); });
    progress.addEventListener('input', () => { position = Number(progress.value); draw(position); setRunning(false); });
    document.addEventListener('visibilitychange', () => { if (document.hidden && running) setRunning(false); });
    new IntersectionObserver(entries => { if (!entries[0].isIntersecting && running) setRunning(false); }).observe(player);
    progress.max = segments.length;
    play.disabled = restart.disabled = progress.disabled = false;
    draw(position);
  } catch (error) {
    count.textContent = 'The stitch preview couldn’t load. Refresh to try again.';
    status.textContent = count.textContent;
  } finally {
    player.setAttribute('aria-busy', 'false');
  }
}
initStitchPlayer();
