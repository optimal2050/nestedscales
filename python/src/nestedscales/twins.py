"""Read-only views of the R twins' scales: timescales' Calendar and
geoscales' GeoScale.

These are thin subclasses: the inherited engine with the twins' vocabulary
(so messages speak of timeframes and timeslices, or geoframes and regions)
and their alias fields. Rule and map registry lookups use the twins' scopes
("calendar", "geoscale"). The dimension logic itself -- calendar generation,
datetime crosswalks, geometry -- stays in the twin packages.

A store written by R carries no class marker, so convert explicitly:

    sd = ns.open_scale_dataset(path)
    cal = ns.twins.as_calendar(sd.scale)
"""
from __future__ import annotations

from dataclasses import fields

from .scale_class import NestedScale, _check_scale, scale_alias_property, scale_vocab


class Calendar(NestedScale):
    """timescales::Calendar, as a NestedScale with time vocabulary."""

    _r_package = "timescales"
    timeframes = scale_alias_property("frames")


class GeoScale(NestedScale):
    """geoscales::GeoScale, as a NestedScale with space vocabulary."""

    _r_package = "geoscales"
    geoframes = scale_alias_property("frames")


@scale_vocab.register(Calendar)
def _(x: Calendar) -> dict[str, str]:
    return {"object": "Calendar", "frame": "timeframe", "frames": "timeframes",
            "unit": "timeslice", "units": "timeslices", "atoms": "timebase",
            "register_rule": "register_calendar_rule()",
            "register_map": "register_calendar_map_between()"}


@scale_vocab.register(GeoScale)
def _(x: GeoScale) -> dict[str, str]:
    return {"object": "GeoScale", "frame": "geoframe", "frames": "geoframes",
            "unit": "region", "units": "regions", "atoms": "geoatoms",
            "register_rule": "register_geoscale_rule()",
            "register_map": "register_geoscale_map_between()"}


def _as(cls: type[NestedScale], x: NestedScale) -> NestedScale:
    _check_scale(x)
    return cls(**{f.name: getattr(x, f.name) for f in fields(NestedScale)})


def as_calendar(x: NestedScale) -> Calendar:
    """View a scale (e.g. one opened from a store R wrote) as a Calendar."""
    return _as(Calendar, x)


def as_geoscale(x: NestedScale) -> GeoScale:
    """View a scale (e.g. one opened from a store R wrote) as a GeoScale."""
    return _as(GeoScale, x)
