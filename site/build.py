#!/usr/bin/env python3
# Copyright 2026 Abdul Muheet Ghani
# SPDX-License-Identifier: Apache-2.0
#
# Builds the NandTier documentation website (GitHub Pages) from site/pages/*.md
# into docs/. Run from the repository root:  python3 site/build.py
# Needs: python3 -m pip install markdown

import json, re, shutil, datetime
from pathlib import Path
import markdown

SITE = "https://nandtier.github.io/nandtier/"     # change when a custom domain is set
REPO = "https://github.com/NandTier/nandtier"
COURSE = "https://www.nandtier.com/"                 # the Gates to Games course

HERE = Path(__file__).resolve().parent
OUT = HERE.parent / "docs"
ORDER = ["index", "getting-started", "tang-nano-9k", "architecture", "risc-v-cpu", "boot-rom-and-flash",
         "hdmi-ppu", "games", "open-source-fpga-toolchain", "compare", "faq"]
TODAY = datetime.date.today().isoformat()


def load(slug):
    text = (HERE / "pages" / f"{slug}.md").read_text()
    m = re.match(r"---\n(.*?)\n---\n", text, re.S)
    meta = dict(line.split(": ", 1) for line in m.group(1).splitlines())
    return meta, text[m.end():]


def url(slug):
    return SITE if slug == "index" else f"{SITE}{slug}.html"


def href(slug):
    return "./" if slug == "index" else f"{slug}.html"


def course_box():
    link = f'<a href="{COURSE}">Gates to Games</a>' if COURSE else "<strong>Gates to Games</strong>"
    soon = "" if COURSE else " It is launching soon."
    return (f'<aside class="course"><strong>Learn it step by step.</strong>'
            f'<p>{link} teaches NandTier from the first logic gate to the games, '
            f'with a voiced film for every lesson.{soon}</p></aside>')


def faq_ld(body):
    qa = re.findall(r"^### (.+?)\n(.+?)(?=\n### |\Z)", body, re.S | re.M)
    strip = lambda s: re.sub(r"\[(.+?)\]\(.+?\)", r"\1", re.sub(r"[*`]", "", s)).strip()
    return {"@context": "https://schema.org", "@type": "FAQPage",
            "mainEntity": [{"@type": "Question", "name": strip(q),
                            "acceptedAnswer": {"@type": "Answer", "text": strip(a)}} for q, a in qa]}


def page(slug, pages):
    meta, body = pages[slug]
    md = markdown.Markdown(extensions=["tables", "fenced_code", "toc", "attr_list"],
                           extension_configs={"toc": {"anchorlink": True, "anchorlink_class": "hl"}})
    html = md.convert(body)
    cur = ' aria-current="page"'
    nav = "".join(f'<a href="{href(s)}"{cur if s == slug else ""}>{pages[s][0]["nav"]}</a>' for s in ORDER)
    i = ORDER.index(slug)
    prev = f'<a href="{href(ORDER[i-1])}"><small>Previous</small>{pages[ORDER[i-1]][0]["nav"]}</a>' if i > 0 else "<span></span>"
    nxt = f'<a href="{href(ORDER[i+1])}"><small>Next</small>{pages[ORDER[i+1]][0]["nav"]}</a>' if i + 1 < len(ORDER) else ""
    ld = [{"@context": "https://schema.org", "@type": "BreadcrumbList", "itemListElement": [
        {"@type": "ListItem", "position": 1, "name": "NandTier", "item": SITE}] + (
        [{"@type": "ListItem", "position": 2, "name": meta["nav"], "item": url(slug)}] if slug != "index" else [])}]
    if slug == "index":
        ld.append({"@context": "https://schema.org", "@type": "SoftwareSourceCode", "name": "NandTier",
                   "description": meta["description"], "url": SITE, "codeRepository": REPO,
                   "programmingLanguage": ["Verilog", "C", "Python", "RISC-V assembly"], "license": "https://www.apache.org/licenses/LICENSE-2.0",
                   "author": {"@type": "Person", "name": "Abdul Muheet Ghani"},
                   "keywords": "RISC-V, RV32IM, FPGA, Tang Nano 9K, Gowin, SoC, HDMI, Verilog, open-source toolchain"})
    elif slug == "faq":
        ld.append(faq_ld(body))
    else:
        ld.append({"@context": "https://schema.org", "@type": "TechArticle", "headline": meta["title"],
                   "description": meta["description"], "url": url(slug), "dateModified": TODAY,
                   "author": {"@type": "Person", "name": "Abdul Muheet Ghani"},
                   "isPartOf": {"@type": "WebSite", "name": "NandTier", "url": SITE}})
    title = meta["title"] if slug == "index" else f'{meta["title"]} | NandTier'
    return f'''<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<title>{title}</title>
<meta name="description" content="{meta["description"]}">
<link rel="canonical" href="{url(slug)}">
<link rel="icon" href="assets/icon-64.png">
<link rel="apple-touch-icon" href="assets/icon-180.png">
<meta property="og:type" content="{"website" if slug == "index" else "article"}">
<meta property="og:site_name" content="NandTier">
<meta property="og:title" content="{meta["title"]}">
<meta property="og:description" content="{meta["description"]}">
<meta property="og:url" content="{url(slug)}">
<meta property="og:image" content="{SITE}images/banner.png">
<meta name="twitter:card" content="summary_large_image">
<meta name="theme-color" content="#0b1016">
<link rel="preload" href="assets/ibm-plex-sans-latin-400-normal.woff2" as="font" type="font/woff2" crossorigin>
<link rel="stylesheet" href="style.css">
<script type="application/ld+json">{json.dumps(ld, ensure_ascii=False)}</script>
</head>
<body>
<header><div class="bar"><a class="brand" href="./"><img src="assets/icon-64.png" alt="" width="30" height="30">NandTier</a>
<nav aria-label="Documentation">{nav}</nav>
<a class="gh" href="{REPO}">GitHub</a></div></header>
<main>
{html}
{course_box() if slug not in ("faq",) else ""}
<nav class="pager" aria-label="Pages">{prev}{nxt}</nav>
</main>
<footer><div class="bar">NandTier by Abdul Muheet Ghani · <a href="{REPO}">Source on GitHub</a> · <a href="{REPO}/blob/main/LICENSE">Apache 2.0</a> · <a href="llms.txt">llms.txt</a></div></footer>
</body>
</html>
'''


def main():
    pages = {s: load(s) for s in ORDER}
    OUT.mkdir(exist_ok=True)
    (OUT / "assets").mkdir(exist_ok=True)
    for f in (HERE / "assets").iterdir():
        shutil.copy(f, OUT / "assets" / f.name)
    shutil.copy(HERE / "style.css", OUT / "style.css")
    for s in ORDER:
        (OUT / ("index.html" if s == "index" else f"{s}.html")).write_text(page(s, pages))
    (OUT / ".nojekyll").write_text("")
    (OUT / "robots.txt").write_text(f"User-agent: *\nAllow: /\n\nSitemap: {SITE}sitemap.xml\n")
    (OUT / "sitemap.xml").write_text('<?xml version="1.0" encoding="UTF-8"?>\n<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">\n' +
        "".join(f"  <url><loc>{url(s)}</loc><lastmod>{TODAY}</lastmod></url>\n" for s in ORDER) + "</urlset>\n")
    llms = [f"# NandTier\n\n> {pages['index'][0]['description']}\n",
            f"NandTier is an open-source (Apache 2.0) RISC-V system-on-chip by Abdul Muheet Ghani. Source: {REPO}\n",
            "## Documentation\n"]
    llms += [f"- [{pages[s][0]['title']}]({url(s)}): {pages[s][0]['description']}" for s in ORDER]
    llms.append(f"\n## Key facts\n\n- CPU: RV32IM, multi-cycle, 24.975 MHz, no interrupts, no C extension\n- Boards: Sipeed Tang Nano 9K (default), Tang Nano 20K, Radiona ULX3S\n"
                "- Memory map: flash XIP 0x00000000 (8 MiB), SRAM 0x40000000 (8 KiB), boot RAM 0x80000000 (8 KiB)\n"
                "- Video: 640x480 HDMI, NES-style PPU (256x240, tiles, 64 sprites), 80x25 text terminal\n"
                "- Storage: SPI flash with 4 KiB cache, SD card over SPI; boot ROM programs the flash over UART\n"
                "- Tools: Yosys, nextpnr, Apicula, openFPGALoader, RISC-V GCC; installer: setup/setup.sh\n"
                "- Games: 8 cartridges on the SD card, C game SDK (ngame)\n")
    if COURSE:
        llms.append(f"## Course\n\n- [Gates to Games]({COURSE}): a course that teaches NandTier from logic gates to games.\n")
    (OUT / "llms.txt").write_text("\n".join(llms))
    (OUT / "404.html").write_text(page("index", pages).replace("<head>", f'<head>\n<base href="{SITE}">', 1)
                                  .replace("<main>", '<main><p><strong>That page does not exist.</strong> Here is the NandTier home page.</p>', 1))
    print(f"built {len(ORDER)} pages into {OUT}")


if __name__ == "__main__":
    main()
