# OpenHoop user guide

How to digitize with OpenHoop, from artwork to a file your embroidery machine can sew. For an overview and how to build the app, see the [README](../README.md).

**Contents:** [Getting started](#getting-started) · [Bringing in artwork](#bringing-in-artwork) · [Drawing stitches](#drawing-stitches) · [Editing shapes](#editing-shapes) · [Viewing and measuring](#viewing-and-measuring) · [Lettering](#lettering) · [Patches: borders and appliqué](#patches-borders-and-appliqué) · [Threads and fabric](#threads-and-fabric) · [Hoops](#hoops) · [Checking and saving for the machine](#checking-and-saving-for-the-machine) · [Importing machine files](#importing-machine-files) · [Making it yours](#making-it-yours) · [Keyboard shortcuts](#keyboard-shortcuts) · [Known limits](#known-limits)

## Getting started

Open `dist/OpenHoop.app` after building it. To look around first, choose **File → Open Sample Design** or **File → Open Satin + Fill Sampler**. The app carries its own file converter, so you don't need to install Python to use it.

> OpenHoop has been built and tested on an Apple Silicon Mac. Its stitches have not yet been sewn on a real machine, so test-sew on scrap fabric first.

**The window:**
- **Tool strip** (under the toolbar): tools grouped as *Pick & shape*, *Stitch*, *Add* and *View*, each with its key. Some tools share a slot (Fill and Hole; Text, Satin border, Appliqué and Auto-digitize); click the slot's arrow to pick one. Tools that can't be used yet are dimmed.
- **Canvas:** the hoop with your design. Scroll to pan, pinch or Option-scroll to zoom, **⌥0** to fit the hoop. More ways to look: [Viewing and measuring](#viewing-and-measuring).
- **Panels:** Sewing order, Properties, Design (fabric and hoop), Reference image and Threads. The stitch player sits at the right end of the tool strip.
- **Status bar:** messages, and a **Ready to save** check that turns orange with a short reason when something needs fixing before export.

**Guided and Pro views.** Same features, two layouts; switch with **⌥⌘P** or the **Guided | Pro** toggle in the toolbar. Pro shows every tool as its own button on a walnut band, two rows across the top; **Settings › Tools & player › Tools** moves them to a rail down the left side instead.
- **Guided** (the default) shows the everyday settings with a plain-English line under each and folds the rest under **More settings**.
- **Pro** shows everything at once: every tool in one row, a precision bar for exact position, size and rotation, compact Properties, a sewing-order table with stitch counts, and live stats in the status bar. Explanations become tooltips.

**Not sure what something does?** Rest the pointer on any tool, button or setting: a tooltip says what it does, with its key.

**Escape** means "done": it returns to the Select tool, stops the stitch player and shows the whole design. While drawing, Escape cancels the path instead.

## Bringing in artwork

**Trace over an image.** **⌘I** imports a PNG or JPEG as a reference image (it never sews). Set its size in the Reference image panel, and drag the **Opacity** slider there to fade it (the image changes as you drag; letting go is one step to undo). Press **⌥D** (or **Move & size on canvas**) to move it or resize it from a corner (Shift stretches it); press Escape when done. With no image yet, **Move & Size Artwork** shows a + on its icon and asks for one first, then lets you place it. **D** shows or hides it.

**Put the image between layers.** The reference image has its own row in the Sewing order, at the top to begin with (under everything). Its **▲ ▼** arrows move it one step at a time: the steps listed above it are drawn under the image and the ones below it on top. So you can digitize the background, move the image below it, and trace the next layer over it. Grouped objects (such as the letters of a word) count as one step. New objects go at the end of the list, over the image. It only changes what you see: the image is never sewn.

**Import SVG outlines.** **⇧⌘I** imports an SVG as unstitched outlines at its real size. Select an outline and choose **Running Stitch** or **Tatami Fill** in Properties to make it sew. Curves keep their Bézier handles; strokes come in as center lines. The import report lists anything it couldn't use. [What SVG content is supported](#svg-support).

**Auto-digitize.** **⌥M** traces the reference image into fills. Choose how many colors to reduce it to (2–8, counting the background), whether to skip the background, and the smallest part to keep. You'll see your image beside the traced result before anything is added. Each color patch becomes a tatami fill with its holes, placed over the image, largest colors first. Thin lines and small text trace poorly; redraw those as satin or running stitch.

## Drawing stitches

All drawing tools work the same way: **click** for a corner, **press and drag** to pull out a curve, **secondary-click** for an automatic smooth point. **Return** finishes, **Escape** cancels, **Delete** removes the last point. Projects remember an unfinished path, so you can carry on after reopening.

### Running stitch (⇧N)

A line of stitches along your path. Set **Stitch length** in Properties.

**Bean stitch:** set **Passes** to **Bean ×3** or **Bean ×5** for a bold outline. Each stitch is sewn forward, back and forward again. Stitch lengths of 2.5–3.5 mm suit it.

**Line styles:** **Line style** in Properties sews a line as something other than plain running stitch. Like Fill style, it's a button with a picture: click it for the list of styles, each with a picture of its stitches, and point at one to see the selected line sewn that way on the canvas (nothing changes until you click):

| Style | What it looks like | Settings |
|---|---|---|
| **Zigzag** | The needle swings side to side along the line: a decorative edge, or a light tack-down | **Width** (2 mm), **Spacing** along the line (1.5 mm). Together they set each stitch, so zigzag has no Stitch length |
| **Blanket** | Running stitch with short prongs at regular spacing, like hand blanket stitch: the classic appliqué edge. On a closed shape the prongs point inward | **Prong length** (2.5 mm), **Prong spacing** (3 mm) |
| **Back stitch** | Each stitch goes forward two lengths and back one: a solid, hand-sewn line | **Stitch length** |
| **Stem stitch** | Like back stitch, with each stitch slanting across the line: a twisted rope | **Width** (1 mm), **Stitch length** |
| **Motif** | A small pattern repeated along the line, joined by short runs: hearts, leaves, diamonds, stars, scallops or circles. Each motif bends with the line | **Motif**, **Motif size** (4 mm), **Gap** (1 mm) |
| **Ripple** | The line sewn again and again, each copy the same shape but smaller, shrinking toward a **Target** dot (drag it on the canvas; **Reset target** puts it back). A closed shape spirals in, in one unbroken line; an open line is sewn there and back, each copy smaller. The target starts in the middle of a closed shape, and to one side of a straight or wavy open line | **Lines** (10, from 2 to 50), **Stitch length** |

Projects using line styles, the stipple, motif, cross stitch, gradient or guided fills, lettering on a line, or raised satin are saved as file version 6, which versions of OpenHoop before these stitches refuse to open rather than sewing them as plain stitches.

### Satin columns (⇧A)

Smooth, shiny columns for borders, outlines and lettering. Two ways to make one:
- **Edge by edge:** with **⇧A**, click pairs of points, one on each side of the column, all the way along; press Return after at least two pairs.
- **From a center line (⇧I):** draw a running line down the middle, set **Satin width** in Properties (0.8–10 mm), then press **⇧I** (or F6) or **Make satin column**. Sharp turns are rounded just enough for the satin to turn. Turns too tight for the width are explained and the line is left alone.

Settings: **Row spacing**, **Compensation** per side (extra width because thread pulls the fabric in), **Compensation % of width** (More settings; in Pro, **% of width**), and **Maximum stitch**. The percentage adds a share of each stitch's own width on top, so wide parts of a satin get more: new satins start at 3%, so a 2 mm part gets 0.26 mm per side and a 6 mm part 0.38 mm. It's a starting value to tune after a test sew-out. Two helpers, on for new satins:
- **Short stitches on curves:** on the inside of a curve, every other stitch stops short so the thread doesn't pile up.
- **Split wide satin:** stitches longer than the maximum are split into shorter, staggered ones instead of the column being refused.
- **Raised (padded):** lanes of padding stitches are sewn along the column first, so the satin stands up off the fabric for a 3D look. Best on columns 3 mm and wider.

### Fills (F3)

Trace a closed outline and press Return. Settings: **Row spacing**, **Stitch length**, **Angle** and **Expansion**. For tatami, wave and guided fills, Row spacing is measured across two rows (from a row to the next one sewn the same way), as embroidery software usually measures it: the default 0.40 mm lays the rows 0.20 mm apart. Designs saved by earlier versions have these spacings doubled when they open, so they sew exactly as before. **Fill style** sets how the rows are laid:

| Style | What it looks like |
| --- | --- |
| **Tatami** | Straight rows (the default) |
| **Contour** | Rings following the outline inward, sewn as a few long spirals |
| **Radial** | Stitches fanning out from a center point; drag the **Center** dot on the canvas to move it |
| **Wave** | Rows that ripple, with a wave height and length |
| **Stipple** | One wandering line that loops through the whole shape and never crosses itself: the quilting look, or a light background. **Stipple spacing** (4 mm) sets how far apart its passes are; it sews without underlay, in stitches of 2 mm at most so its curves stay round |
| **Motif** | Rows of whole motifs (hearts, leaves, stars…) across the shape at the fill angle, every other row shifted half a motif. **Motif**, **Motif size** (5 mm) and **Gap** (1.5 mm); no underlay |
| **Cross stitch** | X's on a square grid, like hand cross-stitch, in every square entirely inside the shape, so the edge steps. Each diagonal is sewn three times for the weight of floss. **Square size** (3 mm) sets the stitches, so there's no Stitch length; no underlay |
| **Gradient** | Tatami rows that open up across the shape, from **Spacing at start** (0.4 mm, solid) to **Spacing at end** (2.5 mm, sheer), for shading or blending two colors. Turning the angle by 180° swaps the solid and sheer sides |
| **Guided** | Rows that bend to follow a guide line you draw over the shape, always one row spacing apart: for hair, feathers, petals and anything that flows. See **Guided fills** below |
| **Satin** | Smooth satin stitches straight across the shape from edge to edge, at the fill angle (drag the angle line to turn them), each one coming back beside the last: for leaves, petals and small shapes. **Row spacing** is the satin density (try 0.36 mm). With **Auto split** (on), stitches longer than the **Split length** (7 mm) are broken every 5.5 mm measured from the shape's left edge, so the breaks form bands that follow its edge rather than a straight groove. With Auto split off, a shape wider than the split length is refused. No Stitch length |

**Pattern** (tatami only): where each row's needle holes go. The thread lies the same either way, but the lines of holes make a texture in the fill: **Smooth** (the default, even fine diagonals), steeper or shallower diagonals, ribs, zigzags, waves, herringbone, chevrons, blocks, steps, or **Scattered** holes with no lines at all. Click the Pattern button for pictures of all 26, and point at one to see it on your shape (it shows best with needle points on, and on the real sew-out). Patterns are for straight rows: a tatami with stitch angle lines keeps Smooth.

The **Fill style** button shows a small picture of the current style. Click it for the list of styles, each with a picture of its stitches and a line about it. Point at a style and the selected fill is drawn with it on the canvas, outlined in terracotta while you're only trying it; click to keep it, or move off the list (or press Esc) to go back. Nothing changes in the design, and nothing goes on the Undo list, until you click.

**Holes:** select a fill and press **⌥H** to trace a hole (or use **+** and **−** next to Holes).

**Cut out shapes sewn on top** (off unless you tick it): the fill skips the area that later fills and satins cover, so the hidden part isn't stitched twice. It still sews 1 mm under their edges so no gap shows, and the shape on top can be moved freely; the fill fills back in.

**Stitch angles (⌃H / ⌃⇧H)** (in the Fill slot, and **Stitch angles · Add…** in Properties): select one tatami or satin fill, choose **Add Stitch Angles**, and click two points across it for each line. Each line reaches across the shape, and lines may not cross inside the fill, nor may three or more of them meet the same part of it, like a line across each point of a star or each arm of a Y: rows only turn from one line to one other, so those can't be joined up (if a line would do either, it isn't added, or a dragged line goes back, and the status line says why; a design that already has such lines shows the fill outlined in red, unsewn, until you move or delete some). Beyond an end line, rows run straight at its angle (and between two parallel lines). Between two lines, every point of the shape's edge has a share: how far it is from the first line as a fraction of its distances to both lines. Each row joins the point on one side of the shape to the point on the other side with the same share, so the rows turn evenly from one line's angle to the other's: across a plain shape they fan out from where the two lines would meet, and round a bend (a U, a Z) they turn the whole way round with it, with no seam at any line. Where the rows crowd together toward the narrow side, pairs of rows stop short in bands along that edge, so the spacing stays even and thread doesn't pile up. On a ring (a fill with a hole), draw three or more lines from the outside edge to the hole's edge, all pointing at the middle of the hole, and the stitches run across the ring all the way round. The fill sews in one sweep from one end of the shape to the other. With an end point, the shape is split along the row through it, like a straight fill: the rest is sewn first, ending on that row, then the piece beyond it from its far end back to the end point, so the run out to the far end is covered by that piece. A shape the lines don't cross one after another (a hole or a notch in the way) is cut along the lines and sewn piece by piece, each next to the last. To adjust a line, select the fill, press **H** (Edit nodes) and drag the line: drag one of its square ends to swing that end, or the middle to slide the whole line; the stitches follow when you let go. While you drag (or draw a new line), its angle shows beside the pointer, counted like the fill's Angle. To delete one line, click it (it turns orange) and press **Delete**; this works with Edit nodes or either angle tool, and deletes just the line, not the fill. **Remove Stitch Angles** takes away each line you click; **Remove all** in Properties brings back straight rows. The lines show while the fill is selected with Edit nodes or either tool. On a satin fill the same rows are sewn as a turning satin: each row is one stitch from edge to edge, at the fill's Spacing, split at its Split length with Auto split on (or refused without it), just as a straight satin fill's are.

**Guided fills.** Draw a line over the fill with the line tool (it can reach past the edges; past its ends, the rows carry straight on). Select the fill and the line (Shift-click), then choose **Digitize → Stitch → Use Line as Fill Guide**.
- The line stops sewing and becomes a dashed guide, grouped with the fill.
- The fill's style becomes **Guided**, and its rows follow the guide.
- Reshape the guide with Edit nodes (**H**) and the rows follow.

Each row is the guide moved sideways by whole row spacings, so the spacing stays even everywhere. Far from a bend, rows on its outside round off and rows on its inside close into a corner, so gentle guides look best. A guide can't cross itself.

If you delete the guide, the fill keeps sewing the last shape it had. **Running Stitch** in the guide's Properties turns it back into a line that sews.

### Shapes and the stitch picker

Pick a stitch first, then draw. The **Shape** group in the tool strip holds them. Picking one shows the **Next shape** in the **Properties** panel, even while something is selected (select something again to see its properties): its shape and stitches, with a small drawing of it. Its **Stitch**, **Fill** and **Outline** buttons open lists with a picture of each choice's stitches, in the thread the shape will get. Your choices are remembered, except the outline: picking a closed-shape tool starts it with **Outline: None**, and an outline you pick then lasts until you pick a tool again. Picking a shape tool opens Properties if it's closed.

| Tool | How to draw | Stitch it gets |
| --- | --- | --- |
| **Digitize Open Shape (⌥O)** | Click corners, drag or secondary-click for curves, Return to finish | Running, Bean (triple run), Satin line (as wide as **Width** in the bar), Zigzag, Blanket, Back stitch or Stem stitch |
| **Digitize Closed Shape (⌥S)** | The same, and the outline closes itself | A **Fill** (Tatami, Contour, Radial, Wave, Stipple or None) and an **Outline** (Running, Bean, Satin line, Zigzag, Blanket, Back stitch, Stem stitch or None) |
| **Freehand Open Shape (⌥⇧O)** | Press and drag; the line follows the pointer and is smoothed when you let go | The Open Shape stitch |
| **Freehand Closed Shape (⌥⇧S)** | The same, and the outline closes itself when you let go | The Closed Shape stitches |
| **Rectangle (⌥R)** | Drag corner to corner; set **Corners** for rounded ones | The Closed Shape stitch |
| **Ellipse (⌥J)** | Drag out from the center | The Closed Shape stitch |
| **Basic Shapes (⌥B)** | Pick Polygon (3–12 sides), Star (4–12 points, shallow to deep), Heart or Arrow, then drag | The Closed Shape stitch |

With both a fill and an outline, the shape becomes two objects, grouped so they move together: the fill, then the outline sewn on top of its edge (a satin outline is centered on the edge, like a satin border). When you pick a shape tool, the status line says what the next shape will get.

While dragging a shape, hold **⌘** to keep it even (a square, circle or regular star) and **⇧** to draw it out from where you started. A shape is a normal outline: reshape it with **H**, and change its stitch in Properties.

### Underlay and finishing

**Underlay** is a quick first layer that holds the fabric still. Satins: **Auto** (the default for new satins, borders and appliqué edges), center run, inset edge or inset zigzag. Auto picks from the satin's average width each time it sews, so it follows reshaping: a center run under 2 mm, an inset edge run up to 4 mm, and an edge run then a zigzag above that (from 2 mm on knit and towel). These steps are starting values to tune after a sew-out. Fills: inset edge, or edge plus a sparse fill. **U** turns it on or off; **⇧U** shows it on the canvas.

Fills with **Edge + sparse** underlay lay their sparse rows at the fill angle. For contour, radial and guided fills (and tatami or satin steered by stitch angle lines), whose own rows don't follow that angle, it shows as **Underlay angle** instead, and turns only the underlay. **Underlay spacing** shows only where there are underlay rows to space: not for an edge run on its own.

Satins with a chosen (not Auto) underlay can have a **second underlay** (More settings in Guided, the Underlay section in Pro). It sews after the first, back along the column, so the top stitches start where it ends. Common pairs are center run then zigzag, or edge run then zigzag for wide satins. Both layers use the same inset and spacing. Turning underlay off (or picking the same style for the first) clears the second.

**Finishing:** **Tie in** and **Tie off** add tiny locking stitches, **Trim after** cuts the thread before the next part, and **Stop after** pauses the machine. Trim after is **When far** to begin with: the thread is cut only when the next part in the same thread starts at least 3 mm away (change the distance under **Trims** in the design's Properties, with nothing selected). Closer than that, one plain stitch carries the thread across, with no tie-off or tie-in. Choose **Always** to cut however close the next part is, or **Off** to never cut. A color change or a stop always cuts.

**Start & end points (⌥E):** select an object, press **⌥E**, click where it should start; Option-click where it should end. A selected object shows where it starts as a green play button (▶) and where it ends as a red stop button (■). Drag either one to move it, with Select, Edit nodes or the Start & End tool; each drag is one step to undo. Each object has its own points: with a group selected (such as a laydown's parts), click on the part you mean, even one lying under other objects. Lettering is one object: it sews its letters in order, so a click anywhere sets the word's start on its first letter (Option-click: its end, on its last letter), and the points are kept when you change the text, font or size. The first stitch goes exactly on the start point and the last exactly on the end point; a point off the shape moves to the nearest place just inside it. Fills run inside the shape from the start point to where they begin, hidden under the stitching, and are sewn toward the end point so the last row finishes right beside it. Lines and satins sew from whichever end is nearer the start point; with only an end point set, they finish at the end nearer it (closed outlines start and finish beside it). A line or satin can start part way along. Click on the line, or on the satin: the needle starts there and runs to the nearer end, then sews the whole thing from that end. On a satin the run goes along the middle of the column, hidden under the satin; on a line it goes back through the line's own needle holes, so that stretch is sewn twice. (A start point more than 1 mm off a line just picks the nearer end.) A satin can also end part way along: it's then sewn in two halves that meet at the end point (the needle runs hidden through the unsewn half between them), so a faint join may show there on shiny thread. A line can end part way along too: after the line, the needle comes back along it through its own holes to the end point. Closed outlines and satin borders start right beside their start point and finish at their end point: an outline carries on round, the shorter way, to the end point; a border is sewn the long way round to the end point, then the needle runs hidden back through the rest and sews it to finish there. An end point within 1 mm of an end just finishes at that end, and the End marker shows there. **Auto for all** starts each object where the previous one ends, to cut down on travel.

## Editing shapes

- **Select (O):** click to select, Shift-click to add more, drag to move. Drag from an empty spot to draw a box: everything wholly inside it is selected (hold **⇧** to add to what's already selected). In the sewing order list, Shift-click selects everything between the last object you clicked and this one, and ⌘-click adds or removes one. Drag a row (or the selection) up or down the list to change when it sews: a line shows where it will go, and dropping below the last row sends it to the end. Groups and lettering move whole and are never split. **Sequence by Color** (the palette button under the list, or **Edit › Sequence by Color**) gathers each thread's objects together so the machine changes thread as few times as possible. Arrow keys nudge (1 mm; with something selected, change it in Pro's precision bar or under More settings in Guided's Properties). Small squares round the selection resize it: drag a corner to keep its proportions (hold **⇧** to stretch freely) or a side to stretch it one way; the opposite side stays put. A selected object also shows where it starts sewing (a ring) and where it ends (squares inside squares), in every tool; drag either with Select to set that point. Points you set are labelled Start and End.
- **Edit nodes (H):** drag points and their curve handles. Click a selected object's edge to add a corner point there (keep holding to drag it into place), or secondary-click the edge to add a curve point: the edge stays as it is until you drag the point, then bends smoothly through it. On a satin, either adds a new rung. A drag that would leave the shape unable to sew (such as a satin rung crossing a rail, or a fill's edge crossing itself) goes back, and the status line says why. While you drag, the shape turns red and the status line warns you before you let go. To switch a point between a sharp corner and a smooth curve, click it and use the **Corner | Smooth** switch that appears above the canvas, press **Space**, secondary-click it, or choose **Digitize › Pick & Shape › Corner / Smooth Point**; Option-drag moves one handle on its own. **⌥⇧I** inserts a point under the pointer; **Delete** (or **⇧⌫**) deletes the selected one; with no point selected, Delete removes the whole object. On a tatami or wave fill, a line across the shape shows its stitch angle: drag either square end to turn the stitches (the angle shows beside the pointer, in whole degrees), and they follow when you let go. Drag the line itself to move it anywhere handy: it still crosses the whole shape, turns around where you put it, and moving it never changes the stitches.
- **Stitch errors:** if an object can't be sewn, it's outlined in red and the status bar says why. Everything else keeps showing up-to-date stitches, but export waits until the error is fixed.
- **Arrange:** mirror, rotate, resize, duplicate (**⌘D**), sew earlier or later, hide and lock (**K**). Hidden objects still sew; hiding only declutters the canvas.
- **Sequence by selection order:** Shift-click objects on the canvas (or ⌘-click them in the sewing order list) in the order they should sew, then choose **Sew in click order** (Properties, with several selected), the numbered-list button in Pro's precision bar, or **Edit → Sequence by Selection Order**. They sew one after another in that order, starting where the earliest of them sewed; everything else keeps its place.
- **Skew:** type an angle in **Skew** (Pro's precision bar) or **Skew by °** (Guided, under More settings) and press Return to lean the selection sideways, like italics: positive leans the top to the right. Fill rows lean along.
- **Align and space:** with several objects selected, the row of small buttons in Properties lines them up by their left edges, centers or right edges, tops, centers or bottoms, or both centers. They line up with **the object you select last**, which stays put. **Space evenly across / down** (three or more) leaves the outer two in place and makes the gaps between neighbours equal. A group moves as one block, and locked objects stay put. These are in the Edit menu too.
- **Group (⌘G / ⇧⌘G):** groups move, turn, resize and recolor together. Option-click picks one member.
- **Rename:** double-click an object's name in the sewing order (or right-click it and choose **Rename**), or click its name (with the ✎) at the top of Properties, and type a new one. Return keeps it, Esc keeps the old name, and Undo puts it back. **Edit › Rename Object…** does the same. Until you rename it, an object is called after its stitch and a number, and the name follows the stitch: change Zigzag 2's Line style to Ripple and it becomes Ripple 2. A name you've typed stays as it is. Lettering shows its text instead of a name; change the text in Properties.
- **Lock and hide from the sewing order:** each row has a lock at its right: solid when the object is locked, faint while the pointer is over the row. Click it to lock or unlock. Right-click a row for **Rename**, **Lock / Unlock** and **Hide / Show**. On a group's row (Pro) or lettering, these act on all its objects. Each is one step to undo.
- **Copy, cut and paste (⌘C, ⌘X, ⌘V):** within a design or into another. Pasted objects go at the end of the sewing order, where they were copied from; pasting again into the same design shifts each copy 3 mm.
- **Convert:** turn a running outline into a fill, or outlines back into running stitch.
- **Edit Stitches (E)** (in the Edit nodes slot): select one line, satin or fill and press **E**. Its needle points show as small squares, and the top of the **Properties** panel says you're in Edit Stitches (its **Done** button, or Escape, leaves it). Click one to select it (Shift- or ⌘-click adds more, or drag a box around several), drag to move them, press **Delete** to remove them, and Option-click on a stitch to add a needle point there. Escape when done. The object keeps its settings and Properties says **Stitches edited by hand**. The edits sew until you change its shape or a setting: then fresh stitches replace them and the status bar says so (Undo brings them back). Moving, turning, mirroring, resizing or skewing the object keeps them. **Regenerate** in Properties throws them away on purpose.
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

**Show** (the list next to the zoom slot, and the View menu) switches parts of the view on and off. These only change what you see: everything still sews. OpenHoop remembers your choices (and the grid), so new and opened designs start the way you left them; only **Hide unselected objects** starts off each time.
- **Stitches (S)** and **Outlines of every object (L)**: hide the stitches and show the outlines to check shapes against the artwork.
- **Connectors (⇧C):** the dashed travel moves between parts. They show in the stitch view and are hidden in Thread View until you switch them.
- **Needle points (.)** and **Underlay (⇧U).** Needle points show as small dots once you zoom in (300% or more), in Thread View too.
- **Hide unselected objects (⇧S):** keeps only the selection in view, to work on one part of a busy design. Clicking empty canvas shows everything again until you select something else.
- **Rulers & guides (⌘R):** hides the rulers and guide lines for a clear canvas. Your guides are kept and come back with the rulers.

**Measure (M)** (in the Pan slot): drag from one point to another to read the distance (in mm or inches) and its angle (counted counterclockwise from pointing right, like Rotate). The line stays until you measure again or change tools. Snap to grid applies.

**Rulers:** a thin line on each ruler follows the pointer, so you can read where it is at a glance.

**Guides:** drag down from the top ruler for a side-to-side guide line, or right from the left ruler for an up-and-down one; the position shows beside the pointer while you drag. With Select, drag a guide (where no object is under the pointer, the pointer turns ↔ or ↕) to move it, or back onto its ruler to remove it. **View → Clear Guides** removes them all. With **Snap to grid** on, points and drags close to a guide land on it. Guides are saved with the design but never sewn.

**Grid color:** the grid draws light lines on dark cloth and dark lines on light cloth. To pick your own color and strength, open **Settings → Look → Grid lines** and choose **Custom** (the color picker's opacity slider sets how strong the lines are).

## Lettering

Press **A** (or **Add → Text**), then click on the design where the lettering should go. The word appears there in the last font and size you used, selected, and **Lettering** in Properties is ready for you to type over it.

- **Trying fonts:** the **Font** list in Properties shows your own words in every font. Click one, then press **↑** or **↓** to move to the next: the lettering on the hoop changes as you go, at its real size, so you can see what fits. Fonts tried one after another are one step to undo, so **⌘Z** goes back to the font you started with.
- **Embroidery fonts** (recommended): 18 hand-digitized satin fonts, from 2.8 mm tiny text to 140 mm monograms. Each shows the size range it was made for; switching to one keeps the height if the font was made for it, or moves to the nearest size it was. **Font credits…** lists each font's license.
- **System fonts:** any font on your Mac, as fills or outlines, 3–200 mm tall. Below about 10 mm, use an embroidery font instead.
- **Several lines:** up to 10 (Option-Return starts a new line), aligned left, center or right, with adjustable line spacing.
- **Shape:** **Straight**, **Arch up** or **Arch down**, with the arc's radius, or **On a line** (below).
- **Lettering on a line:** draw a line with the line tool, select the lettering and the line (Shift-click), and choose **Digitize → Add → Put Lettering on Line**.
  - Each letter stands on the line, turned to follow it. The word is centered on the line, and past the line's ends it carries straight on.
  - The line stops sewing and becomes a dashed guide, grouped with the word.
  - Reshape the line with **Edit Nodes (H)** and the letters follow.
  - It works with one line of text. Choosing **Straight** or an arch in Properties takes the word off the line; the line stays, unstitched, for you to delete or reuse.
- **One object:** lettering is one step in the sewing order and moves, resizes and recolors as one. Clicking any letter (even Option-clicking) selects the whole word, and Ungroup leaves it whole.
- **Edit it in Properties:** with the lettering selected, **Lettering** in Properties changes the text (the letters update when you pause typing), the font, height, **Letter spacing** (extra space between letters in mm; negative pulls them closer) and the **Baseline** (straight or arched, with its radius). With several lines, **Lines** aligns them and **Line spacing** sets the gap. Each change is one step to undo. Double-click lettering (or press **⌥L**) to jump to its text. If you had changed any letters by hand, Properties says that these settings rebuild them.
- **Move one letter:** with **Edit Nodes (H)**, each letter has a small diamond handle below it. Drag it to move just that letter, sideways or up and down. It stays where you put it when you change the text, font, size or spacing (moves are kept by the letter's place in the word: 1st letter, 2nd letter…). **Reset letter positions** in Properties puts them back.
- **Break apart:** **Digitize → Add → Break Apart Lettering** (or **Break apart** in Properties) turns the lettering into separate shapes, still grouped, so you can reshape each letter's points. Its text can't be edited after that.

### Monograms (⌥⇧M)

**Add Monogram…** (in the Add slot, next to Text): type one to three initials and pick a font (the embroidery fonts, or classic Mac fonts such as Didot and Baskerville, converted to fill), the height of the tallest initial, and a layout:
- **Big middle:** the middle initial (usually the surname) larger, the others smaller on either side.
- **Side by side:** all the same size in a row.
- **Stacked:** one above the other.
- **Diamond:** a tall middle with shorter initials close in on either side, to suit a diamond border.

Add **ornaments** either side (swirls in bean stitch, leaves or dots, drawn for OpenHoop) and a **border** (circle, oval, rounded rectangle, diamond or shield) sewn as satin, with its width and the gap to the monogram. The preview updates as you go. The monogram is added as one group in the current thread, centered in the hoop. **Double-click** it (or **Edit monogram…** in Properties) to change anything; it's rebuilt in the same place. Embroidery fonts are only digitized for certain sizes, so an initial that would fall outside them is kept within, and the dialog says so. Ungrouping turns a monogram into plain shapes.

## Patches: borders and appliqué

**Satin border (⇧⌘O).** Select a fill or closed outline to add a satin column around its outside edge (1–8 mm, default 3), like the edge of a patch. Corners are rounded just enough for the satin to turn, and shapes too thin for the width are explained. To change a border's width later, select it and type a new **Width** in Properties (satin columns made from a line have it too). The satin is rebuilt around the same middle line; a satin line's sharp turns can't be widened past the width they were made at, and Properties says so.

**Appliqué (F7 or ⌥Q).** Sews a piece of fabric on instead of filling the shape with stitches. The shape becomes three grouped parts, in its own thread:
1. **Placement line**, then the machine stops: lay your fabric over the line.
2. **Tack-down** (an open zigzag, or a running line) holds the fabric, then it stops: trim the fabric close to the stitching.
3. **Satin edge** (2.5–8 mm) covers the cut edge.

## Threads and fabric

**Holding the fabric** (in the Design panel):
- **Basting box:** long running stitches around the design, sewn before everything else in the design's first thread (so the machine doesn't stop), that hold the fabric to the stabilizer. Pull them out after sewing. Set how far outside the design it runs with **Margin** (5 mm to start). It stays inside the hoop: on a rectangular hoop it's cut back to the edge, and on an oval one the margin shrinks until the corners fit.
- **Laydown (⌥⇧L, or Add laydown…):** a light, open fill under the whole design (or the selection) that flattens the pile of towels, fleece and velvet so stitches don't sink in. The dialog sets how far it reaches past the edge, row spacing (measured across two rows, like tatami: 4 mm lays rows 2 mm apart), stitch length, angle, one layer or two crossed ones, and its thread (one matching the fabric hides best), with a preview. Shapes close together share one laydown, which also covers the gaps between them. It's added as a group that sews before what it lies under; change its spacing or angle in Properties afterwards like any fill.

**Thread colors.** The Threads panel shows a thread library: pick a chart from its menu (the basic colors, a machine palette, a thread brand such as Isacord or Madeira, or a chart you imported) and every thread in it appears as a swatch, with a search box for a name or number. Click a thread to set the current thread; anything selected changes to it too. The chart you pick here is the one **Choose Thread from Chart** opens with. In the Pro view the panel also lists the design's threads in sewing order underneath; drag the bar above that list up or down to give more room to the list or to the library, and double-click the bar to let the list fit its threads again.

**The design's palette.** Each design keeps a short row of threads, saved with it, in a strip under the canvas. A new design starts with the eight basic colors. Clicking a thread anywhere (the library, the chart dialog or the palette itself) adds it to the palette if it isn't there yet. **+** adds the current thread, **−** takes it out, and **Remove unused** clears every thread no object sews in; a thread objects still sew in stays (hover over it to see how many objects use it). The button beside the chart menu in the Threads panel, or **View › Palette Under Canvas**, docks the palette at the top of the Threads panel instead, and back.

**Real threads (⌥T).** **Choose Thread from Chart** picks threads by brand and color number:
- **Current thread and selection:** the closest matches are listed first, or search by name or number.
- **Every thread in the design:** previews each thread beside its closest chart thread before **Match All** changes them. A muted color may match a gray if the chart has nothing closer.
- Built-in charts, in two sections of the chart menu:
  - **Machine palettes:** Brother, Janome and Husqvarna Viking. Their numbers are each machine's own color numbers, which may differ from the number on the spool.
  - **Thread brands**, with real spool numbers: Brother Embroidery and Country, Madeira Polyneon and Rayon, Isacord, Robison-Anton Polyester and Rayon, Sulky Polyester and Rayon, Floriani, Gunold, Marathon Polyester and Rayon, Mettler Poly Sheen, Hemingworth, Fil-Tec Glide, Simthread (and its 63 Brother colors), Janome, DMC and Coats Alcazar, from Ink/Stitch. Their colors are screen approximations of the real spools.
- **Import Chart…** adds any other GIMP palette (`.gpl`) file, such as Ink/Stitch's other brand charts (github.com/inkstitch/inkstitch, `palettes` folder). Imported charts get their own section, and one with a built-in chart's name replaces it.
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

**Stitch player.** The player sits at the right end of the tool strip, under the caption **Player** (at the bottom of the tool rail when Pro's tools are down the left side). Press **Space** or **⇧R** (or ▶) to watch the design sew, and **Home** (or ⏮) to go back to the start; drag the slider to step through it. **.** (period) shows the needle points. The speed buttons set how many stitches it sews per second (12, 120, 500 and 2,000 to start; a machine sews about 12), and you can switch between them while it plays. Change the four speeds in **Settings › Tools & player**. For a one-off speed, right-click the buttons and choose **Custom Speed…** (1–5,000). Each time the app opens, the player starts on the second button.

**Density map.** Turn on **View → Density Map** (or **Density** in the Show list) to color the spots that lay too much thread, in 1 mm squares. They show in both views and update as you edit.
- **Yellow** is heavy: more than about 2 layers of fill (for example, two satins crossing). One layer is an ordinary tatami fill at 0.40 mm.
- **Red** is too dense: more than about 3 layers, or 6 or more needle holes inside a quarter of a millimetre. Expect stiff patches there, broken thread, or holes cut in the fabric.
- The status line gives the total area of each.

**Test swatches.** Not sure which row spacing or compensation suits your fabric? Select one line, fill or satin and choose **Digitize → Make Test Swatches…**.
- Pick the setting to step (row spacing, stitch length, compensation, compensation %, fill angle or underlay spacing; only the ones that change this object's stitches are offered), the value to start at, the step and how many (2–25).
- The preview shows them laid out in your hoop. **Make Swatches** opens them as a new design.
- Each copy is named after its value ("Row spacing 0.35 mm") and they sew in order, top left first, so you can tell them apart on the fabric.
- If they don't fit the hoop, make fewer or shrink the shape first.

**Save your work** as a `.stitchproj` project; that's what you keep editing. Machine files are output only.

**Export:**
- **File → Export Machine File…** (**⌘E** or **⇧E**) saves the stitches for your machine. Pick the format from the **Format** menu at the bottom of the save window: PES 6 (the default, for Brother and Baby Lock), PES 1, PEC, DST, EXP, JEF, VP3 or XXX. OpenHoop remembers the one you used last.
- Every export is read back and checked before saving: needle positions, colors, stops, travel and hoop bounds. If anything changed, nothing is saved.
- **File → Export Thread List…** saves a spreadsheet (CSV) of the thread order, with brands and numbers, for the format you pick. Use it for DST and EXP, which store no colors.

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

**Light or dark:** **Settings → Look → Appearance** keeps OpenHoop light or dark, or **Match Mac** follows the Mac's own setting (the default).

**Around the hoop:** **Settings → Look** sets the color behind the hoop, or follows light and dark mode.

**Grid & snap:** **Settings → Measuring** sets how far apart the grid's lines are (5, 10 or 20 mm, or ¼, ½ or 1 in; half that when zoomed in) and the steps Snap moves points to (0.5, 1 or 2 mm, or 0.025, 0.05 or 0.1 in).

**New designs and objects:** **Settings → New designs** sets what things start with:
- **New designs:** the fabric type, and the hoop: the one you used last, or one you pick there (then choosing another hoop for one design doesn't change it).
- **New objects:** the stitch length of lines and fills, the fill angle, and satin compensation, for shapes you draw. Row spacing, pull compensation and underlay come from the design's fabric type; lettering, monograms and imports keep their own settings.
- **Machine:** how many stitches a minute your machine sews, for the time estimate in the status bar and on worksheets.

**Millimeters or inches:** **Settings → Measuring**, or **View → Use Inches**, switches how sizes and positions are shown and typed: object, design and hoop sizes, positions, start and end points, the rulers, guides, Measure, nudge, lettering and monogram height, and the worksheet. In inches the grid draws a line every ½ in (¼ in zoomed in) and Snap rounds to 0.05 in, unless Grid & snap is set finer or coarser. Stitch settings (stitch length, row spacing, satin and border widths, underlay, compensation) always stay in millimeters, as digitizers usually give them. Designs are saved the same either way, so switching never changes a design.

**Updates:** OpenHoop looks for a new version once a day while it's open, and **OpenHoop → Check for Updates…** looks right away. When there is one, a window shows what's new: **Install Update** downloads it, installs it and reopens OpenHoop, **Remind Me Later** asks again another day, and **Skip This Version** waits for the one after. Only updates signed by OpenHoop's maker are installed. Nothing about you or your designs is sent; it only reads the list of versions on openhoop.app. **Settings → Updates** switches the daily check off, or checks now. (This starts with the version after 0.6.0; to get it, download it from openhoop.app once.)

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
| Appliqué | F7 or ⌥Q | Export machine file | ⌘E or ⇧E |
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
| Insert / delete node | ⌥⇧I / ⌫ or ⇧⌫ | Finish / cancel path | Return / Esc |
| Open / closed shape | ⌥O / ⌥S | Freehand open / closed shape | ⌥⇧O / ⌥⇧S |
| Rectangle / ellipse / basic shapes | ⌥R / ⌥J / ⌥B | | |
| | | Next / previous design tab | ⌃⇥ / ⌃⇧⇥ |

## Known limits

**Early machine testing.** PES files load correctly on a Brother SE600 (100 × 100 mm hoop); full sew-out tests are under way. Export checks read each file back with the same library that wrote it; they don't prove a machine will accept it or that the stitches look right. Trim and color behavior varies between machines. Confirm your machine model before the first sew-out. Brother files larger than 100 × 100 mm haven't been sewn yet; JEF can only describe Janome hoops up to 200 × 200 mm (use DST for larger ones).

**Stitches:**
- Satin columns with crossing or reversed pairs are refused; split sharp bends into separate columns. Each satin is limited to 5,000 edge pairs.
- Parts of a shape are joined by short travel runs sewn inside it where possible (up to 150 mm while they'll be covered, 40 mm after); longer gaps use trims. Where a tatami, wave or gradient fill's rows split at a notch or hole, the side branch is sewn there and back (the needle travels out through it while it's bare, then sews it back over that run), so the fill sews in one sweep with its travel covered. Other fills can still run travel over sewn fill near edges, so check it at the sew-out.
- Stitches shorter than 0.3 mm are merged into the next stitch, as most digitizing software does, so a very small corner can be rounded off slightly. Imported machine files keep every stitch.
- Contour fills spiral smoothly on round shapes (ovals, rounded corners). Shapes with sharp corners show a short step line from ring to ring; it runs from the Start point toward the middle, so put the start where it shows least. Radial fills crowd a little where the edge comes close to the center.
- Underlay that won't fit at the chosen inset is left out, with a warning.

**Lettering:** arched lettering is one line (make each curved line its own lettering). Updating lettering rebuilds every letter, so hand edits (and stitch settings changed in Properties) are lost; Undo brings them back. Letters moved with Edit Nodes are kept. The embroidery fonts were tuned for Ink/Stitch, whose underlay and compensation differ a little, so test-sew small text.

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
