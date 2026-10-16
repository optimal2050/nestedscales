"""ScaleProduct -- several scales combined into one multi-index (port of the
class and accessors in R/product-class.R; `recast_product()` is R-only for
now).

A product HOLDS scales; its atoms are never materialised. Data on a product
carries one key column per axis, never a pasted composite.
"""
from __future__ import annotations

import math
from collections.abc import Mapping
from dataclasses import dataclass, field
from typing import Any

from ._utils import _preview, _stop
from .navigate import scale_coverage
from .scale_class import NestedScale, scale_frames, scale_weights


@dataclass(frozen=True, eq=False, repr=False)
class ScaleProduct:
    """Named axes (each a named NestedScale) and one data key column per axis."""

    axes: dict[str, NestedScale]
    keys: dict[str, str]
    joint_weights: Any = None
    meta: dict[str, Any] = field(default_factory=dict)

    def __post_init__(self) -> None:
        errs = _validate_product(self)
        if errs:
            _stop("<nestedscales::ScaleProduct> object is invalid:\n%s",
                  "\n".join("- " + e for e in errs))

    def __eq__(self, other: object) -> bool:
        if not isinstance(other, ScaleProduct):
            return NotImplemented
        return (self.axes == other.axes and self.keys == other.keys
                and self.meta == other.meta)

    __hash__ = None  # type: ignore[assignment]

    def __repr__(self) -> str:
        return "<ScaleProduct[%s]>" % " x ".join(
            "%s:%d" % (a, s.leaftable.num_rows) for a, s in self.axes.items())


def _validate_product(self: ScaleProduct) -> list[str]:
    errs: list[str] = []
    axes, keys = self.axes, self.keys
    if not isinstance(axes, Mapping):
        return ["`axes` must be a list of NestedScale objects"]
    if len(axes) < 2:
        errs.append("a product needs at least 2 axes")
    if any(not isinstance(k, str) or k == "" for k in axes):
        errs.append("every axis must be named")
    for nm, a in axes.items():
        if isinstance(a, ScaleProduct):
            errs.append("axis `%s` is itself a product; pass its axes directly "
                        "instead of nesting" % nm)
            continue
        if not isinstance(a, NestedScale):
            errs.append("axis `%s` is not a NestedScale object" % nm)
            continue
        if not a.meta.get("name"):
            errs.append("axis `%s` has no name; a product's axes must be named "
                        "scales (set meta$name)" % nm)
    if not isinstance(keys, Mapping):
        errs.append("`keys` must be a named character vector")
    elif not errs:
        if set(keys) != set(axes):
            errs.append("`keys` must have exactly one entry per axis")
        else:
            vals = list(keys.values())
            dup = list(dict.fromkeys(v for i, v in enumerate(vals) if v in vals[:i]))
            if dup:
                errs.append("axes resolve to the same key column: %s. Data on a "
                            "product carries one column per axis, so the columns "
                            "must differ -- pass `keys=` to name them."
                            % _preview(dup))
    if self.joint_weights is not None:
        errs.append("`joint_weights` is reserved and must be NULL")
    return errs


def scale_product(name: str = "", desc: str = "",
                  keys: Mapping[str, str] | None = None, joint_weights: Any = None,
                  **axes: NestedScale) -> ScaleProduct:
    """Combine named scales into a product: `scale_product(time=cal, space=gs)`.

    Keys default to each axis's own key; when two collide, the axis names.
    """
    if not axes:
        _stop("pass the axes as named arguments, e.g. scale_product(time = cal)")
    own = {a: (s.key if isinstance(s, NestedScale) else None)
           for a, s in axes.items()}
    if keys is None:
        vals = [v for v in own.values() if v is not None]
        keys = ({a: a for a in axes} if len(set(vals)) != len(vals) else own)
    else:
        unknown = [k for k in keys if k not in axes]
        if unknown:
            _stop("`keys` names unknown axes: %s", _preview(unknown))
        keys = {**own, **keys}
    return ScaleProduct(axes=dict(axes), keys=dict(keys), joint_weights=joint_weights,
                        meta={"name": name, "desc": desc})


def _check_product(x: object, arg: str = "x") -> None:
    if not isinstance(x, ScaleProduct):
        _stop("`%s` must be a ScaleProduct object", arg)


def scale_axes(x: ScaleProduct, axis: str | None = None):
    """All axes (name -> scale), or one axis."""
    _check_product(x)
    if axis is None:
        return dict(x.axes)
    if not isinstance(axis, str):
        _stop("`axis` must be a single axis name; one of: %s", ", ".join(x.axes))
    if axis not in x.axes:
        _stop('`axis` = "%s" is not an axis of this product; one of: %s', axis,
              ", ".join(x.axes))
    return x.axes[axis]


def product_keys(x: ScaleProduct) -> dict[str, str]:
    """Axis -> data key column."""
    _check_product(x)
    return dict(x.keys)


def product_frames(x: ScaleProduct) -> dict[str, list[str]]:
    _check_product(x)
    return {a: scale_frames(s) for a, s in x.axes.items()}


def product_weights(x: ScaleProduct) -> dict[str, list[str]]:
    _check_product(x)
    return {a: scale_weights(s) for a, s in x.axes.items()}


def product_size(x: ScaleProduct) -> dict[str, Any]:
    """Atoms per axis and the size of the (never materialised) product."""
    _check_product(x)
    n = {a: s.leaftable.num_rows for a, s in x.axes.items()}
    return {"axes": n, "total": float(math.prod(n.values()))}


def product_coverage(x: ScaleProduct, weight: str | None = None) -> dict[str, float]:
    _check_product(x)
    out = {}
    for a, s in x.axes.items():
        w = weight or s.meta.get("default_weight") or (
            scale_weights(s)[0] if scale_weights(s) else None)
        out[a] = 1.0 if w is None else scale_coverage(s, w)
    return out


def scale_is_product(x: object) -> bool:
    return isinstance(x, ScaleProduct)


def scale_product_class() -> type[ScaleProduct]:
    return ScaleProduct
