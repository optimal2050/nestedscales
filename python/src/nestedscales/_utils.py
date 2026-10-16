"""Internal utilities: error and warning classes, message helpers.

Port of R/utils.R. Messages are kept verbatim so both bindings report the
same text.
"""
from __future__ import annotations

import warnings
from collections.abc import Iterable


class NestedScalesError(ValueError):
    """Raised for every user-facing error (R: `.stop()`)."""


class NestedScalesWarning(UserWarning):
    """Issued for every user-facing warning (R: `.warn()`)."""


def _stop(msg: str, *args: object) -> None:
    raise NestedScalesError(msg % args if args else msg)


def _warn(msg: str, *args: object) -> None:
    warnings.warn(msg % args if args else msg, NestedScalesWarning, stacklevel=3)


def _preview(x: Iterable[object], n: int = 3) -> str:
    """Truncated comma-separated preview of a sequence."""
    x = [str(v) for v in x]
    if len(x) <= n:
        return ", ".join(x)
    return "%s, ... (%d total)" % (", ".join(x[:n]), len(x))


def _as_str_tuple(x: object) -> tuple:
    """A string or a sequence of strings as a tuple (R: a character vector).

    A bare string is one element, never split into characters. Non-string
    elements are kept as they are so the validator can name them.
    """
    if x is None:
        return ()
    if isinstance(x, str):
        return (x,)
    return tuple(x)
