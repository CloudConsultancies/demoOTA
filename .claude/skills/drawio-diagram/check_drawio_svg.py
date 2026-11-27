#!/usr/bin/env python3
"""Check that a .drawio.svg file is both an editable draw.io diagram and a
self-contained SVG image that GitHub can render.

Usage: python3 -I check_drawio_svg.py docs/<name>.drawio.svg [...]

Exit code 0 when every file passes, 1 otherwise. Warnings do not fail.
Standard library only.
"""
import base64
import re
import sys
import urllib.parse
import xml.etree.ElementTree as ET
import zlib

SVG_NS = "{http://www.w3.org/2000/svg}"
XLINK_HREF = "{http://www.w3.org/1999/xlink}href"
WHITE = {"#fff", "#ffffff", "white", "rgb(255,255,255)", "rgb(255, 255, 255)"}


def decode_diagram(diagram):
    """Return the mxGraphModel element of a <diagram>, inflating it if draw.io
    stored it compressed (base64 + raw deflate + URL encoding)."""
    model = diagram.find("mxGraphModel")
    if model is not None:
        return model
    text = (diagram.text or "").strip()
    if not text:
        raise ValueError("diagram has neither an mxGraphModel nor compressed data")
    raw = zlib.decompress(base64.b64decode(text), -15)
    return ET.fromstring(urllib.parse.unquote(raw.decode("utf-8")))


def has_white_canvas(root):
    """True if the SVG paints a white background: a background colour on the
    root element, or a white rect at the origin covering the whole view."""
    style = root.get("style", "").replace(" ", "").lower()
    m = re.search(r"background(-color)?:([^;]+)", style)
    if m and m.group(2) in WHITE:
        return True
    view = root.get("viewBox", "").split()
    width = view[2] if len(view) == 4 else root.get("width", "")
    height = view[3] if len(view) == 4 else root.get("height", "")
    for rect in root.iter(SVG_NS + "rect"):
        if (rect.get("fill", "").lower() in WHITE
                and float(rect.get("x", 0)) <= 0 and float(rect.get("y", 0)) <= 0
                and rect.get("width", "").rstrip("px") in (width.rstrip("px"), "100%")
                and rect.get("height", "").rstrip("px") in (height.rstrip("px"), "100%")):
            return True
    return False


def check(path):
    errors, warnings = [], []
    try:
        root = ET.parse(path).getroot()
    except (ET.ParseError, OSError) as exc:
        return [f"not well-formed XML: {exc}"], warnings

    if root.tag != SVG_NS + "svg":
        errors.append(f"root element is {root.tag}, expected an SVG <svg> element")
    if not root.get("viewBox") and not (root.get("width") and root.get("height")):
        errors.append("<svg> has no viewBox or width/height, so its size is undefined")

    content = root.get("content")
    diagrams = []
    if not content:
        errors.append("<svg> has no 'content' attribute: draw.io cannot open it for editing")
    else:
        try:
            mxfile = ET.fromstring(content)
            if mxfile.tag != "mxfile":
                errors.append(f"'content' holds <{mxfile.tag}>, expected <mxfile>")
            diagrams = mxfile.findall("diagram")
            if not diagrams:
                errors.append("<mxfile> contains no <diagram>")
        except ET.ParseError as exc:
            errors.append(f"'content' is not valid draw.io XML: {exc}")

    for diagram in diagrams:
        name = diagram.get("name", diagram.get("id", "?"))
        try:
            model = decode_diagram(diagram)
        except Exception as exc:  # noqa: BLE001 - report any decode failure
            errors.append(f"diagram '{name}': cannot decode: {exc}")
            continue
        background = (model.get("background") or "none").lower()
        if background not in WHITE:
            errors.append(f"diagram '{name}': draw.io background is '{background}', "
                          "set it to #ffffff (File > Properties > Background)")
        cells = model.findall("./root/mxCell")
        if len(cells) <= 2:
            warnings.append(f"diagram '{name}': has no shapes")

    if not has_white_canvas(root):
        errors.append("SVG image has no white background, so it is unreadable in dark "
                      "mode (export with a white background, not transparent)")

    # GitHub shows README images through <img>: scripts do not run and
    # external resources are not loaded, so the image must be self-contained.
    if root.find(f".//{SVG_NS}script") is not None:
        errors.append("SVG contains <script>, which GitHub strips")
    for el in root.iter():
        href = el.get("href") or el.get(XLINK_HREF) or ""
        if href.startswith(("http://", "https://", "//")) and el.tag != SVG_NS + "a":
            errors.append(f"SVG loads an external resource ({href}), GitHub will not show it")
    if root.find(f".//{SVG_NS}foreignObject") is not None and \
            root.find(f".//{SVG_NS}switch") is None:
        warnings.append("labels use <foreignObject> without a <switch> text fallback; "
                        "some viewers show them blank")

    return errors, warnings


def main(paths):
    if not paths:
        print(__doc__.strip())
        return 2
    failed = False
    for path in paths:
        errors, warnings = check(path)
        status = "FAIL" if errors else "OK"
        print(f"{status} {path}")
        for msg in errors:
            print(f"  error: {msg}")
        for msg in warnings:
            print(f"  warning: {msg}")
        failed |= bool(errors)
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
