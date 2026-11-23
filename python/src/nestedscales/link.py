"""The identity of a scale (port of `scale_id()` in R/link.R).

The data link of the R package (`bind_scale()` and the `scale_member` vector)
is not part of this binding; the identity it compares is.
"""
from __future__ import annotations

import hashlib

from .scale_class import NestedScale, _check_scale, _scale_name, _strings


def _id_text(x: NestedScale) -> str:
    """The canonical text the identity hashes."""
    cols = list(dict.fromkeys([x.leaf, *x.frames]))
    tab = [["" if v is None else v for v in _strings(x.leaftable, c)] for c in cols]
    # leaves in the order of the UTF-8 bytes of the leaf code (R: a radix
    # sort in the C locale)
    order = sorted(range(len(tab[0])), key=lambda i: tab[0][i].encode("utf-8"))
    rows = ["\t".join(col[i] for col in tab) for i in order]
    # the literal prefix `key=` is part of the hashed text
    return "\n".join(["key=" + x.leaf, "frames=" + "\t".join(x.frames), *rows])


def _structure_hash(x: NestedScale) -> str:
    return hashlib.md5(_id_text(x).encode("utf-8")).hexdigest()[:8]


def scale_id(x: NestedScale) -> str:
    """The identity of a scale: `"<name>@<hash>"`.

    The hash covers the leaf column, the frames and the leaf-to-frame
    memberships; weights, attributes, aliases, labels and the order of rows
    or members do not enter, so adding a weight keeps the identity while a
    subset or a re-grouping is a different scale. Two objects with the same
    structure under different names share the hash.

    The hash is the first eight hexadecimal digits of the MD5 of a canonical
    UTF-8 text: the line `key=<leaf column name>`, the line `frames=` with
    the frame names tab-separated, then one tab-separated line per leaf (its
    code in the leaf column first, then its code at each frame, empty where
    unassigned), leaves sorted by the bytes of the leaf code, lines joined
    by a line feed. Both bindings give the same identity for the same scale.
    """
    _check_scale(x)
    return "%s@%s" % (_scale_name(x, require=False), _structure_hash(x))


def _id_hash(id_: str) -> str:
    """The structure hash of an identity."""
    return id_.rsplit("@", 1)[-1]
