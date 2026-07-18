import tempfile
import unittest
import xml.etree.ElementTree as ET
from fractions import Fraction
from pathlib import Path

from srt_to_fcpxml import convert, parse_srt


SRT = """1
00:00:01,500 --> 00:00:03,000
첫 번째 자막

2
00:00:04,040 --> 00:00:05,500
두 번째
자막
"""

TEMPLATE = """<?xml version="1.0" encoding="UTF-8"?>
<fcpxml version="1.11"><resources><effect id="r1" name="Custom" uid="x"/></resources>
<library><event><project><sequence tcStart="0s"><spine>
<title ref="r1" offset="0s" name="sample" start="0s" duration="1s">
<text><text-style ref="ts1">샘플</text-style></text>
<text-style-def id="ts1"><text-style font="Pretendard" fontSize="52"/></text-style-def>
</title></spine></sequence></project></event></library></fcpxml>"""


class ConverterTests(unittest.TestCase):
    def test_parse_srt(self):
        items = parse_srt(SRT)
        self.assertEqual(items[0].start, Fraction(3, 2))
        self.assertEqual(items[1].text, "두 번째\n자막")

    def test_template_style_and_timing_are_preserved(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            srt, template, output = root / "in.srt", root / "template.fcpxml", root / "out.fcpxml"
            srt.write_text(SRT, encoding="utf-8")
            template.write_text(TEMPLATE, encoding="utf-8")
            count, warnings = convert(srt, template, output)
            self.assertEqual((count, warnings), (2, []))
            tree = ET.parse(output)
            titles = list(tree.getroot().iter("title"))
            self.assertEqual(len(titles), 2)
            self.assertEqual(titles[0].get("offset"), "3/2s")
            self.assertEqual(titles[0].get("duration"), "3/2s")
            self.assertEqual(titles[1].find(".//text-style").text, "두 번째\n자막")
            self.assertEqual(titles[1].find(".//text-style-def/text-style").get("fontSize"), "52")


if __name__ == "__main__":
    unittest.main()
