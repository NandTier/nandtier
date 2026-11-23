# NandTier website

The source of https://nandtier.github.io/nandtier/ (GitHub Pages, served from `docs/`).

- `pages/*.md`: one Markdown file per page. The block between the `---` lines sets the page's slug, title, menu name and search description.
- `style.css`, `assets/`: the look, fonts and icons.
- `build.py`: turns the pages into `docs/*.html`, and writes `sitemap.xml`, `robots.txt`, `llms.txt` and `404.html`.

Edit a page, then run `make site` (needs `python3 -m pip install markdown`) and commit `site/` and `docs/` together.

When the Gates to Games course is online, set `COURSE` at the top of `build.py` to its address and rebuild: every page then links to it. For a custom domain, set `SITE` too.
