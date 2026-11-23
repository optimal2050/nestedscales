"""nestedscales: nested scales and multi-dimensional indexes for modeling.

Python binding of the R package of the same name. Every function has the same
name and argument order as in R; see API.md at the repository root.
"""
from ._utils import NestedScalesError, NestedScalesWarning
from .aliases import attach_aliases_scale, scale_aliases, scale_match
from .array import as_scale_array, as_scale_table
from .attributes import attach_attributes_scale, scale_attributes
from .backend import (
    Backend,
    backend_bind_rows,
    backend_is_lazy,
    backend_of,
    backend_pull,
    backend_restore,
    backend_schema,
)
from .convert import convert_scale
from .dataset import (
    ScaleDataset,
    open_scale_dataset,
    scale_dataset_info,
    write_scale_dataset,
)
from .definition import (
    clear_scale_dirs,
    list_scale_classes,
    list_scale_dirs,
    read_scale,
    register_scale_class,
    register_scale_dir,
    scale_catalog,
    scale_read_payload,
    scale_write_payload,
    write_scale,
)
from .filter import filter_scale, prune_scale, scale_share
from .frames import is_valid_frame
from .join import join_scale
from .labels import attach_labels_scale, scale_label, scale_labels
from .link import scale_id
from .map import (
    clear_scale_maps,
    get_scale_map,
    get_scale_map_between,
    list_scale_maps,
    register_scale_map,
    register_scale_map_between,
    scale_leaf_pairs,
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
    recast_from_leaves,
    recast_scale,
    recast_to_leaves,
)
from .rules import (
    SCALE_RULES,
    clear_scale_rules,
    get_scale_rule,
    list_scale_rules,
    register_scale_rule,
)
from .scale_class import (
    ALIAS_SCHEMA,
    ATTR_SCHEMA,
    LABEL_SCHEMA,
    SCALE_ATTRIBUTE_KINDS,
    NestedScale,
    ScaleSummary,
    empty_aliases,
    empty_attributes,
    empty_labels,
    scale_alias_property,
    scale_class,
    scale_frames,
    scale_is,
    scale_leaf_column,
    scale_leaf_frame,
    scale_leaftable,
    scale_members,
    scale_payload_collapse,
    scale_payload_slice,
    scale_rank,
    scale_residuals,
    scale_set_props,
    scale_summary,
    scale_validate,
    scale_vocab,
    scale_weights,
)
from .scale_construct import scale_example, scale_example2, scale_from_leaftable
from .tree import ScaleTree, scale_payload_parts, scale_tree

__version__ = "0.3.0"

__all__ = [
    "ScaleDataset", "open_scale_dataset", "scale_dataset_info",
    "write_scale_dataset", "write_scale", "read_scale", "scale_catalog",
    "register_scale_dir", "list_scale_dirs", "clear_scale_dirs",
    "register_scale_class", "list_scale_classes", "scale_read_payload",
    "scale_write_payload", "SCALE_ATTRIBUTE_KINDS", "ATTR_SCHEMA",
    "ALIAS_SCHEMA", "LABEL_SCHEMA", "empty_attributes", "empty_aliases",
    "empty_labels",
    "attach_attributes_scale", "scale_attributes", "attach_aliases_scale",
    "scale_aliases", "scale_match", "convert_scale",
    "attach_labels_scale", "scale_labels", "scale_label",
    "scale_id", "scale_tree", "ScaleTree", "scale_payload_parts",
    "scale_payload_collapse", "scale_set_props", "scale_validate",
    "ScaleProduct", "product_coverage", "product_frames",
    "product_keys", "product_size", "product_weights", "scale_axes",
    "scale_is_product", "scale_product", "scale_product_class",
    "as_scale_array", "as_scale_table", "filter_scale", "join_scale",
    "prune_scale", "scale_share",
    "recast", "recast_crosswalk", "recast_from_leaves", "recast_scale",
    "recast_to_leaves",
    "SCALE_RULES", "clear_scale_maps", "clear_scale_rules", "get_scale_map",
    "get_scale_map_between", "get_scale_rule", "list_scale_maps",
    "list_scale_rules", "register_scale_map", "register_scale_map_between",
    "register_scale_rule", "scale_leaf_pairs", "scale_map", "scale_map_between",
    "NestedScale", "NestedScalesError", "NestedScalesWarning", "ScaleSummary",
    "Verdict", "Backend", "backend_bind_rows",
    "backend_is_lazy", "backend_of", "backend_pull", "backend_restore",
    "backend_schema", "is_valid_frame", "scale_alias_property",
    "scale_ancestors", "scale_ancestry", "scale_leaf_frame", "scale_children",
    "scale_class", "scale_coverage", "scale_crosses", "scale_descendants",
    "scale_example", "scale_example2", "scale_family", "scale_frames",
    "scale_from_leaftable", "scale_is", "scale_is_uniform", "scale_leaf_column",
    "scale_leaftable", "scale_nests", "scale_parents", "scale_payload_slice",
    "scale_rank", "scale_residuals", "scale_summary", "scale_members",
    "scale_vocab", "scale_weights",
]
