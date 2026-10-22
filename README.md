<p align="center"><img src="Resources/AppIcon-preview.png" width="128" alt="OpenHoop icon: a machine embroidery hoop holding an open ring of satin stitches, with edit points"></p>

<h1 align="center">OpenHoop</h1>

<p align="center"><strong>Open-source machine embroidery for the Mac.</strong><br>
Digitize logos, patches and lettering into stitch files for your embroidery machine.</p>

<p align="center"><a href="https://openhoop.app"><strong>openhoop.app</strong></a> · <a href="https://github.com/EvenDog/openhoop/releases/latest">Download for Mac</a> · <a href="docs/USER-GUIDE.md">User guide</a></p>

![OpenHoop's Guided view: a flower design stitched in the hoop, drawn as real thread, with the sewing order, threads, palette, fabric settings and stitch player around it](docs/screenshot-guided.jpg)

> **In active development.** OpenHoop works end to end, from artwork to a machine file, and its designs have been sewn on a Brother SE600. Stitch settings keep improving from version to version. Test-stitch on scrap fabric before using a design on anything that matters.

## What it does

- **Draw stitches** over your artwork: running stitch (single or bean), satin columns (edge by edge or from one center line), and fills (tatami, contour, radial, wave) with holes.
- **Bring in artwork**: trace a PNG or JPEG, import SVG outlines, or auto-digitize simple artwork into fills.
- **Lettering** with 18 bundled embroidery fonts or any font on your Mac, straight or on an arc, and **monograms**: one to three initials in classic layouts, with ornaments and a satin border.
- **Familiar editing tools**: knife, weld and smooth shapes; branching (touching shapes sew in one go, without trims); stitch angles that turn a fill round a curve; edit individual needle points; align, space evenly, skew, and sew in the order you click.
- **Patch tools**: satin borders and appliqué (placement line, tack-down and satin edge, with stops).
- **Sews well**: underlay, pull compensation, short stitches on curves, split wide satin, start and end points, travel kept inside shapes, and an option to skip stitching under shapes on top.
- **Fabric presets** for woven, knit, towel, denim and felt, with the stabilizer to use, plus a basting box and laydown to hold the fabric.
- **See it before it sews**: Thread View draws every stitch as real thread, a stitch player sews it on screen, and zoom box, real-size zoom, measure and show/hide lists help you check the details.
- **Real threads**: Brother, Janome and Husqvarna Viking color charts built in, or import any brand's chart.
- **Hoops** for Brother, Janome and Husqvarna Viking / Pfaff machines, or any custom size.
- **Machine files**: export PES, PEC, DST, EXP, JEF, VP3 and XXX (each one read back and checked before saving), and import them too.
- **Production worksheet** to print and keep beside the machine: thread steps, stops and an actual-size picture.
- **Made for the Mac**: Guided and Pro views, dockable panels, copy and paste, undo, millimeters or inches, tooltips that explain every tool, and a keyboard shortcut you can change for every command.

## Guided and Pro

**Guided** (above) shows the everyday tools with their names and a plain-English line under each setting. **Pro** puts every tool one click away, adds a precision bar for exact position, size and rotation, and shows the sewing order as a table with stitch counts and live stats. Switch any time with **⌥⌘P**.

![OpenHoop's Pro view in dark mode: two rows of tools, a precision bar for the selected petal, the sewing order as a table with stitch counts, threads in sewing order, the petal's satin settings, and stats along the bottom](docs/screenshot-pro.jpg)

## Download

Get the DMG from the [latest release](https://github.com/EvenDog/openhoop/releases/latest), open it and drag **OpenHoop** onto **Applications**. It's signed and notarized by Apple, so it opens like any other app.

## Requirements

- macOS 14 (Sonoma) or later on an Apple Silicon Mac
- To build: Xcode or the Swift 6 toolchain, and Python 3

## Build and run

```sh
git clone https://github.com/EvenDog/openhoop.git
cd openhoop
./scripts/build.sh      # builds dist/OpenHoop.app (the first run sets up a local Python environment)
open dist/OpenHoop.app
```

Run the tests with `./scripts/test.sh` (build first: some tests use the built app).

## Documentation

- **[User guide](docs/USER-GUIDE.md)**: every tool and setting in detail, file formats, and known limits.
- **[Developing OpenHoop](docs/DEVELOPMENT.md)**: how the code is organized and what the tests cover.

## License

OpenHoop is free software: you can redistribute it and/or modify it under the terms of the GNU General Public License as published by the Free Software Foundation, either version 3 of the License, or (at your option) any later version. It is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See [LICENSE](LICENSE) for the full text.

Copyright © 2026 EvenDog.

Bundled parts keep their own licenses: pyembroidery (MIT), Clipper2 (Boost Software License), the Python runtime (PSF License), and the embroidery fonts in `Resources/EmbroideryFonts` (SIL Open Font License 1.1 or public domain; each font folder has its own `LICENSE`). The thread charts in `Resources/ThreadCharts` are pyembroidery's machine palettes (MIT) and brand charts from Ink/Stitch (GPL-3, like OpenHoop). See `Resources/ThirdPartyNotices.txt`.
