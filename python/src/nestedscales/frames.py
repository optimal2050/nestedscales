"""Frame vocabulary (port of R/frames.R).

A frame is one resolution of a scale. Names are validated for syntax only:
a frame name must be a syntactically valid R name, so the same scale can be
written by one binding and read by the other without renaming columns.
"""
from __future__ import annotations

import re
from collections.abc import Iterable

# R's `make.names(x) == x`: a letter, or a dot not followed by a digit, then
# letters, digits, dots and underscores.
_SYNTACTIC = re.compile(r"^(?:[^\W\d_]|\.(?![0-9]))[\w.]*$")

# R reserved words: `make.names()` appends a dot to these, so they fail.
_R_RESERVED = frozenset({
    "if", "else", "repeat", "while", "function", "for", "in", "next", "break",
    "TRUE", "FALSE", "NULL", "Inf", "NaN", "NA", "NA_integer_", "NA_real_",
    "NA_character_", "NA_complex_",
})

#: Column names with a fixed meaning that cannot be frame names. The atom key
#: is reserved too, except as the name of the finest frame.
RESERVED_COLS = ("share", ".weight", ".order")


def is_valid_frame(x: str | Iterable[object]) -> bool | list[bool]:
    """Validate frame names.

    Returns a bool for a single string, a list of bools for a sequence.
    """
    def ok(v: object) -> bool:
        return (isinstance(v, str) and v != "" and v not in _R_RESERVED
                and _SYNTACTIC.match(v) is not None)

    if isinstance(x, str):
        return ok(x)
    return [ok(v) for v in x]
