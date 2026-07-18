#!/usr/bin/env python3
"""SRT subtitles to FCPXML using a title clip from a user template."""

from __future__ import annotations

import argparse
import copy
import html
import re
import sys
import xml.etree.ElementTree as ET
from dataclasses import dataclass
from fractions import Fraction
from pathlib import Path
from typing import Iterable, List, Optional, Tuple


@dataclass(frozen=True)
class Subtitle:
    start: Fraction
    end: Fraction
    text: str


TIMESTAMP = re.compile(
    r"^(?P<sh>\d{1,2}):(?P<sm>\d{2}):(?P<ss>\d{2})[,.](?P<sms>\d{3})\s*-->\s*"
    r"(?P<eh>\d{1,2}):(?P<em>\d{2}):(?P<es>\d{2})[,.](?P<ems>\d{3})"
)


def _srt_time(match: re.Match, prefix: str) -> Fraction:
    seconds = (
        int(match.group(prefix + "h")) * 3600
        + int(match.group(prefix + "m")) * 60
        + int(match.group(prefix + "s"))
    )
    return Fraction(seconds * 1000 + int(match.group(prefix + "ms")), 1000)


def parse_srt(contents: str) -> List[Subtitle]:
    contents = contents.lstrip("\ufeff").replace("\r\n", "\n").replace("\r", "\n")
    blocks = re.split(r"\n\s*\n", contents.strip())
    subtitles: List[Subtitle] = []
    for block_number, block in enumerate(blocks, 1):
        lines = block.splitlines()
        if lines and lines[0].strip().isdigit():
            lines = lines[1:]
        if not lines:
            continue
        match = TIMESTAMP.match(lines[0].strip())
        if not match:
            raise ValueError(f"SRT {block_number}번 블록의 타임스탬프를 읽을 수 없습니다: {lines[0]!r}")
        start, end = _srt_time(match, "s"), _srt_time(match, "e")
        if end <= start:
            raise ValueError(f"SRT {block_number}번 블록의 종료 시간이 시작 시간보다 빠릅니다.")
        text = "\n".join(lines[1:]).strip()
        if text:
            subtitles.append(Subtitle(start, end, html.unescape(text)))
    if not subtitles:
        raise ValueError("SRT에 변환할 자막이 없습니다.")
    return subtitles


def parse_fcpx_time(value: str) -> Fraction:
    if not value.endswith("s"):
        raise ValueError(f"지원하지 않는 FCPXML 시간 값입니다: {value}")
    raw = value[:-1]
    return Fraction(raw) if "/" in raw else Fraction(raw)


def fcpx_time(value: Fraction) -> str:
    value = Fraction(value)
    if value.denominator == 1:
        return f"{value.numerator}s"
    return f"{value.numerator}/{value.denominator}s"


def _read_text(path: Path) -> str:
    data = path.read_bytes()
    for encoding in ("utf-8-sig", "utf-8", "cp949", "utf-16"):
        try:
            return data.decode(encoding)
        except UnicodeDecodeError:
            pass
    raise ValueError(f"파일 인코딩을 읽을 수 없습니다: {path.name}")


def _parents(root: ET.Element) -> dict:
    return {child: parent for parent in root.iter() for child in parent}


def _replace_title_text(title: ET.Element, value: str) -> None:
    text_nodes = list(title.iter("text"))
    if not text_nodes:
        raise ValueError("템플릿 title 안에 <text> 요소가 없습니다.")

    # Motion titles normally store visible text in one or more text-style nodes.
    target = text_nodes[0]
    styles = list(target.iter("text-style"))
    if styles:
        styles[0].text = value
        for extra in styles[1:]:
            extra.text = ""
    else:
        target.text = value


def _sequence_start(root: ET.Element) -> Fraction:
    sequence = root.find(".//sequence")
    if sequence is None:
        return Fraction(0)
    return parse_fcpx_time(sequence.get("tcStart", "0s"))


def convert(srt_path: Path, template_path: Path, output_path: Path) -> Tuple[int, List[str]]:
    subtitles = parse_srt(_read_text(srt_path))
    try:
        tree = ET.parse(str(template_path))
    except ET.ParseError as exc:
        raise ValueError(f"FCPXML 템플릿을 읽을 수 없습니다: {exc}") from exc

    root = tree.getroot()
    titles = list(root.iter("title"))
    if not titles:
        raise ValueError("템플릿에서 <title> 자막 클립을 찾지 못했습니다.")

    exemplar = titles[0]
    parents = _parents(root)
    parent = parents.get(exemplar)
    if parent is None:
        raise ValueError("템플릿 title의 위치를 확인할 수 없습니다.")

    sibling_titles = [child for child in list(parent) if child.tag == "title"]
    insert_at = list(parent).index(exemplar)
    for old_title in sibling_titles:
        parent.remove(old_title)

    base = _sequence_start(root) if parent.tag == "spine" else Fraction(0)
    warnings: List[str] = []
    if parent.tag != "spine":
        warnings.append(
            f"템플릿 title이 <{parent.tag}> 안에 있어 SRT 시간을 해당 컨테이너 기준으로 적용했습니다."
        )

    for index, subtitle in enumerate(subtitles, 1):
        title = copy.deepcopy(exemplar)
        title.set("offset", fcpx_time(base + subtitle.start))
        title.set("duration", fcpx_time(subtitle.end - subtitle.start))
        title.set("start", "0s")
        title.set("name", subtitle.text.replace("\n", " ")[:80] or f"Subtitle {index}")
        _replace_title_text(title, subtitle.text)
        parent.insert(insert_at + index - 1, title)

    try:
        ET.indent(tree, space="  ")
    except AttributeError:  # Python < 3.9
        pass
    output_path.parent.mkdir(parents=True, exist_ok=True)
    tree.write(str(output_path), encoding="utf-8", xml_declaration=True)
    return len(subtitles), warnings


def main(argv: Optional[Iterable[str]] = None) -> int:
    parser = argparse.ArgumentParser(description="SRT를 사용자 FCPXML title 템플릿으로 변환합니다.")
    parser.add_argument("srt", type=Path)
    parser.add_argument("template", type=Path)
    parser.add_argument("output", type=Path)
    args = parser.parse_args(argv)
    try:
        count, warnings = convert(args.srt, args.template, args.output)
    except (OSError, ValueError) as exc:
        print(f"오류: {exc}", file=sys.stderr)
        return 1
    print(f"완료: 자막 {count}개 → {args.output}")
    for warning in warnings:
        print(f"주의: {warning}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
