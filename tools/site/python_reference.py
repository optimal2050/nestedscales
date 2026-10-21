"""Write the Python site's sources from the R site's structure.

Usage (from the repository root, with the Python binding installed):
    python tools/site/python_reference.py

Reads `_pkgdown.yml` and writes, under `python/`:
  * `docs/index.md`            -- the binding's README;
  * `docs/reference/*.md`      -- one page per R reference section, listing the
                                  same functions (those the binding has);
  * `docs/reference/index.md`  -- the section list and the R-only functions;
  * `mkdocs.yml`               -- the site configuration and navigation.
Every Python function belongs to exactly one page: those the R reference does
not list go to "Python only".
"""
from __future__ import annotations

import re
import shutil
from pathlib import Path

import nestedscales as ns
import yaml

ROOT = Path(__file__).resolve().parents[2]
PY = ROOT / "python"
DOCS = PY / "docs"
REF = DOCS / "reference"


def slug(s: str) -> str:
    return re.sub(r"[^a-z0-9]+", "-", s.lower()).strip("-")


def rd_aliases(topic: str) -> list[str]:
    """The functions a help topic documents: its `\\alias{}` entries."""
    rd = ROOT / "man" / ("%s.Rd" % topic)
    if not rd.exists():
        return [topic]
    found = re.findall(r"\\alias\{([^}]*)\}", rd.read_text(encoding="utf-8"))
    return [topic] + [a for a in found if a != topic]


# R topics whose Python counterpart has another name; a method or the package
# page has no free-function counterpart and maps to nothing.
R_TO_PY = {"summary.NestedScale": ["scale_summary"], "[.NestedScale": [],
           "summary.ScaleProduct": [], "nestedscales-package": []}


def expand(item: str, names: list[str]) -> list[str]:
    m = re.fullmatch(r'starts_with\("([^"]+)"\)', item)
    if m:
        return [n for n in names if n.startswith(m.group(1))]
    topic = item.strip("`")
    if topic in R_TO_PY:
        return R_TO_PY[topic]
    return rd_aliases(topic)


def main() -> None:
    cfg = yaml.safe_load((ROOT / "_pkgdown.yml").read_text(encoding="utf-8"))
    public = sorted(ns.__all__)
    placed: set[str] = set()
    r_only: list[str] = []
    sections = []
    for sec in cfg["reference"]:
        listed = []
        for item in sec["contents"]:
            fns = expand(item, public)
            if (not any(n in public for n in fns) and not item.startswith("starts_with")
                    and item.strip("`") not in R_TO_PY):
                r_only.append(item.strip("`"))
            listed += fns
        have = [n for n in dict.fromkeys(listed) if n in public and n not in placed]
        placed.update(have)
        if have:
            sections.append((sec["title"], sec.get("desc", ""), have))
    extra = [n for n in public if n not in placed]
    if extra:
        sections.append(("Python only", "Functions without an R counterpart "
                         "in the reference.", extra))

    if REF.exists():
        shutil.rmtree(REF)
    REF.mkdir(parents=True)
    shutil.copyfile(PY / "README.md", DOCS / "index.md")
    nav_ref = [{"Overview": "reference/index.md"}]
    lines = ["# Reference", "",
             "The functions of the Python binding, grouped as in the "
             "[R reference](../../r/reference/index.html). Names and argument "
             "order match R; see the [cross-language table]"
             "(../../r/API.html).", ""]
    for i, (title, desc, fns) in enumerate(sections, 1):
        fname = "%02d-%s.md" % (i, slug(title))
        body = ["# %s" % title, ""] + ([desc, ""] if desc else [])
        body += ["::: nestedscales.%s" % f for f in fns]
        (REF / fname).write_text("\n\n".join(body) + "\n", encoding="utf-8")
        nav_ref.append({title: "reference/" + fname})
        lines.append("* [%s](%s) -- %s" % (title, fname, ", ".join(
            "`%s`" % f for f in fns)))
    if r_only:
        lines += ["", "## R only", "",
                  "Not in the binding yet: " + ", ".join("`%s`" % f
                                                         for f in r_only) + "."]
    (REF / "index.md").write_text("\n".join(lines) + "\n", encoding="utf-8")

    mk = {
        "site_name": "nestedscales for Python",
        "site_url": "https://optimal2050.github.io/nestedscales/python/",
        "repo_url": "https://github.com/optimal2050/nestedscales",
        "docs_dir": "docs",
        "site_dir": "../docs/python",
        "theme": {"name": "material",
                  "features": ["navigation.sections", "navigation.top",
                               "content.code.copy", "search.highlight"],
                  "palette": [
                      {"media": "(prefers-color-scheme: light)",
                       "scheme": "default",
                       "toggle": {"icon": "material/brightness-7",
                                  "name": "Dark mode"}},
                      {"media": "(prefers-color-scheme: dark)",
                       "scheme": "slate",
                       "toggle": {"icon": "material/brightness-4",
                                  "name": "Light mode"}}]},
        "plugins": ["search", {"mkdocstrings": {"handlers": {"python": {
            "paths": ["src"],
            "options": {"show_root_heading": True, "show_root_full_path": False,
                        "show_source": False, "separate_signature": True,
                        "show_signature_annotations": True,
                        "heading_level": 2, "docstring_style": "google"}}}}}],
        "markdown_extensions": ["admonition", "pymdownx.highlight",
                                "pymdownx.superfences", "toc"],
        "nav": [{"Home": "index.md"}, {"Reference": nav_ref},
                {"R package": "../r/"},
                {"Cross-language API": "../r/API.html"}],
    }
    (PY / "mkdocs.yml").write_text(
        "# Generated by tools/site/python_reference.py -- do not edit by hand.\n"
        + yaml.safe_dump(mk, sort_keys=False), encoding="utf-8")
    print("python reference: %d pages, %d functions, %d R-only"
          % (len(sections), len(public), len(r_only)))


if __name__ == "__main__":
    main()
