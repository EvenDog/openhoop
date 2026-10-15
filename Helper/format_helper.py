"""Convert final needle commands to machine files; this process never writes user files.

The Mac app supplies one JSON request and receives one JSON response. pyembroidery
owns format encoding; the Swift engine has already generated geometry and ties.
"""
import base64
import csv
import io
import json
import math
import sys

from machine_import import import_machine
import pyembroidery as embroidery
import strict_vp3
from pyembroidery.PecReader import read_pec
from pyembroidery.EmbThread import build_unique_palette
from pyembroidery.EmbThreadPec import get_thread_set
from pyembroidery.EmbThreadJef import get_thread_set as jef_palette

OPERATIONS = {
    "stitch": embroidery.STITCH, "jump": embroidery.JUMP, "trim": embroidery.TRIM,
    "colorChange": embroidery.COLOR_CHANGE, "stop": embroidery.STOP, "end": embroidery.END,
}


def export(request):
    """Encode once, decode those same bytes, and verify needle positions and hoop bounds."""
    if request.get("version") != 1:
        raise ValueError("Unsupported helper protocol version.")
    fmt = request.get("format", "pes")
    if fmt not in ("pes", "pec", "dst", "exp", "jef", "vp3", "xxx"):
        raise ValueError("Unsupported export format.")
    pes_version = request.get("pesVersion", 6)
    if pes_version not in (1, 6):
        raise ValueError("PES version must be 1 or 6.")
    plan = request["plan"]
    commands, threads = plan["commands"], plan["threads"]
    if not 1 <= len(commands) <= 1_000_000 or not threads:
        raise ValueError("There are no stitches to export, or the design is too large.")
    hoop = request["hoop"]
    width, height = float(hoop["width"]), float(hoop["height"])
    if not all(math.isfinite(n) and 1 <= n <= 1000 for n in (width, height)):
        raise ValueError("Invalid sewing area.")
    pattern = embroidery.EmbPattern()
    pattern.metadata("name", "Embroidery")
    active_thread = None
    expected = []
    travel_boundaries = set()
    expected_colors = []
    expected_boundaries = []
    expected_threads = []
    expected_names = []
    expected_labels = []   # (brand, code) for each thread block, for the thread list
    # Machine files store thread text as plain ASCII; anything else becomes "?".
    plain = lambda text: text.encode("ascii", "replace").decode("ascii") if text else None
    previous_point = None
    if commands[0]["op"] not in ("jump", "stitch"):
        raise ValueError("A stitch plan must begin with a needle position or travel move.")
    if commands[-1]["op"] != "end" or any(c["op"] == "end" for c in commands[:-1]):
        raise ValueError("The stitch plan must have exactly one final END command.")
    for thread in threads:
        if not isinstance(thread.get("hex"), int) or not 0 <= thread["hex"] <= 0xFFFFFF or not isinstance(thread.get("name"), str) or len(thread["name"]) > 256:
            raise ValueError("Invalid thread color or name.")
        # Optional thread-chart details (brand and color number), stored in PES v6 thread records.
        if any(thread.get(key) is not None and (not isinstance(thread[key], str) or len(thread[key]) > 100) for key in ("brand", "code")):
            raise ValueError("Invalid thread brand or code.")
    for command in commands:
        op = command["op"]
        if op not in OPERATIONS:
            raise ValueError("Unsupported sewing command: " + str(op))
        point = command["point"]
        x, y = float(point["x"]), float(point["y"])
        if not math.isfinite(x) or not math.isfinite(y) or max(abs(x), abs(y)) > 10_000:
            raise ValueError("Invalid stitch coordinate.")
        thread_index = command["thread"]
        if not isinstance(thread_index, int) or not 0 <= thread_index < len(threads):
            raise ValueError("Invalid thread assignment.")
        if op not in ("stitch", "jump") and previous_point is not None and (x, y) != previous_point:
            raise ValueError("Control commands cannot move the needle.")
        if op in ("stitch", "jump", "stop", "trim") and active_thread is not None and thread_index != active_thread:
            raise ValueError("Thread changes require an explicit color-change command.")
        if active_thread is None or op == "colorChange":
            thread = threads[thread_index]
            pattern.add_thread({"color": thread["hex"], "description": plain(thread["name"]),
                                "brand": plain(thread.get("brand")), "catalog": plain(thread.get("code"))})
            expected_threads.append(pattern.threadlist[-1])
            expected_names.append(thread["name"])
            expected_labels.append((thread.get("brand") or "", thread.get("code") or ""))
            active_thread = thread_index
        if op in ("colorChange", "stop"):
            expected_boundaries.append(len(expected))
            if op == "stop":
                expected_threads.append(pattern.threadlist[-1])
                expected_names.append(threads[active_thread]["name"])
                expected_labels.append(expected_labels[-1])
        if op in ("stitch", "jump"):
            qx, qy = round(x * 10) / 10, round(y * 10) / 10
            outside = (qx / (width / 2)) ** 2 + (qy / (height / 2)) ** 2 > 1.000001 if hoop.get("oval") else abs(qx) > width / 2 or abs(qy) > height / 2
            if outside:
                raise ValueError(f"Stitch at ({qx:.1f}, {qy:.1f}) mm is outside the selected sewing area.")
        if op == "jump" and expected and previous_point != (x, y):
            travel_boundaries.add(len(expected))
        if op == "stitch":
            expected.append((x * 10, -y * 10))
            expected_colors.append(threads[thread_index]["hex"] & 0xFFFFFF)
        # This writer omits VP3 jumps. A trim before travel prevents a sewn
        # connection to the next needle position; the first move starts unthreaded.
        if fmt == "vp3" and op == "jump" and expected and previous_point != (x, y):
            pattern.add_stitch_absolute(embroidery.TRIM, previous_point[0]*10, -previous_point[1]*10)
        pattern.add_stitch_absolute(OPERATIONS[op], x * 10, -y * 10)
        previous_point = (x, y)
    if len(expected) < 2:
        raise ValueError("At least two needle positions are required.")
    if len(expected_threads) > (21 if fmt == "xxx" else 255):
        raise ValueError(f"{fmt.upper()} export supports at most {21 if fmt == 'xxx' else 255} thread blocks, including stops.")
    if fmt not in ("pes", "pec"):
        pattern.interpolate_stop_as_duplicate_color()
    # Brother machines read PEC stitches as distances from the design's top-left corner and drop anything at a
    # negative position: a Brother SE600 showed and sewed only the part of a design right of and below the hoop
    # center. So PES and PEC files start from that corner, as other embroidery software writes them; the machine centers
    # the design in its hoop itself. `shift` is how far everything moved (0.1 mm units, y down as in the file).
    shift = (0.0, 0.0)
    if fmt in ("pes", "pec"):
        left, top, _, _ = pattern.bounds()
        shift = (-left, -top)
        pattern.translate(*shift)
        expected = [(x + shift[0], y + shift[1]) for x, y in expected]
    output = io.BytesIO()
    settings = {"version": pes_version, "tie_on": False, "tie_off": False, "round": True,
                "trims": True, "trim_at": 3,
                "long_stitch_contingency": embroidery.CONTINGENCY_LONG_STITCH_SEW_TO}
    getattr(embroidery, "write_" + fmt)(pattern, output, settings)
    data = output.getvalue()
    if fmt == "pes" and pes_version == 6:
        data = set_pes_hoop(data, width, height)
    decoded = embroidery.EmbPattern()
    if fmt == "vp3":
        # The pinned VP3 reader skips a block's start position when it lies on an axis, which
        # rejected valid files; the corrected import reader honors every block start.
        strict_vp3.read(io.BytesIO(data), decoded)
    else:
        getattr(embroidery, "read_" + fmt)(io.BytesIO(data), pattern=decoded, settings={"trim_at": 3, "clipping": False})
    actual = [(x, y) for x, y, op in decoded.stitches if op & embroidery.COMMAND_MASK == embroidery.STITCH]
    if len(actual) != len(expected):
        raise ValueError(f"Export changed the needle count ({len(expected)} to {len(actual)}). No file was saved.")
    if any(abs(ax - ex) > 1.00001 or abs(ay - ey) > 1.00001 for (ax, ay), (ex, ey) in zip(actual, expected)):
        raise ValueError("Export verification found changed needle positions. No file was saved.")
    needle_index, repositioned = 0, True
    for _, _, op in decoded.stitches:
        op &= embroidery.COMMAND_MASK
        if op in (embroidery.JUMP, embroidery.TRIM, embroidery.COLOR_CHANGE, embroidery.STOP):
            repositioned = True
        elif op == embroidery.STITCH:
            if needle_index in travel_boundaries and not repositioned:
                raise ValueError("Export turned a travel move into a sewn connection. No file was saved.")
            needle_index += 1
            repositioned = False
    # Preserve raw PEC boundaries before the reader folds duplicate colors into stops.
    raw = decoded
    if fmt in ("pes", "pec"):
        raw = embroidery.EmbPattern()
        stream = io.BytesIO(data)
        stream.seek(int.from_bytes(data[8:12], "little") if fmt == "pes" else 8)
        read_pec(stream, raw)
    boundaries, needles = [], 0
    for _, _, op in raw.stitches:
        if op & embroidery.COMMAND_MASK == embroidery.STITCH:
            needles += 1
        elif op & embroidery.COMMAND_MASK in (embroidery.COLOR_CHANGE, embroidery.STOP):
            boundaries.append(needles)
    if boundaries != expected_boundaries:
        raise ValueError("Export changed a color-change or stop boundary. No file was saved.")
    wanted = [t.color & 0xFFFFFF for t in expected_threads]
    if fmt in ("pes", "pec"):
        palette = get_thread_set()
        wanted = [palette[index].color & 0xFFFFFF for index in build_unique_palette(get_thread_set(), expected_threads)]
        if [t.color & 0xFFFFFF for t in raw.threadlist] != wanted:
            raise ValueError("Export changed the thread color order. No file was saved.")
    elif fmt == "jef":
        palette = jef_palette()
        wanted, last_index, last_thread = [], None, None
        for thread in expected_threads:
            index = thread.find_nearest_color_index(palette)
            if last_index == index and last_thread != thread:
                available = palette[:]; available[index] = None
                index = thread.find_nearest_color_index(available)
            wanted.append(palette[index].color & 0xFFFFFF)
            last_index, last_thread = index, thread
    if fmt in ("jef", "xxx", "vp3") and [t.color & 0xFFFFFF for t in decoded.threadlist] != wanted:
        raise ValueError("Export changed the thread color order. No file was saved.")
    if fmt == "pes" and pes_version == 6:
        actual_colors, index = [], 0
        for _, _, op in decoded.stitches:
            if op & embroidery.COMMAND_MASK == embroidery.COLOR_CHANGE:
                index += 1
            elif op & embroidery.COMMAND_MASK == embroidery.STITCH:
                if index >= len(decoded.threadlist):
                    raise ValueError("Export is missing a thread color.")
                actual_colors.append(decoded.threadlist[index].color & 0xFFFFFF)
        if actual_colors != expected_colors:
            raise ValueError("Export changed a stitch's thread color. No file was saved.")
    # Check decoded moves too: rounding, trim sequences and format origins must not
    # escape the configured area. DST trim wiggles outside it are deliberately rejected.
    for x, y, op in decoded.stitches:
        if op & embroidery.COMMAND_MASK not in (embroidery.STITCH, embroidery.JUMP):
            continue
        x, y = (x - shift[0])/10, (y - shift[1])/10   # back to positions from the hoop center
        outside = (x/(width/2))**2+(y/(height/2))**2 > 1.000001 if hoop.get("oval") else abs(x)>width/2+1e-6 or abs(y)>height/2+1e-6
        if outside:
            raise ValueError("Encoded movement extends beyond the selected sewing area. Move the design inward and retry.")
    warnings = {
        "pes": ["PES encodes travel after the first move as trim/jumps, even with Trim After off. Standalone trims may be omitted; cutting depends on your machine.", "Brother's PEC palette may approximate your thread colors.", "Brother machines place the design in the middle of the hoop; move it on the machine's screen if you want it elsewhere."],
        "pec": ["PEC maps colors to the Brother palette. Travel after the first move uses trim/jumps; standalone trims may be omitted.", "Brother machines place the design in the middle of the hoop; move it on the machine's screen if you want it elsewhere."],
        "dst": ["Standard DST has no thread colors. Use the thread list to set sewing order.", "DST trims use jump sequences; machine trim settings determine cutting."],
        "exp": ["EXP has no thread colors. Use the thread list to set sewing order.", "EXP trim commands are encoded; cutting depends on your machine."],
        "jef": ["JEF maps thread colors to the Janome palette.", "JEF trims use three zero-distance jumps; cutting depends on your machine."],
        "vp3": ["VP3 travel is encoded after trims. Untrimmed travel becomes a trim. Its opening move is encoded as the first needle from the origin; verify starting placement during a test sew-out."],
        "xxx": ["XXX stores RGB thread colors; machine interpretation may vary."]
    }[fmt]
    if fmt in ("pes", "pec") and (width > 100 or height > 100):
        warnings.append("Brother files for hoops larger than 100 × 100 mm haven't been sewn on a machine yet. Check that the machine shows the design in the right hoop before sewing.")
    if fmt == "pes" and pes_version == 6 and pes_hoop(data) != (int(round(width)), int(round(height))):
        raise ValueError("Export wrote the wrong hoop size. No file was saved.")
    if any(c["op"] == "stop" for c in commands):
        warnings.append("Stops use repeated thread-color boundaries. Resume with the same thread; controller behavior varies.")
    if fmt == "jef":
        code = int.from_bytes(data[32:36], "little")
        sizes = {0:(110,110),1:(50,50),2:(140,200),3:(126,110),4:(200,200)}
        hw, hh = sizes[code]
        if any(abs(x)>hw*5 or abs(y)>hh*5 for x,y,op in decoded.stitches if op & embroidery.COMMAND_MASK in (embroidery.STITCH,embroidery.JUMP)):
            raise ValueError("The encoded JEF hoop cannot contain this placement: JEF files describe Janome hoops up to 200 × 200 mm. Center or reduce the design, or export DST for a larger hoop.")
        warnings.append(f"JEF header selects a {hw} × {hh} mm hoop from design bounds. Confirm that hoop on the target machine.")
    mapped_by_rgb = {}
    if fmt not in ("dst", "exp"):
        for thread, mapped in zip(expected_threads, wanted):
            mapped_by_rgb.setdefault(thread.color & 0xFFFFFF, set()).add(mapped)
        if any(len(colors)>1 for colors in mapped_by_rgb.values()):
            warnings.append("Threads with identical requested RGB but different names mapped to different machine palette colors. Review the thread list.")
    # Save separately on request, so machine bytes and the editable project remain independent.
    table = io.StringIO(newline="")
    writer = csv.writer(table)
    writer.writerow(["Block", "Thread", "Requested RGB", "Encoded RGB", "Machine palette RGB", "Brand", "Code"])
    for i, thread in enumerate(expected_threads):
        encoded = "not stored" if fmt in ("dst", "exp") else f"#{(thread.color if fmt == 'pes' and pes_version == 6 else wanted[i]) & 0xFFFFFF:06X}"
        # A leading = + - @ or control character would make a spreadsheet run the cell as a formula; quote it.
        safe = lambda text: "'" + text if text.lstrip().startswith(("=", "+", "-", "@")) or text.startswith(("\t", "\r", "\n")) else text
        name = safe(expected_names[i] or "Thread")
        brand, code = (safe(text) for text in expected_labels[i])
        palette_rgb = f"#{wanted[i]:06X}" if fmt in ("pes", "pec", "jef") else "not applicable"
        writer.writerow([i+1, name, f"#{thread.color & 0xFFFFFF:06X}", encoded, palette_rgb, brand, code])
    min_x, max_x = min(x for x, _ in actual), max(x for x, _ in actual)
    min_y, max_y = min(y for _, y in actual), max(y for _, y in actual)
    return {"version": 1, "ok": True, "bytes": base64.b64encode(data).decode("ascii"),
            "stitchCount": len(actual), "width": (max_x - min_x) / 10, "height": (max_y - min_y) / 10,
            "warnings": warnings, "threadCSV": table.getvalue(), "format": fmt}


def set_pes_hoop(data, width, height):
    """pyembroidery always writes a 100 × 100 mm hoop into the PES 6 header. Put the design's real hoop size (in mm)
    there instead. The header starts with the signature, the PEC offset, a hoop flag, a two-digit number and five
    length-prefixed strings; then two flags, then hoop width and height as 16-bit numbers. If the bytes there aren't
    the expected 100 and 100, the layout isn't what this was written for, so nothing is saved."""
    data = bytearray(data)
    offset = 16
    for _ in range(5):
        offset += 1 + data[offset]
    offset += 4
    if data[offset:offset + 4] != bytes([100, 0, 100, 0]):
        raise ValueError("Unexpected PES header layout; the hoop size could not be written. No file was saved.")
    data[offset:offset + 4] = int(round(width)).to_bytes(2, "little") + int(round(height)).to_bytes(2, "little")
    return bytes(data)


def pes_hoop(data):
    """Reads the hoop width and height (mm) back out of a PES 6 header; the inverse of set_pes_hoop."""
    offset = 16
    for _ in range(5):
        offset += 1 + data[offset]
    offset += 4
    return int.from_bytes(data[offset:offset + 2], "little"), int.from_bytes(data[offset + 2:offset + 4], "little")


def main():
    """Keep stdout machine-readable, including errors, and cap input size."""
    try:
        source = sys.stdin.buffer.read(100_000_001)
        if len(source) > 100_000_000:
            raise ValueError("Request is too large.")
        request = json.loads(source)
        response = import_machine(request) if request.get("operation") == "import" else export(request)
    except Exception as error:
        response = {"version": 1, "ok": False, "error": str(error)}
    sys.stdout.write(json.dumps(response, allow_nan=False))


if __name__ == "__main__":
    main()
