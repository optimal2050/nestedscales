"""nestedscales: nested scales and multi-dimensional indexes for modeling.

Python binding of the R package of the same name. Every function has the same
name and argument order as in R; see API.md at the repository root.
"""
# the twin views register their vocabularies on import
from . import twins  # noqa: E402,F401
from ._backend import as_table
from ._utils import NestedScalesError, NestedScalesWarning
from .array import as_scale_array, as_scale_table
from .dataset import (
    ScaleDataset,
    open_scale_dataset,
    scale_dataset_info,
    write_scale_dataset,
)
from .filter import filter_scale, prune_scale, scale_share
from .frames import is_valid_frame
from .join import join_scale
from .map import (
    clear_scale_maps,
    get_scale_map,
    get_scale_map_between,
    list_scale_maps,
    register_scale_map,
    register_scale_map_between,
    scale_atom_pairs,
    scale_map,
    scale_map_between,
)
from .navigate import (
    Verdict,
    scale_ancestors,
    scale_ancestry,
    scale_children,
    scale_coverage,
    scale_crosses,
    scale_descendants,
    scale_family,
    scale_is_uniform,
    scale_nests,
    scale_parents,
)
from .product import (
    ScaleProduct,
    product_coverage,
    product_frames,
    product_keys,
    product_size,
    product_weights,
    scale_axes,
    scale_is_product,
    scale_product,
    scale_product_class,
)
from .recast import (
    recast,
    recast_crosswalk,
    recast_from_atoms,
    recast_scale,
    recast_to_atoms,
)
from .rules import (
    SCALE_RULES,
    clear_scale_rules,
    get_scale_rule,
    list_scale_rules,
    register_scale_rule,
)
from .scale_class import (
    NestedScale,
    ScaleSummary,
    scale_alias_property,
    scale_atom_level,
    scale_class,
    scale_frames,
    scale_is,
    scale_key,
    scale_leaftable,
    scale_payload_slice,
    scale_rank,
    scale_residuals,
    scale_summary,
    scale_units,
    scale_vocab,
    scale_weights,
)
from .scale_construct import scale_example, scale_example2, scale_from_leaftable

__version__ = "0.1.0.dev0"

__all__ = [
    "ScaleDataset", "open_scale_dataset", "scale_dataset_info",
    "write_scale_dataset", "ScaleProduct", "product_coverage", "product_frames",
    "product_keys", "product_size", "product_weights", "scale_axes",
    "scale_is_product", "scale_product", "scale_product_class",
    "as_scale_array", "as_scale_table", "filter_scale", "join_scale",
    "prune_scale", "scale_share",
    "recast", "recast_crosswalk", "recast_from_atoms", "recast_scale",
    "recast_to_atoms",
    "SCALE_RULES", "clear_scale_maps", "clear_scale_rules", "get_scale_map",
    "get_scale_map_between", "get_scale_rule", "list_scale_maps",
    "list_scale_rules", "register_scale_map", "register_scale_map_between",
    "register_scale_rule", "scale_atom_pairs", "scale_map", "scale_map_between",
    "NestedScale", "NestedScalesError", "NestedScalesWarning", "ScaleSummary",
    "Verdict", "as_table", "is_valid_frame", "scale_alias_property",
    "scale_ancestors", "scale_ancestry", "scale_atom_level", "scale_children",
    "scale_class", "scale_coverage", "scale_crosses", "scale_descendants",
    "scale_example", "scale_example2", "scale_family", "scale_frames",
    "scale_from_leaftable", "scale_is", "scale_is_uniform", "scale_key",
    "scale_leaftable", "scale_nests", "scale_parents", "scale_payload_slice",
    "scale_rank", "scale_residuals", "scale_summary", "scale_units",
    "scale_vocab", "scale_weights",
]
