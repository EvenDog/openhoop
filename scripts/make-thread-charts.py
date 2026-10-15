"""Writes the thread charts bundled with the app (Resources/ThreadCharts/*.gpl) from the machine palettes
inside pyembroidery (MIT License, already bundled and credited in ThirdPartyNotices.txt).

Run it with the project's Python:  .venv/bin/python scripts/make-thread-charts.py
The output is committed, so this only needs to run again if pyembroidery's palettes change.
"""
from pathlib import Path

from pyembroidery.EmbThreadHus import get_thread_set as husqvarna
from pyembroidery.EmbThreadJef import get_thread_set as janome
from pyembroidery.EmbThreadPec import get_thread_set as brother

# Chart name shown in the app -> (palette function, source file in pyembroidery). The numbers in these palettes
# are each machine's own color numbers, so the names say "machine palette" rather than promising spool numbers.
CHARTS = {
    "Brother (machine palette)": (brother, "EmbThreadPec.py"),
    "Janome (machine palette)": (janome, "EmbThreadJef.py"),
    "Husqvarna Viking (machine palette)": (husqvarna, "EmbThreadHus.py"),
}


def write_chart(name, threads, source, folder):
    """Writes one GIMP palette: a header, then one "R G B<tab>name<tab>code" line per thread."""
    lines = ["GIMP Palette", f"Name: {name}", "Columns: 4",
             f"# From pyembroidery 1.5.1 ({source}), MIT License."]
    for thread in threads:
        if thread is None:   # pyembroidery keeps empty placeholder slots so list positions match machine numbers
            continue
        rgb = thread.color & 0xFFFFFF
        lines.append(f"{rgb >> 16:3d} {(rgb >> 8) & 0xFF:3d} {rgb & 0xFF:3d}\t{thread.description}\t{thread.catalog_number}")
    (folder / f"{name}.gpl").write_text("\n".join(lines) + "\n", encoding="utf-8")


def main():
    folder = Path(__file__).resolve().parent.parent / "Resources" / "ThreadCharts"
    folder.mkdir(parents=True, exist_ok=True)
    for name, (palette, source) in CHARTS.items():
        write_chart(name, palette(), source, folder)
        print("wrote", name)


if __name__ == "__main__":
    main()
