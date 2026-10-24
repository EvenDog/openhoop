# OpenHoop website

The landing page for https://openhoop.app. Plain HTML, CSS and JavaScript; no dependencies or build step.

From the repository root, run:

```sh
python3 -m http.server 4173 --bind 127.0.0.1 --directory website
```

Open http://127.0.0.1:4173. Stop the server with Control-C.

The page uses the real app icon from `Resources/` and fresh captures of the app. The main action downloads the latest DMG; each release updates its link and the version in the fine print.

The headings and text use Bricolage Grotesque, bundled in `assets/fonts/` (SIL Open Font License 1.1; keep `OFL.txt` next to the font file). The only outside request is GoatCounter's visit counter (`gc.zgo.at`, no cookies; the numbers are at openhoop.goatcounter.com), which the footer's privacy line describes.

GitHub Pages publishes this folder automatically whenever a change to `website/` lands on `main` (see `.github/workflows/pages.yml`). The custom domain openhoop.app is set in the repository's Pages settings, with DNS records at the domain registrar.

The hero screenshot shows the app in light and dark mode. The workspace section below uses concise text rather than repeating the screenshot. Both images were captured from the same scratch copy of the Garden Flower design, in a 1452 × 860 pt window scaled to 2048 × 1212, with Thread View on, connectors and underlay hidden, and Petal 1 selected. The pair has identical framing and a fixed display area without cropping, so switching does not move the page.

The hero's Light/Dark toggle switches between the two screenshots. “Inspect stitches” enables a magnifying lens: move a pointer, tap, or focus the image and use arrow keys; Escape turns it off. The lens follows the selected appearance.

The stitch player reads `assets/garden-flower-stitches.json`, exported from the app's `StitchEngine.compile` for the same Garden Flower design. It retains stitch and travel coordinates, thread colors, and sewing order (5,985 stitches). Canvas draws the stitches without connecting travel moves. The web renderer is an illustrative preview, not the native Thread View renderer or a machine timing simulation. Playback is user initiated, supports pause/restart/speed/scrubbing, and pauses when the section or browser tab is hidden. No animation autoplays.

The embroidered look comes from `stitch.js` and `embroidered.css`. The script draws thread onto a `<canvas>` behind each button, patch and badge: zigzag and satin edges, running stitches, and tatami or satin fills. Each stitch is shaded, and its sheen depends on its direction. `STITCH_PLAN` at the top of `stitch.js` lists which element gets which stitches. Each side and corner of an outline gets a whole number of zigzags, so all corners match. Filled buttons stay flat inside so their text is easy to read. The script adds the `embroidered` class to the page; without JavaScript the page keeps its plain dashed borders.
