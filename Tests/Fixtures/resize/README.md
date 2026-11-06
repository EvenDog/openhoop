# Test designs for Recognize Objects

Five machine embroidery designs, digitized by other people in three different programs, that
`StitchRecognitionTests` turns back into fills and satin columns.

| File | What it tests |
|---|---|
| `smiling-face.pes` | Patterned tatami fill sewn in sections, two fills on top, three curved satins |
| `smiling-face-inkstitch.pes` | The same picture digitized in Ink/Stitch: a satin ring round the edge |
| `melting-face.pes` | A wavy fill with three holes; oval satin eyes sewn in two halves that meet |
| `melting-face-hand-stitch.pes` | The same with a rough hand-stitched look |
| `grinning-face-with-sweat.pes` | A fill split in two sections around a small satin, a fan-shaped satin mouth |

Each `.json` file holds the same design's needle commands as OpenHoop's importer
(`Helper/machine_import.py`) decodes them, `[operation, x, y, thread]` in millimetres, because
the core tests can't run the Python format helper. To make one again from its `.pes` file:

```sh
.venv/bin/python -I -c 'import base64, json, sys; sys.path.insert(0, "Helper"); from machine_import import import_machine
plan = import_machine({"version": 1, "operation": "import", "format": "pes", "bytes": base64.b64encode(open(sys.argv[1], "rb").read()).decode()})["plan"]
json.dump({"threads": plan["threads"], "commands": [[c["op"], round(c["point"]["x"], 3), round(c["point"]["y"], 3), c["thread"]] for c in plan["commands"]]}, open(sys.argv[2], "w"), separators=(",", ":"))' Tests/Fixtures/resize/melting-face.pes Tests/Fixtures/resize/melting-face.json
```

## Credits

The designs are from the Emoji Embroidery Project by Daniel K. Schneider (University of Geneva,
Faclab / Arbores TECH), <https://tecfa.unige.ch/guides/embroid/emoji/>, licensed under
[CC BY-SA 4.0](https://creativecommons.org/licenses/by-sa/4.0/). They're unchanged apart from
their file names, and the `.json` files are decoded from them.

The pictures they're digitized from are [Twemoji](https://github.com/twitter/twemoji) emoji by
Twitter, Inc. and other contributors, licensed under
[CC BY 4.0](https://creativecommons.org/licenses/by/4.0/).
