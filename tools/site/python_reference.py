"""Write the Python site's sources from the R site's structure.

Usage (from the repository root, with the Python binding installed):
    python tools/site/python_reference.py

Reads `DESCRIPTION` (package name) and `_pkgdown.yml`, and writes under
`python/`:
  * `docs/index.md`            -- the binding's README;
  * `docs/reference/*.md`      -- one page per R reference section, listing the
                                  same functions (those the binding has);
  * `docs/reference/index.md`  -- the section list and the R-only topics;
  * `docs/assets/logo.png`     -- the package logo, when `man/figures/` has one;
  * `mkdocs.yml`               -- the site configuration and navigation.
Every Python function belongs to exactly one page: those the R reference does
not list go to "Python only". The same file serves every package of the
family; only `DESCRIPTION` and `_pkgdown.yml` differ.
"""
from __future__ import annotations

import importlib
import re
import shutil
from pathlib import Path

import yaml

ROOT = Path(__file__).resolve().parents[2]
PY = ROOT / "python"
DOCS = PY / "docs"
REF = DOCS / "reference"

# the Python name of R's summary() for each package's class
SUMMARY = {"nestedscales": "scale_summary", "timescales": "calendar_summary",
           "geoscales": "geoscale_summary"}


def package() -> str:
    for line in (ROOT / "DESCRIPTION").read_text(encoding="utf-8").splitlines():
        if line.startswith("Package:"):
            return line.split(":", 1)[1].strip()
    raise SystemExit("no Package field in DESCRIPTION")


def slug(s: str) -> str:
    return re.sub(r"[^a-z0-9]+", "-", s.lower()).strip("-")


def rd_aliases(topic: str) -> list[str]:
    """The functions a help topic documents: its `\\alias{}` entries."""
    rd = ROOT / "man" / ("%s.Rd" % topic)
    if not rd.exists():
        return [topic]
    found = re.findall(r"\\alias\{([^}]*)\}", rd.read_text(encoding="utf-8"))
    return [topic] + [a for a in found if a != topic]


def no_counterpart(topic: str) -> bool:
    """A method, an S7 class page or the package page: no free function."""
    return topic.startswith("[") or topic.endswith("-package")


def expand(item: str, names: list[str], pkg: str) -> list[str]:
    m = re.fullmatch(r'starts_with\("([^"]+)"\)', item)
    if m:
        return [n for n in names if n.startswith(m.group(1))]
    topic = item.strip("`")
    if topic.startswith("summary."):
        fn = SUMMARY.get(pkg)
        return [fn] if fn in names else []
    if no_counterpart(topic):
        return []
    return rd_aliases(topic)


def main() -> None:
    pkg = package()
    mod = importlib.import_module(pkg)
    cfg = yaml.safe_load((ROOT / "_pkgdown.yml").read_text(encoding="utf-8"))
    public = sorted(mod.__all__)
    placed: set[str] = set()
    r_only: list[str] = []
    sections = []
    for sec in cfg["reference"]:
        listed = []
        for item in sec["contents"]:
            fns = expand(item, public, pkg)
            topic = item.strip("`")
            if (not any(n in public for n in fns) and not item.startswith("starts_with")
                    and not topic.startswith("summary.") and not no_counterpart(topic)):
                r_only.append(topic)
            listed += fns
        have = [n for n in dict.fromkeys(listed) if n in public and n not in placed]
        placed.update(have)
        if have:
            sections.append((sec["title"], sec.get("desc", ""), have))
    extra = [n for n in public if n not in placed]
    if extra:
        sections.append(("Python only",
                         "Functions without an R counterpart in the reference.", extra))

    if REF.exists():
        shutil.rmtree(REF)
    REF.mkdir(parents=True)
    shutil.copyfile(PY / "README.md", DOCS / "index.md")
    logo = ROOT / "man" / "figures" / "logo.png"
    if logo.exists():
        (DOCS / "assets").mkdir(exist_ok=True)
        shutil.copyfile(logo, DOCS / "assets" / "logo.png")
    has_api = (ROOT / "API.md").exists()

    nav_ref = [{"Overview": "reference/index.md"}]
    intro = ("The functions of the Python binding, grouped as in the "
             "[R reference](../../r/reference/index.html). Names and argument "
             "order match R.")
    if has_api:
        intro += " See also the [cross-language table](../../r/API.html)."
    lines = ["# Reference", "", intro, ""]
    for i, (title, desc, fns) in enumerate(sections, 1):
        fname = "%02d-%s.md" % (i, slug(title))
        body = ["# %s" % title, ""] + ([" ".join(desc.split()), ""] if desc else [])
        body += ["::: %s.%s" % (pkg, f) for f in fns]
        (REF / fname).write_text("\n\n".join(body) + "\n", encoding="utf-8")
        nav_ref.append({title: "reference/" + fname})
        lines.append("* [%s](%s) -- %s" % (title, fname, ", ".join(
            "`%s`" % f for f in fns)))
    if r_only:
        lines += ["", "## R only", "",
                  "Not in the binding yet: "
                  + ", ".join("`%s`" % f for f in r_only) + "."]
    (REF / "index.md").write_text("\n".join(lines) + "\n", encoding="utf-8")

    theme = {"name": "material",
             "features": ["navigation.sections", "navigation.top",
                          "content.code.copy", "search.highlight"],
             "palette": [
                 {"media": "(prefers-color-scheme: light)", "scheme": "default",
                  "toggle": {"icon": "material/brightness-7", "name": "Dark mode"}},
                 {"media": "(prefers-color-scheme: dark)", "scheme": "slate",
                  "toggle": {"icon": "material/brightness-4", "name": "Light mode"}}]}
    if logo.exists():
        theme["logo"] = "assets/logo.png"
        theme["favicon"] = "assets/logo.png"
    nav = [{"Home": "index.md"}, {"Reference": nav_ref}, {"R package": "../r/"}]
    if has_api:
        nav.append({"Cross-language API": "../r/API.html"})
    mk = {
        "site_name": "%s for Python" % pkg,
        "site_url": "https://optimal2050.github.io/%s/python/" % pkg,
        "repo_url": "https://github.com/optimal2050/%s" % pkg,
        "docs_dir": "docs",
        "site_dir": "../docs/python",
        "theme": theme,
        "plugins": ["search", {"mkdocstrings": {"handlers": {"python": {
            "paths": ["src"],
            "options": {"show_root_heading": True, "show_root_full_path": False,
                        "show_source": False, "separate_signature": True,
                        "show_signature_annotations": True,
                        "heading_level": 2, "docstring_style": "google"}}}}}],
        "markdown_extensions": ["admonition", "pymdownx.highlight",
                                "pymdownx.superfences", "toc"],
        "nav": nav,
    }
    (PY / "mkdocs.yml").write_text(
        "# Generated by tools/site/python_reference.py -- do not edit by hand.\n"
        + yaml.safe_dump(mk, sort_keys=False), encoding="utf-8")
    print("%s python reference: %d pages, %d functions, %d R-only"
          % (pkg, len(sections), len(public), len(r_only)))


if __name__ == "__main__":
    main()
