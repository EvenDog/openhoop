# OpenHoop user guide

How to digitize with OpenHoop, from artwork to a file your embroidery machine can sew. For an overview and how to build the app, see the [README](../README.md).

**Contents:** [Getting started](#getting-started) · [Bringing in artwork](#bringing-in-artwork) · [Drawing stitches](#drawing-stitches) · [Editing shapes](#editing-shapes) · [Viewing and measuring](#viewing-and-measuring) · [Lettering](#lettering) · [Patches: borders and appliqué](#patches-borders-and-appliqué) · [Threads and fabric](#threads-and-fabric) · [Hoops](#hoops) · [Checking and saving for the machine](#checking-and-saving-for-the-machine) · [Importing machine files](#importing-machine-files) · [Making it yours](#making-it-yours) · [Keyboard shortcuts](#keyboard-shortcuts) · [Known limits](#known-limits)

## Getting started

Open `dist/OpenHoop.app` after building it. To look around first, choose **File → Open Sample Design** or **File → Open Satin + Fill Sampler**. The app carries its own file converter, so you don't need to install Python to use it.

> OpenHoop has been built and tested on an Apple Silicon Mac. Its stitches have not yet been sewn on a real machine, so test-sew on scrap fabric first.

**The window:**
- **Tool strip** (under the toolbar): tools grouped as *Pick & shape*, *Stitch*, *Add* and *View*, each with its key. Some tools share a slot (Fill and Hole; Text, Satin border, Appliqué and Auto-digitize); click the slot's arrow to pick one. Tools that can't be used yet are dimmed.
- **Canvas:** the hoop with your design. Scroll to pan, pinch or Option-scroll to zoom, **⌥0** to fit the hoop. More ways to look: [Viewing and measuring](#viewing-and-measuring).
- **Panels:** Sewing order, Properties, Design (fabric and hoop), Reference image, Threads and Stitch player.
- **Status bar:** messages, and a **Ready to save** check that turns orange with a short reason when something needs fixing before export.

**Guided and Pro views.** Same features, two layouts; switch with **⌥⌘P** or the **Guided | Pro** toggle in the toolbar. Pro shows every tool as its own button on a walnut band, two rows across the top; **Settings › General › Pro view tools** moves them to a rail down the left side instead.
- **Guided** (the default) shows the everyday settings with a plain-English line under each and folds the rest under **More settings**.
- **Pro** shows everything at once: every tool in one row, a precision bar for exact position, size and rotation, compact Properties, a sewing-order table with stitch counts, and live stats in the status bar. Explanations become tooltips.

**Not sure what something does?** Rest the pointer on any tool, button or setting: a tooltip says what it does, with its key.

**Escape** means "done": it returns to the Select tool, stops the stitch player and shows the whole design. While drawing, Escape cancels the path instead.

## Bringing in artwork

**Trace over an image.** **⌘I** imports a PNG or JPEG as a reference image (it never sews). Set its size in the Reference image panel, and drag the **Opacity** slider there to fade it (the image changes as you drag; letting go is one step to undo). Press **⌥D** (or **Move & size on canvas**) to move it or resize it from a corner (Shift stretches it); press Escape when done. **D** shows or hides it.

**Put the image between layers.** The reference image has its own row in the Sewing order, at the top to begin with (under everything). Its **▲ ▼** arrows move it one step at a time: the steps listed above it are drawn under the image and the ones below it on top. So you can digitize the background, move the image below it, and trace the next layer over it. Grouped objects (such as the letters of a word) count as one step. New objects go at the end of the list, over the image. It only changes what you see: the image is never sewn.

**Import SVG outlines.** **⇧⌘I** imports an SVG as unstitched outlines at its real size. Select an outline and choose **Running Stitch** or **Tatami Fill** in Properties to make it sew. Curves keep their Bézier handles; strokes come in as center lines. The import report lists anything it couldn't use. [What SVG content is supported](#svg-support).

**Auto-digitize.** **⌥M** traces the reference image into fills. Choose how many colors to reduce it to (2–8, counting the background), whether to skip the background, and the smallest part to keep. You'll see your image beside the traced result before anything is added. Each color patch becomes a tatami fill with its holes, placed over the image, largest colors first. Thin lines and small text trace poorly; redraw those as satin or running stitch.

## Drawing stitches

All drawing tools work the same way: **click** for a corner, **press and drag** to pull out a curve, **secondary-click** for an automatic smooth point. **Return** finishes, **Escape** cancels, **Delete** removes the last point. Projects remember an unfinished path, so you can carry on after reopening.

### Running stitch (⇧N)

A line of stitches along your path. Set **Stitch length** in Properties.

**Bean stitch:** set **Passes** to **Bean ×3** or **Bean ×5** for a bold outline. Each stitch is sewn forward, back and forward again. Stitch lengths of 2.5–3.5 mm suit it.

### Satin columns (⇧A)

Smooth, shiny columns for borders, outlines and lettering. Two ways to make one:
- **Edge by edge:** with **⇧A**, click pairs of points, one on each side of the column, all the way along; press Return after at least two pairs.
- **From a center line (⇧I):** draw a running line down the middle, set **Satin width** in Properties (0.8–10 mm), then press **⇧I** (or F6) or **Make satin column**. Sharp turns are rounded just enough for the satin to turn. Turns too tight for the width are explained and the line is left alone.

Settings: **Row spacing**, **Compensation** per side (extra width because thread pulls the fabric in), **Compensation % of width** (More settings; in Pro, **% of width**), and **Maximum stitch**. The percentage adds a share of each stitch's own width on top, so wide parts of a satin get more: new satins start at 3%, so a 2 mm part gets 0.26 mm per side and a 6 mm part 0.38 mm. It's a starting value to tune after a test sew-out. Two helpers, on for new satins:
- **Short stitches on curves:** on the inside of a curve, every other stitch stops short so the thread doesn't pile up.
- **Split wide satin:** stitches longer than the maximum are split into shorter, staggered ones instead of the column being refused.

### Fills (F3)

Trace a closed outline and press Return. Settings: **Row spacing**, **Stitch length**, **Angle** and **Expansion**. **Fill style** sets how the rows are laid:

| Style | What it looks like |
| --- | --- |
| **Tatami** | Straight rows (the default) |
| **Contour** | Rings following the outline inward, sewn as a few long spirals |
| **Radial** | Stitches fanning out from a center point; drag the **Center** dot on the canvas to move it |
| **Wave** | Rows that ripple, with a wave height and length |

**Holes:** select a fill and press **⌥H** to trace a hole (or use **+** and **−** next to Holes).

**Cut out shapes sewn on top** (off unless you tick it): the fill skips the area that later fills and satins cover, so the hidden part isn't stitched twice. It still sews 1 mm under their edges so no gap shows, and the shape on top can be moved freely; the fill fills back in.

**Stitch angles (⌃H / ⌃⇧H)** (in the Fill slot, and **Stitch angles · Add…** in Properties): select one tatami fill, choose **Add Stitch Angles**, and click two points across it for each line. The stitches run along each line and turn gradually from one line to the next, so a fill can follow a curved shape like a satin column does. Lines don't need to end exactly on the edge: each is stretched to it. On a ring (a fill with a hole), draw each line from the outside edge to the hole's edge, and the stitches turn all the way round. Where the turning crowds the rows together, on the inside of a bend, rows stop short so thread doesn't pile up. To adjust a line, select the fill, press **H** (Edit nodes) and drag the line: drag one of its square ends to swing that end, or the middle to slide the whole line; the stitches follow when you let go. While you drag (or draw a new line), its angle shows beside the pointer, counted like the fill's Angle. To delete one line, click it (it turns orange) and press **Delete**; this works with Edit nodes or either angle tool, and deletes just the line, not the fill. **Remove Stitch Angles** takes away each line you click; **Remove all** in Properties brings back straight rows. The lines show while the fill is selected with Edit nodes or either tool.

### Shapes and the stitch picker

Pick a stitch first, then draw. The **Shape** group in the tool strip holds them, and while one is on, a **Next shape** bar at the top of the canvas shows its choices. Your choices are remembered.

| Tool | How to draw | Stitch it gets |
| --- | --- | --- |
| **Digitize Open Shape (⌥O)** | Click corners, drag or secondary-click for curves, Return to finish | Running, Bean (triple run) or Satin line (as wide as **Width** in the bar) |
| **Digitize Closed Shape (⌥S)** | The same, and the outline closes itself | A **Fill** (Tatami, Contour, Radial, Wave or None) and an **Outline** (Running, Bean, Satin line or None) |
| **Freehand Open Shape (⌥⇧O)** | Press and drag; the line follows the pointer and is smoothed when you let go | The Open Shape stitch |
| **Freehand Closed Shape (⌥⇧S)** | The same, and the outline closes itself when you let go | The Closed Shape stitches |
| **Rectangle (⌥R)** | Drag corner to corner; set **Corners** for rounded ones | The Closed Shape stitch |
| **Ellipse (⌥J)** | Drag out from the center | The Closed Shape stitch |
| **Basic Shapes (⌥B)** | Pick Polygon (3–12 sides), Star (4–12 points, shallow to deep), Heart or Arrow, then drag | The Closed Shape stitch |

With both a fill and an outline, the shape becomes two objects, grouped so they move together: the fill, then the outline sewn on top of its edge (a satin outline is centered on the edge, like a satin border). When you pick a shape tool, the status line says what the next shape will get.

While dragging a shape, hold **⌘** to keep it even (a square, circle or regular star) and **⇧** to draw it out from where you started. A shape is a normal outline: reshape it with **H**, and change its stitch in Properties.

### Underlay and finishing

**Underlay** is a quick first layer that holds the fabric still. Satins: **Auto** (the default for new satins, borders and appliqué edges), center run, inset edge or inset zigzag. Auto picks from the satin's average width each time it sews, so it follows reshaping: a center run under 2 mm, an inset edge run up to 4 mm, and an edge run then a zigzag above that (from 2 mm on knit and towel). These steps are starting values to tune after a sew-out. Fills: inset edge, or edge plus a sparse fill. **U** turns it on or off; **⇧U** shows it on the canvas.

Satins with a chosen (not Auto) underlay can have a **second underlay** (More settings in Guided, the Underlay section in Pro). It sews after the first, back along the column, so the top stitches start where it ends. Common pairs are center run then zigzag, or edge run then zigzag for wide satins. Both layers use the same inset and spacing. Turning underlay off (or picking the same style for the first) clears the second.

**Finishing:** **Tie in** and **Tie off** add tiny locking stitches, **Trim after** cuts the thread before the next part, and **Stop after** pauses the machine.

**Start & end points (⌥E):** select an object, press **⌥E**, click where it should start; Option-click where it should end. Each object has its own points: with a group selected (such as a laydown's parts or a word's letters), click on the part you mean, even one lying under other objects. The first stitch goes exactly on the start point and the last exactly on the end point; a point off the shape moves to the nearest place just inside it. Fills run inside the shape from the start point to where they begin, hidden under the stitching, and are sewn toward the end point so the last row finishes right beside it. Lines and satins sew from whichever end is nearer the start point; with only an end point set, they finish at the end nearer it (closed outlines start and finish beside it). A line or satin can start part way along. Click on the line, or on the satin: the needle starts there and runs to the nearer end, then sews the whole thing from that end. On a satin the run goes along the middle of the column, hidden under the satin; on a line it goes back through the line's own needle holes, so that stretch is sewn twice. (A start point more than 1 mm off a line just picks the nearer end.) A satin can also end part way along: it's then sewn in two halves that meet at the end point (the needle runs hidden through the unsewn half between them), so a faint join may show there on shiny thread. A line can end part way along too: after the line, the needle comes back along it through its own holes to the end point. Closed outlines and satin borders start right beside their start point and finish at their end point: an outline carries on round, the shorter way, to the end point; a border is sewn the long way round to the end point, then the needle runs hidden back through the rest and sews it to finish there. An end point within 1 mm of an end just finishes at that end, and the End marker shows there. **Auto for all** starts each object where the previous one ends, to cut down on travel.

## Editing shapes

- **Select (O):** click to select, Shift-click to add more, drag to move. In the sewing order list, Shift-click selects everything between the last object you clicked and this one, and ⌘-click adds or removes one. Arrow keys nudge (1 mm; change it in Pro's precision bar).
- **Edit nodes (H):** drag points and their curve handles. Click a selected object's edge to add a corner point there (keep holding to drag it into place), or secondary-click the edge to add a curve point: the edge stays as it is until you drag the point, then bends smoothly through it. On a satin, either adds a new rung. A drag that would leave the shape unable to sew (such as a satin rung crossing a rail, or a fill's edge crossing itself) goes back, and the status line says why. While you drag, the shape turns red and the status line warns you before you let go. To switch a point between a sharp corner and a smooth curve, click it and use the **Corner | Smooth** switch that appears above the canvas, press **Space**, secondary-click it, or choose **Digitize › Pick & Shape › Corner / Smooth Point**; Option-drag moves one handle on its own. **⌥⇧I** inserts a point under the pointer; **⇧⌫** deletes the selected one. On a tatami or wave fill, a line across the shape shows its stitch angle: drag either square end to turn the stitches (the angle shows beside the pointer, in whole degrees), and they follow when you let go. Drag the line itself to move it anywhere handy: it still crosses the whole shape, turns around where you put it, and moving it never changes the stitches.
- **Stitch errors:** if an object can't be sewn, it's outlined in red and the status bar says why. Everything else keeps showing up-to-date stitches, but export waits until the error is fixed.
- **Arrange:** mirror, rotate, resize, duplicate (**⌘D**), sew earlier or later, hide and lock (**K**). Hidden objects still sew; hiding only declutters the canvas.
- **Sequence by selection order:** Shift-click objects on the canvas (or ⌘-click them in the sewing order list) in the order they should sew, then choose **Sew in click order** (Properties, with several selected), the numbered-list button in Pro's precision bar, or **Edit → Sequence by Selection Order**. They sew one after another in that order, starting where the earliest of them sewed; everything else keeps its place.
- **Skew:** type an angle in **Skew** (Pro's precision bar) or **Skew by °** (Guided, under More settings) and press Return to lean the selection sideways, like italics: positive leans the top to the right. Fill rows lean along.
- **Align and space:** with several objects selected, the row of small buttons in Properties lines them up by their left edges, centers or right edges, tops, centers or bottoms, or both centers. They line up with **the object you select last**, which stays put. **Space evenly across / down** (three or more) leaves the outer two in place and makes the gaps between neighbours equal. A group moves as one block, and locked objects stay put. These are in the Edit menu too.
- **Group (⌘G / ⇧⌘G):** groups move, turn, resize and recolor together. Option-click picks one member.
- **Copy, cut and paste (⌘C, ⌘X, ⌘V):** within a design or into another. Pasted objects go at the end of the sewing order, where they were copied from; pasting again into the same design shifts each copy 3 mm.
- **Convert:** turn a running outline into a fill, or outlines back into running stitch.
- **Edit Stitches (E)** (in the Edit nodes slot): select one line, satin or fill and press **E**. Its needle points show as small squares, and a bar at the top of the canvas says you're in Edit Stitches (its **Done** button, or Escape, leaves it). Click one to select it (Shift- or ⌘-click adds more, or drag a box around several), drag to move them, press **Delete** to remove them, and Option-click on a stitch to add a needle point there. Escape when done. The object keeps its settings and Properties says **Stitches edited by hand**. The edits sew until you change its shape or a setting: then fresh stitches replace them and the status bar says so (Undo brings them back). Moving, turning, mirroring, resizing or skewing the object keeps them. **Regenerate** in Properties throws them away on purpose.
- **Knife (⌥K)** (shares a slot with Weld): click points across what to cut and press **Return**. It cuts the selected objects, or everything on show if nothing is selected. Each piece keeps the stitch settings and color: fills and closed outlines split into the areas on either side of the line, satins are cut across the column, and lines are cut where the knife crosses them. Cutting a border once opens the ring. The line has to run right across a shape, from outside to outside. The Knife stays on for the next cut; Escape when done.
- **Branching (I)** (in the Knife slot, or **Branch** in Properties with several selected): select two or more fills, satins or lines, press **I**, then click where the branch should start and where it should end (**Return** at either step lets OpenHoop choose). The objects are put in order (each next is the nearest one left), take the first one's thread, are grouped, and each starts where the one before finished. Where they touch or overlap, the needle travels from one to the next inside them instead of trimming, so lines that meet (a tree's branches) or touching shapes sew in one go; where they're apart, it ties off and trims as usual. An object whose stitches you edited by hand keeps them (and its own start and end); the next object starts where those stitches finish. Ungroup to sew them separately again.
- **Weld (⌥W):** select overlapping fills, closed outlines or satins and weld them into one fill (also **Weld** in Properties). It takes the settings of the topmost object (the one sewn last) and its place in the sewing order; if that's a satin or outline, you get a fill in its color. Parts that don't touch become separate fills. Pieces cut with the Knife weld back together.
- **Smooth Shapes (⌥N)** (in the Edit nodes slot): removes the nodes that barely shape the selected outlines, each within 0.2 mm, which tidies shapes after Knife, Weld or an SVG import. Satins lose a rung at a time. Press again to remove more; Undo if it went too far.
- **Undo** (⌘Z) and **Redo** (⌘Y or ⇧⌘Z) work on whole edits; each drag is one step.

## Viewing and measuring

**Zoom** (in the View group's zoom slot, and the View menu):
- **Zoom box (B):** drag a box around the part to look at and it fills the canvas; a click zooms in 2× around the pointer. Then you're back in the tool you had, even in the middle of drawing a path. Escape cancels.
- **Real size (1):** shows the design at its actual size on your screen, worked out from the size your display reports to macOS, so hold a ruler up to it to judge small text.
- **Zoom to design (0):** fills the view with the whole design.
- **Zoom to selected (⇧0):** frames the selection.
- **Fit hoop (⌥0), zoom in (Z), zoom out (⇧Z).**

**Show** (the list next to the zoom slot, and the View menu) switches parts of the view on and off. These only change what you see: everything still sews.
- **Stitches (S)** and **Outlines of every object (L)**: hide the stitches and show the outlines to check shapes against the artwork.
- **Connectors (⇧C):** the dashed travel moves between parts. They show in the stitch view and are hidden in Thread View until you switch them.
- **Needle points (.)** and **Underlay (⇧U).** Needle points show as small dots once you zoom in (300% or more), in Thread View too.
- **Hide unselected objects (⇧S):** keeps only the selection in view, to work on one part of a busy design. Clicking empty canvas shows everything again until you select something else.
- **Rulers & guides (⌘R):** hides the rulers and guide lines for a clear canvas. Your guides are kept and come back with the rulers.

**Measure (M)** (in the Pan slot): drag from one point to another to read the distance (in mm or inches) and its angle (counted counterclockwise from pointing right, like Rotate). The line stays until you measure again or change tools. Snap to grid applies.

**Rulers:** a thin line on each ruler follows the pointer, so you can read where it is at a glance.

**Guides:** drag down from the top ruler for a side-to-side guide line, or right from the left ruler for an up-and-down one; the position shows beside the pointer while you drag. With Select, drag a guide (where no object is under the pointer, the pointer turns ↔ or ↕) to move it, or back onto its ruler to remove it. **View → Clear Guides** removes them all. With **Snap to grid** on, points and drags close to a guide land on it. Guides are saved with the design but never sewn.

**Grid color:** the grid draws light lines on dark cloth and dark lines on light cloth. To pick your own color and strength, open **Settings → General → Grid lines** and choose **Custom color** (the color picker's opacity slider sets how strong the lines are).

## Lettering

Press **A** (or **Add → Text**) to add lettering.

- **Embroidery fonts** (recommended): 18 hand-digitized satin fonts, from 2.8 mm tiny text to 140 mm monograms. Each shows its stitched preview and the size range it was made for. **Font credits…** lists each font's license.
- **System fonts:** any font on your Mac, as fills or outlines, 3–200 mm tall. Below about 10 mm, use an embroidery font instead.
- **Several lines:** up to 10, aligned left, center or right, with adjustable line spacing.
- **Shape:** **Straight**, **Arch up** or **Arch down**, with the arc's radius.
- **Edit it later:** double-click the letters (or press **⌥L**) to change the text, font, size or shape. If you had reshaped any letters by hand, you're warned that updating rebuilds them.

### Monograms (⌥⇧M)

**Add Monogram…** (in the Add slot, next to Text): type one to three initials and pick a font (the embroidery fonts, or classic Mac fonts such as Didot and Baskerville, converted to fill), the height of the tallest initial, and a layout:
- **Big middle:** the middle initial (usually the surname) larger, the others smaller on either side.
- **Side by side:** all the same size in a row.
- **Stacked:** one above the other.
- **Diamond:** a tall middle with shorter initials close in on either side, to suit a diamond border.

Add **ornaments** either side (swirls in bean stitch, leaves or dots, drawn for OpenHoop) and a **border** (circle, oval, rounded rectangle, diamond or shield) sewn as satin, with its width and the gap to the monogram. The preview updates as you go. The monogram is added as one group in the current thread, centered in the hoop. **Double-click** it (or **Edit monogram…** in Properties) to change anything; it's rebuilt in the same place. Embroidery fonts are only digitized for certain sizes, so an initial that would fall outside them is kept within, and the dialog says so. Ungrouping turns a monogram into plain shapes.

## Patches: borders and appliqué

**Satin border (⇧⌘O).** Select a fill or closed outline to add a satin column around its outside edge (1–8 mm, default 3), like the edge of a patch. Corners are rounded just enough for the satin to turn, and shapes too thin for the width are explained.

**Appliqué (F7 or ⌥Q).** Sews a piece of fabric on instead of filling the shape with stitches. The shape becomes three grouped parts, in its own thread:
1. **Placement line**, then the machine stops: lay your fabric over the line.
2. **Tack-down** (an open zigzag, or a running line) holds the fabric, then it stops: trim the fabric close to the stitching.
3. **Satin edge** (2.5–8 mm) covers the cut edge.

## Threads and fabric

**Holding the fabric** (in the Design panel):
- **Basting box:** long running stitches around the design, sewn before everything else in the design's first thread (so the machine doesn't stop), that hold the fabric to the stabilizer. Pull them out after sewing. Set how far outside the design it runs with **Margin** (5 mm to start). It stays inside the hoop: on a rectangular hoop it's cut back to the edge, and on an oval one the margin shrinks until the corners fit.
- **Laydown (⌥⇧L, or Add laydown…):** a light, open fill under the whole design (or the selection) that flattens the pile of towels, fleece and velvet so stitches don't sink in. The dialog sets how far it reaches past the edge, row spacing, stitch length, angle, one layer or two crossed ones, and its thread (one matching the fabric hides best), with a preview. Shapes close together share one laydown, which also covers the gaps between them. It's added as a group that sews before what it lies under; change its spacing or angle in Properties afterwards like any fill.

**Thread colors.** Click a color in the Threads panel to set the current thread; anything selected changes to it too.

**Real threads (⌥T).** **Choose Thread from Chart** picks threads by brand and color number:
- **Current thread and selection:** the closest matches are listed first, or search by name or number.
- **Every thread in the design:** previews each thread beside its closest chart thread before **Match All** changes them. A muted color may match a gray if the chart has nothing closer.
- Built-in charts: **Brother**, **Janome** and **Husqvarna Viking** machine palettes. Their numbers are each machine's own color numbers, which may differ from the number on the spool.
- For real spool numbers, **Import Chart…** adds any GIMP palette (`.gpl`) file, such as the Madeira, Isacord, Robison-Anton and other brand charts Ink/Stitch publishes (github.com/inkstitch/inkstitch, `palettes` folder).
- A chart thread's brand and number appear in the Threads panel, on the worksheet, in the thread list and in PES files.

**Fabric type** (Design panel): **Woven**, **Knit**, **Towel / fleece**, **Denim / canvas** or **Felt / patch twill**. It sets starting density, compensation and underlay for new fills and satins, and names the stabilizer to use. If the design already has shapes, you're asked whether to update them. These are rules of thumb; adjust them after a test sew-out.

| Fabric | Main changes | Stabilizer |
| --- | --- | --- |
| Woven | the app's standard settings | tear-away |
| Knit | lighter fills (0.45 mm), more compensation (0.35 mm), more satin underlay* | cut-away |
| Towel / fleece | denser fills (0.35 mm), more satin underlay* | cut-away, plus water-soluble topping |
| Denim / canvas | less compensation (0.15 mm) | tear-away |
| Felt / patch twill | least compensation (0.10 mm), light fill underlay | tear-away, or none |

\* Satins on Auto underlay stay on Auto and get an edge run plus zigzag from 2 mm wide; satins with a chosen underlay get an inset zigzag.

**Fabric color** (Design panel) only changes how the design looks on screen.

## Hoops

Choose your hoop under **Sewing area** in the Design panel:

| Brand | Hoops |
| --- | --- |
| Brother | 4 × 4, 5 × 7, 6 × 10, 8 × 8, 8 × 12, 9.5 × 14 in |
| Janome | SQ14, RE20b, SQ20b, SQ23, RE28b, RE36b |
| Husqvarna Viking / Pfaff | 100 × 100, 115 × 120, 200 × 200, 150 × 240, 200 × 260, 200 × 360 mm |

Hoops are listed upright; **Turn sideways** swaps width and height. You can also type any size or choose an oval. New designs start in the hoop you picked last. Stitches outside the hoop are refused at export.

## Checking and saving for the machine

**Thread View.** Press **T** (or the Thread View button under View) to switch between Thread View and the stitch view. Thread View draws each stitch as its own strand of thread, 0.45 mm wide, dark where it dives into the cloth and bright in the middle, so you see roughly how the design will sew out; travel moves between pieces and needle points are hidden. The stitch view draws thin lines and shows travel moves dashed, which is handier for checking the sewing path. The app remembers which one you used last.

**Stitch player.** Press **Space** or **⇧R** (or ▶) to watch the design sew, and **Home** to go back to the start; drag the slider to step through it. **.** (period) shows the needle points. **Speed** sets how many stitches it sews per second (1–5,000; 120 to start, and back to 120 each time the app opens): drag its slider to slow down or speed up while it plays, or type an exact number in the box. A machine sews about 12. In Pro, the speed slider and box sit next to the mini player.

**Save your work** as a `.stitchproj` project; that's what you keep editing. Machine files are output only.

**Export:**
- **⌘E** saves PES for Brother machines. **⇧E** chooses another format: PES, PEC, DST, EXP, JEF, VP3 or XXX.
- Every export is read back and checked before saving: needle positions, colors, stops, travel and hoop bounds. If anything changed, nothing is saved.
- **File → Export Thread List…** saves a spreadsheet (CSV) of the thread order, with brands and numbers. Use it for DST and EXP, which store no colors.

**Production worksheet (⌘P).** A page to keep beside the machine:
- size, stitch count, thread steps, trims, stops, and the sewing time at your machine's speed (set it in the preview)
- the fabric and its stabilizer
- a picture of the design, **actual size** when it fits (a 10 mm bar checks the printer kept 100%), so you can hold it up to the garment
- a table of thread steps with tick boxes, marking each **Then stop**

Print it, or choose **PDF** in the print dialog to save it.

## Importing machine files

**⇧⌘O** imports PES, PEC, DST, EXP, JEF, VP3 or XXX into the open design, at its original size and place. Each thread change becomes a block you can move, turn, mirror, recolor, reorder or combine with new work. These are finished stitches, not editable shapes: you can't edit their points or change their stitch type, and resizing changes their density. Colors the file doesn't store come in as **Unknown thread**; pick the right thread for each block.

## Making it yours

**Keyboard shortcuts.** **⌘,** → **Keyboard Shortcuts**: search for any command and click **Record** to give it a key. Commands can have several shortcuts; clashes are flagged, and you can save named profiles and import or export them.

**Panels** work like Photoshop's:
- Drag a panel's tab onto another panel to join it, to the top or bottom of a group to stack it, onto the canvas to float it, or to the canvas edge to dock it.
- The **Window** menu shows or hides each panel, and saves, recalls and resets layouts.
- Guided and Pro each keep their own layout.

**Tabs:** designs open as tabs in the window's title bar; **⌘N** or **+** starts a new one. An orange dot marks unsaved changes. **⌘W** or the tab's **×** closes a design (asking to save first); **⌃⇥** and **⌃⇧⇥** (or **⇧⌘]** and **⇧⌘[**) move between tabs. Closing the window closes each design in turn.

**Light or dark:** **Settings → General → Appearance** keeps OpenHoop light or dark, or **Match system** follows the Mac's own setting (the default).

**Around the hoop:** **Settings → General** sets the color behind the hoop, or follows light and dark mode.

**Grid & snap:** **Settings → General → Grid & snap** sets how far apart the grid's lines are (5, 10 or 20 mm, or ¼, ½ or 1 in; half that when zoomed in) and the steps Snap moves points to (0.5, 1 or 2 mm, or 0.025, 0.05 or 0.1 in).

**New designs and objects:** **Settings → Designs** sets what things start with:
- **New designs:** the fabric type, and the hoop: the one you used last, or one you pick there (then choosing another hoop for one design doesn't change it).
- **New objects:** the stitch length of lines and fills, the fill angle, and satin compensation, for shapes you draw. Row spacing, pull compensation and underlay come from the design's fabric type; lettering, monograms and imports keep their own settings.
- **Machine:** how many stitches a minute your machine sews, for the time estimate in the status bar and on worksheets.

**Millimeters or inches:** **Settings → General → Units**, or **View → Use Inches**, switches how sizes and positions are shown and typed: object, design and hoop sizes, positions, start and end points, the rulers, guides, Measure, nudge, lettering and monogram height, and the worksheet. In inches the grid draws a line every ½ in (¼ in zoomed in) and Snap rounds to 0.05 in, unless Grid & snap is set finer or coarser. Stitch settings (stitch length, row spacing, satin and border widths, underlay, compensation) always stay in millimeters, as digitizers usually give them. Designs are saved the same either way, so switching never changes a design.

**Toolbar:** secondary-click it to customize.

## Keyboard shortcuts

These are the starting keys; every one can be changed. Tools on a function key also have a letter, since Mac keyboards need **fn** for F1–F12.

| Tools | | Commands | |
| --- | --- | --- | --- |
| Select | O | Undo / Redo | ⌘Z / ⌘Y |
| Edit nodes (Reshape) | H | Cut / Copy / Paste | ⌘X / ⌘C / ⌘V |
| Pan | P | Duplicate | ⌘D |
| Running stitch | ⇧N or F8 | Group / Ungroup | ⌘G / ⌘U |
| Satin column | ⇧A or F4 | Lock | K |
| Satin column from line | ⇧I or F6 | Mirror across / up and down | ⌘1 / ⌥1 |
| Fill | F3 or ⌥F | Select all | ⌘A |
| Convert to fill | ⇧M | New / Open / Save | ⌘N / ⌘O / ⌘S |
| Lettering / edit lettering | A / ⌥L | Import image / SVG / machine file | ⌘I / ⇧⌘I / ⌥⌘O |
| Appliqué | F7 or ⌥Q | Export PES / choose format | ⌘E / ⇧E |
| Satin border | ⇧⌘O | Production worksheet | ⌘P |
| Underlay on/off / show | U / ⇧U | Fit hoop / zoom in / zoom out | ⌥0 / Z / ⇧Z |
| | | Zoom box / real size / to selected | B / 1 / ⇧0 |
| | | Zoom to design | 0 |
| | | Show stitches / outlines / connectors / hide unselected | S / L / ⇧C / ⇧S |
| | | Measure | M |
| Knife / weld / smooth shapes | ⌥K / ⌥W / ⌥N | | |
| Laydown | ⌥⇧L | | |
| Branching | I | | |
| Add / remove stitch angles | ⌃H / ⌃⇧H | | |
| Edit stitches | E | | |
| Add monogram | ⌥⇧M | | |
| Hole in fill | ⌥H | Grid / snap to grid | ⇧G / ⇧⌘G |
| | | Rulers & guides | ⌘R |
| Start & end points | ⌥E | Show needle points | . (period) |
| Move & size artwork | ⌥D | Show / hide reference image | D |
| Auto-digitize | ⌥M | Play / pause stitches, back to start | Space or ⇧R, Home |
| Choose thread from chart | ⌥T | Pro view / Settings | ⌥⌘P / ⌘, |
| Insert / delete node | ⌥⇧I / ⇧⌫ | Finish / cancel path | Return / Esc |
| Open / closed shape | ⌥O / ⌥S | Freehand open / closed shape | ⌥⇧O / ⌥⇧S |
| Rectangle / ellipse / basic shapes | ⌥R / ⌥J / ⌥B | | |
| | | Next / previous design tab | ⌃⇥ / ⌃⇧⇥ |

## Known limits

**Early machine testing.** PES files load correctly on a Brother SE600 (100 × 100 mm hoop); full sew-out tests are under way. Export checks read each file back with the same library that wrote it; they don't prove a machine will accept it or that the stitches look right. Trim and color behavior varies between machines. Confirm your machine model before the first sew-out. Brother files larger than 100 × 100 mm haven't been sewn yet; JEF can only describe Janome hoops up to 200 × 200 mm (use DST for larger ones).

**Stitches:**
- Satin columns with crossing or reversed pairs are refused; split sharp bends into separate columns. Each satin is limited to 5,000 edge pairs.
- Parts of a shape are joined by short travel runs sewn inside it where possible (up to 150 mm while they'll be covered, 40 mm after); longer gaps use trims. Some travel runs over sewn fill near edges, so check it at the sew-out.
- Stitches shorter than 0.3 mm are merged into the next stitch, as most digitizing software does, so a very small corner can be rounded off slightly. Imported machine files keep every stitch.
- Contour fills spiral smoothly on round shapes (ovals, rounded corners). Shapes with sharp corners show a short step line from ring to ring; it runs from the Start point toward the middle, so put the start where it shows least. Radial fills crowd a little where the edge comes close to the center.
- Underlay that won't fit at the chosen inset is left out, with a warning.

**Lettering:** arched lettering is one line (make each curved line its own lettering). Updating lettering rebuilds every letter, so hand edits are lost (Undo brings them back). The embroidery fonts were tuned for Ink/Stitch, whose underlay and compensation differ a little, so test-sew small text.

**Auto-digitize** makes fills only, and touching colors are traced separately, so check where they meet. Photos and gradients reduce to flat color patches.

**Not yet available:** nested groups, and automatic satin or running-stitch digitizing.

### SVG support

- **Supported:** paths (all commands), rectangles, circles, ellipses, lines, polylines and polygons; group transforms; `viewBox`; px, mm, cm, in, pt and pc units; solid fill and stroke colors (hex, `rgb()` and 18 basic names); even-odd and nonzero fills with holes.
- **Not supported** (reported or refused): CSS stylesheets and classes, text, `use`/symbols, nested viewports, masks, clipping, filters, markers, gradients and external files. Export such files with inline styles and outlined text.
- **Limits:** UTF-8, 5 MB, and 2,000 points per shape. Overlapping shapes are merged as points (the report says so). Strokes become center lines; their width isn't digitized.

### Machine-file import details

- Stitches come in exactly as stored, without added ties or resampling. Stitches over 10 mm are reported.
- PES/PEC repeated colors stay as thread changes (they may be stops). DST jump sequences aren't turned into trims. JEF color zero is read as a stop.
- Header settings, separate color files, thumbnails and original digitizing objects aren't kept.
- Limits: 5 MB, 100,000 commands and 1,000 thread blocks.

### Export formats

| Format | Colors | Notes |
| --- | --- | --- |
| PES 6 / 1 | PES 6 stores exact colors; PES 1 uses Brother's palette | Must fit the chosen hoop; travel can become a trim. Brother machines place the design in the middle of the hoop (move it on the machine's screen) |
| PEC | Brother palette | Hoop is checked |
| DST | none stored (use the thread list) | Trims depend on machine setup |
| EXP | none stored (use the thread list) | Trim behavior varies by machine |
| JEF | Janome palette | Picks a standard hoop from the design's size |
| VP3 | exact colors | Travel is trimmed; check the first move at the sew-out |
| XXX | exact colors | At most 21 thread blocks |

Stops are saved as a repeated color, with a reminder to keep the same thread. Except XXX, files hold at most 255 thread blocks including stops. Leave a little room at the hoop's edges: trim moves outside the hoop are refused.
