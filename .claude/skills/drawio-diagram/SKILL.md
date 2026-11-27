---
name: drawio-diagram
description: Create or update a draw.io diagram in this repo as docs/<name>.drawio.svg (one file that opens in draw.io and renders as an image on GitHub), with a white background, embedded in Markdown and paired with a pure text description. Use when the user asks to add, draw, update or fix a diagram, an architecture picture, a flow, sequence or partition layout, or when documentation needs a figure. Never use ASCII art, Mermaid or PlantUML instead.
---

# draw.io diagram

Every diagram in this repo is one editable `docs/<name>.drawio.svg` file plus a
text description next to it. Follow these steps in order.

## 1. Plan the content

- Pick a short, lowercase, hyphenated `<name>` (for example `partition-layout`).
- Write the **text description first** (step 4): a numbered flow for a process,
  prose or a table for a structure. The diagram must show the same facts, no
  more and no fewer. This keeps picture and text in sync.
- Reuse the style of `docs/architecture.drawio.svg` (zones with a light fill and
  a coloured border, white rounded boxes, `#333333` arrows, Helvetica, labels of
  11-12 px) so the diagrams look like one set.

## 2. Write the file

The file is an SVG whose root `<svg>` element carries the draw.io model in its
`content` attribute (an XML-escaped `<mxfile>`). draw.io opens the model; every
other viewer shows the SVG drawing.

- **Update an existing diagram:** edit both parts. Change the `mxCell`s in the
  `content` model *and* the matching SVG shapes, or regenerate the SVG from the
  model. Never change only one side: draw.io would show something different from
  GitHub.
- **New diagram:** build the `mxGraphModel` (cells with `mxGeometry`), then
  render the same geometry as plain SVG elements. A small Python script in the
  scratchpad that emits both from one list of shapes is the reliable way.
- Prefer an uncompressed model (`<diagram><mxGraphModel>...`), so diffs are
  readable. A compressed model (base64 deflate) from draw.io is also accepted.
- **White background, in both parts:**
  - model: `<mxGraphModel ... background="#ffffff">`
  - image: a first element `<rect x="0" y="0" width="W" height="H" fill="#ffffff"/>`
    covering the viewBox, or `style="background-color: #ffffff"` on `<svg>`.
- Self-contained: no `<script>`, no external images or fonts (GitHub shows the
  file through `<img>`, which loads nothing external). Use plain `<text>` labels.
  If the file comes from draw.io's own export with `<foreignObject>` labels, keep
  the `<switch>` text fallback draw.io adds.
- If the user edits in draw.io (VS Code extension `hediet.vscode-drawio` or
  app.diagrams.net), they should set File > Properties > Background to white and
  keep the `.drawio.svg` extension; the extension then writes both parts itself.

## 3. Check the file

Run the checker on every changed diagram:

```sh
python3 -I .claude/skills/drawio-diagram/check_drawio_svg.py docs/<name>.drawio.svg
```

It checks: well-formed SVG with a size, a decodable draw.io model, a white
background in the model and in the image, and no script or external resource.
Fix every `error` and do not continue until it prints `OK`.

Then look at the picture. If a rasterizer is installed (`rsvg-convert`,
`inkscape`), convert it to PNG in the scratchpad and view it; otherwise ask the
user to open it. Confirm that labels fit their boxes, nothing overlaps, and
arrows point the right way.

Optional, only with the user's permission (it pulls a third-party image):
a headless draw.io export proves draw.io itself parses the file:
`docker run --rm -v "$PWD/docs:/data" rlespinasse/drawio-desktop-headless -x -f png -o /tmp/out.png /data/<name>.drawio.svg`.

## 4. Embed it with a text description

In the Markdown file (README.md or a doc under `docs/`):

```markdown
![<short alt text>](docs/<name>.drawio.svg)

*Source: [docs/<name>.drawio.svg](docs/<name>.drawio.svg) is an editable draw.io
diagram (VS Code extension `hediet.vscode-drawio`, or app.diagrams.net).*

1. <step one, the same content as the picture>
2. ...
```

- The path is relative to the Markdown file (from a file in `docs/`, write
  `<name>.drawio.svg`).
- The description is pure text: no ASCII art, no Mermaid or PlantUML. Someone
  who cannot see the image must get the same information.

## 5. Check the rendering on GitHub

After the branch is pushed (see the `work-on-issue` skill), confirm GitHub
renders the embed:

```sh
gh api "repos/{owner}/{repo}/contents/<file>.md?ref=<branch>" \
  -H "Accept: application/vnd.github.html" | grep -o '<img[^>]*drawio[^>]*>'
```

It must print an `<img>` tag pointing at the diagram. Ask the user to glance at
the page in dark mode if the diagram is new.
