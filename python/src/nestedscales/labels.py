"""Labels -- display names for members and frames, in named variants (port of
R/labels.R).

A long table keyed by (frame, member, variant): one row per display name.
The table is sparse -- a frame, or a member, without a row is shown by its
code -- and a row with a null `member` names the frame itself. Labels are for
display only; `scale_match()` resolves spellings through the alias table.
"""
from __future__ import annotations

from collections.abc import Sequence
from typing import Any

import pyarrow as pa
import pyarrow.compute as pc

from ._backend import as_table
from ._utils import _preview, _stop
from .attributes import _as_list, _replace, _unique
from .scale_class import (
    DEFAULT_VARIANT,
    LABEL_SCHEMA,
    NestedScale,
    _check_frame,
    _check_scale,
    _label_keys,
    _label_variant,
    empty_labels,
)


def _as_labels(labels: Any, variant: str | None = None) -> pa.Table:
    """Coerce user input to the label schema; a table without a `variant`
    column takes `variant` (default `"label"`). Membership is checked by the
    validator."""
    if labels is None:
        return empty_labels()
    t = as_table(labels, "labels")
    if "variant" in t.column_names:
        if variant is not None:
            _stop("`labels` already has a `variant` column; drop `variant=`")
    else:
        if variant is None:
            variant = DEFAULT_VARIANT
        if not isinstance(variant, str) or variant == "":
            _stop("`variant` must be a single string")
        t = t.append_column("variant", pa.array([variant] * t.num_rows, pa.string()))
    missing = [c for c in LABEL_SCHEMA.names if c not in t.column_names]
    if missing:
        _stop("`labels` is missing column(s): %s", _preview(missing))
    extra = [c for c in t.column_names if c not in LABEL_SCHEMA.names]
    if extra:
        _stop("`labels` has unknown column(s): %s", _preview(extra))
    cols = {}
    for c in LABEL_SCHEMA.names:
        col = t[c]
        if pa.types.is_dictionary(col.type):
            col = col.cast(pa.string())
        cols[c] = col.cast(pa.string())
    return pa.table(cols, schema=LABEL_SCHEMA)


def attach_labels_scale(x: NestedScale, labels: Any, variant: str | None = None,
                        default: str | None = None,
                        overwrite: bool = False) -> NestedScale:
    """Add display names to the label table of a scale.

    `labels` has the columns `frame`, `member`, `label` and, unless `variant`
    is given, optionally `variant`; a null `member` labels the frame itself.
    `variant` fills the `variant` column when the table has none (default
    `"label"`). `default` names the variant a lookup uses when it names none;
    None keeps the current one (initially the first variant attached). A
    (frame, member, variant) already present is an error unless
    `overwrite=True`, which replaces it.
    """
    _check_scale(x)
    new = _as_labels(labels, variant=variant)
    old = x.labels
    k_new = set(_label_keys(new))
    clash = [k in k_new for k in _label_keys(old)]
    if any(clash):
        if not overwrite:
            _stop("label(s) already present: %s; pass overwrite = TRUE to replace",
                  _preview(_unique(
                      "%s/%s" % (f, "NA" if u is None else u)
                      for (f, u, _), hit in zip(_label_keys(old), clash, strict=True)
                      if hit)))
        old = old.filter(pa.array([not c for c in clash], pa.bool_()))
    out = pa.concat_tables([old, new])
    if default is None:
        return _replace(x, labels=out)
    if not isinstance(default, str) or default == "":
        _stop("`default` must be a single string")
    have = out["variant"].to_pylist()
    if default not in have:
        _stop("`default` must be a variant of the label table: %s",
              _preview(_unique(have)))
    return _replace(x, labels=out, meta={**x.meta, "default_label": default})


def scale_labels(x: NestedScale, frame: str | None = None,
                 variant: str | Sequence[str] | None = None) -> pa.Table:
    """The label rows (`frame`, `member`, `variant`, `label`), optionally of
    one frame and/or some variants. A row with a null `member` is the label
    of the frame itself."""
    _check_scale(x)
    lb = x.labels
    if frame is not None:
        _check_frame(x, frame)
        lb = lb.filter(pc.equal(lb["frame"], frame))
    if variant is not None:
        lb = lb.filter(pc.is_in(lb["variant"],
                                value_set=pa.array(_as_list(variant), pa.string())))
    return lb


def scale_label(x: NestedScale, members: str | None | Sequence[str | None],
                frame: str, variant: str | None = None) -> list[str]:
    """One display name per code of `members` at `frame`.

    A code without a label of the chosen variant is returned unchanged; None
    stands for the frame itself and gives the frame's label, or its name
    when it has none. `variant=None` uses the default variant of the scale.
    """
    _check_scale(x)
    _check_frame(x, frame)
    if members is None or isinstance(members, str):
        members = [members]
    members = [None if m is None else str(m) for m in members]
    variant = _label_variant(x, variant)
    found: dict = {}
    for f, u, va, lab in zip(*(x.labels[c].to_pylist() for c in LABEL_SCHEMA.names),
                             strict=True):
        if f == frame and va == variant:
            found.setdefault(u, lab)
    return [found[m] if m in found else (frame if m is None else m)
            for m in members]
