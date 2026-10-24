"""Real PES fixtures check both writer versions, coordinate direction and bounds rejection."""
import base64
import io
import unittest
from unittest.mock import patch
import pyembroidery
from format_helper import export


def fixture(version=6):
    points = [(-20, -10), (0, -10), (0, 15), (12, 15)]
    # Keep individual stitch lengths legal so the writer must preserve every needle position.
    commands = [{"op": "jump", "point": {"x": -20, "y": -10}, "thread": 0}]
    for index, (x, y) in enumerate(points):
        if index:
            px, py = points[index - 1]
            for step in range(1, 10):
                commands.append({"op": "stitch", "point": {"x": px + (x-px)*step/10, "y": py+(y-py)*step/10}, "thread": 0})
        commands.append({"op": "stitch", "point": {"x": x, "y": y}, "thread": 0})
    commands.append({"op": "end", "point": {"x": 12, "y": 15}, "thread": 0})
    return {"version": 1, "pesVersion": version, "hoop": {"width": 100, "height": 100, "oval": False},
            "plan": {"commands": commands, "threads": [{"hex": 0x167c80, "name": "Ocean"}]}}


class FormatTests(unittest.TestCase):
    def test_both_versions_preserve_needle_positions(self):
        for version, signature in [(1, b"#PES0001"), (6, b"#PES0060")]:
            result = export(fixture(version))
            self.assertTrue(base64.b64decode(result["bytes"]).startswith(signature))
            self.assertEqual(result["width"], 32)
            self.assertEqual(result["height"], 25)

    def test_y_axis_is_converted_once(self):
        # The fixture runs from (-20, -10) to (12, 15) mm, y up. PES measures from the design's top-left corner with
        # y down in 0.1 mm, so the first needle is 0 across and 25 mm down, the last 32 mm across at the top.
        result = export(fixture())
        pattern = pyembroidery.read_pes(io.BytesIO(base64.b64decode(result["bytes"])))
        stitches = [(x, y) for x, y, op in pattern.stitches if op & pyembroidery.COMMAND_MASK == pyembroidery.STITCH]
        self.assertEqual(stitches[0], (0, 250))
        self.assertEqual(stitches[-1], (320, 0))

    def test_brother_files_have_no_negative_positions(self):
        # A Brother SE600 drops everything at a negative position, so it showed and sewed only part of a design
        # placed around the hoop center. Every PES and PEC position must be measured from the design's corner.
        for fmt, version in [("pes", 6), ("pes", 1), ("pec", 6)]:
            with self.subTest(format=fmt, version=version):
                data = base64.b64decode(export(dict(fixture(version), format=fmt))["bytes"])
                pattern = getattr(pyembroidery, "read_" + fmt)(io.BytesIO(data))
                moves = [(x, y) for x, y, op in pattern.stitches if op & pyembroidery.COMMAND_MASK in (pyembroidery.STITCH, pyembroidery.JUMP)]
                self.assertEqual(min(x for x, _ in moves), 0)
                self.assertEqual(min(y for _, y in moves), 0)

    def test_stitches_too_long_for_the_format_are_split_not_refused(self):
        # A 15 mm satin zigzag: longer than DST (12.1 mm), EXP and JEF (12.7) and XXX (12.4) can store. Each format
        # gets the file, with every long stitch split evenly and nothing over its limit.
        commands = [{"op": "jump", "point": {"x": -7.5, "y": 0}, "thread": 0}]
        for row in range(6):
            commands.append({"op": "stitch", "point": {"x": -7.5 if row % 2 else 7.5, "y": row * 0.4}, "thread": 0})
        commands.append({"op": "end", "point": commands[-1]["point"], "thread": 0})
        request = {"version": 1, "pesVersion": 6, "hoop": {"width": 100, "height": 100, "oval": False},
                   "plan": {"commands": commands, "threads": [{"hex": 0x167c80, "name": "Ocean"}]}}
        for fmt, limit, pieces in [("dst", 121, 2), ("exp", 127, 2), ("jef", 127, 2), ("xxx", 124, 2), ("vp3", 255, 1), ("pes", 2047, 1)]:
            with self.subTest(format=fmt):
                result = export(dict(request, format=fmt))
                self.assertEqual(result["stitchCount"], 6 * pieces)
                pattern = getattr(pyembroidery, "read_" + fmt)(io.BytesIO(base64.b64decode(result["bytes"])))
                needles = [(x, y) for x, y, op in pattern.stitches if op & pyembroidery.COMMAND_MASK == pyembroidery.STITCH]
                longest = max(max(abs(bx - ax), abs(by - ay)) for (ax, ay), (bx, by) in zip(needles, needles[1:]))
                self.assertLessEqual(longest, limit)

    def test_outside_hoop_rejected(self):
        request = fixture(); request["hoop"]["width"] = 20
        with self.assertRaisesRegex(ValueError, "outside"):
            export(request)

    def test_nonfinite_rejected(self):
        request = fixture(); request["plan"]["commands"][0]["point"]["x"] = float("nan")
        with self.assertRaisesRegex(ValueError, "Invalid stitch"):
            export(request)

    def test_trim_stop_and_color_change(self):
        request = fixture()
        commands = request["plan"]["commands"]
        commands.pop()
        for op in ["trim", "stop", "colorChange", "jump", "stitch", "end"]:
            commands.append({"op": op, "point": {"x": 12, "y": 15}, "thread": 1 if op in ["colorChange", "jump", "stitch", "end"] else 0})
        request["plan"]["threads"].append({"hex": 0xdc6552, "name": "Coral"})
        result = export(request)
        self.assertTrue(any("repeated" in message for message in result["warnings"]))

    def test_repeated_colors_and_stops_preserve_boundaries(self):
        for version in (1, 6):
            request = fixture(version)
            commands = request["plan"]["commands"]; commands.pop()
            request["plan"]["threads"].append({"hex": 0xdc6552, "name": "Coral"})
            for op, thread in [("stop", 0), ("stitch", 0), ("colorChange", 1), ("stitch", 1), ("colorChange", 0), ("stitch", 0), ("stop", 0), ("end", 0)]:
                commands.append({"op": op, "point": {"x": 12, "y": 15}, "thread": thread})
            self.assertTrue(export(request)["ok"])

    def test_corrupted_thread_color_is_rejected(self):
        original = pyembroidery.read_pes
        def corrupt(*args, **kwargs):
            result = original(*args, **kwargs)
            kwargs["pattern"].threadlist[0].color = 0xFF0000
            return result
        with patch("format_helper.embroidery.read_pes", side_effect=corrupt):
            with self.assertRaisesRegex(ValueError, "thread color"):
                export(fixture())


if __name__ == "__main__":
    unittest.main()
