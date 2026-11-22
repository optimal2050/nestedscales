# Package index

## Scales

Build a scale and read its structure.

- [`scale_from_leaftable()`](https://optimal2050.github.io/nestedscales/r/reference/scale_from_leaftable.md)
  : Build a NestedScale from a flat table of leaves
- [`scale_example()`](https://optimal2050.github.io/nestedscales/r/reference/scale_example.md)
  : A small example NestedScale
- [`scale_example2()`](https://optimal2050.github.io/nestedscales/r/reference/scale_example2.md)
  : A second small example NestedScale
- [`NestedScale()`](https://optimal2050.github.io/nestedscales/r/reference/NestedScale.md)
  : NestedScale (S7 class)
- [`scale_class()`](https://optimal2050.github.io/nestedscales/r/reference/scale_class.md)
  [`scale_product_class()`](https://optimal2050.github.io/nestedscales/r/reference/scale_class.md)
  : The scale classes, for subclassing and dispatch
- [`scale_is()`](https://optimal2050.github.io/nestedscales/r/reference/scale_is.md)
  [`scale_is_product()`](https://optimal2050.github.io/nestedscales/r/reference/scale_is.md)
  : Is this a scale, or a product of scales?
- [`scale_frames()`](https://optimal2050.github.io/nestedscales/r/reference/scale_frames.md)
  [`names(`*`<NestedScale>`*`)`](https://optimal2050.github.io/nestedscales/r/reference/scale_frames.md)
  : Frames of a NestedScale
- [`scale_members()`](https://optimal2050.github.io/nestedscales/r/reference/scale_members.md)
  : Members of a NestedScale
- [`scale_leaf_column()`](https://optimal2050.github.io/nestedscales/r/reference/scale_leaf_column.md)
  : The name of the leaf column
- [`scale_leaftable()`](https://optimal2050.github.io/nestedscales/r/reference/scale_leaftable.md)
  [`as.data.frame(`*`<NestedScale>`*`)`](https://optimal2050.github.io/nestedscales/r/reference/scale_leaftable.md)
  [`as.data.frame(`*`<nestedscales::NestedScale>`*`)`](https://optimal2050.github.io/nestedscales/r/reference/scale_leaftable.md)
  : The leaftable of a NestedScale
- [`scale_weights()`](https://optimal2050.github.io/nestedscales/r/reference/scale_weights.md)
  : Weight columns of a NestedScale
- [`scale_rank()`](https://optimal2050.github.io/nestedscales/r/reference/scale_rank.md)
  : Frame rank
- [`scale_leaf_frame()`](https://optimal2050.github.io/nestedscales/r/reference/scale_leaf_frame.md)
  : The frame whose members are the leaves
- [`scale_residuals()`](https://optimal2050.github.io/nestedscales/r/reference/scale_residuals.md)
  : Members that are residuals
- [`is_valid_frame()`](https://optimal2050.github.io/nestedscales/r/reference/is_valid_frame.md)
  : Validate frame names
- [`summary(`*`<NestedScale>`*`)`](https://optimal2050.github.io/nestedscales/r/reference/summary.NestedScale.md)
  [`summary(`*`<nestedscales::NestedScale>`*`)`](https://optimal2050.github.io/nestedscales/r/reference/summary.NestedScale.md)
  [`print(`*`<summary_Scale>`*`)`](https://optimal2050.github.io/nestedscales/r/reference/summary.NestedScale.md)
  : Summarize a NestedScale
- [`str(`*`<NestedScale>`*`)`](https://optimal2050.github.io/nestedscales/r/reference/str.NestedScale.md)
  [`str(`*`<nestedscales::NestedScale>`*`)`](https://optimal2050.github.io/nestedscales/r/reference/str.NestedScale.md)
  [`str(`*`<nestedscales::ScaleProduct>`*`)`](https://optimal2050.github.io/nestedscales/r/reference/str.NestedScale.md)
  : Show the structure of a scale
- [`scale_tree()`](https://optimal2050.github.io/nestedscales/r/reference/scale_tree.md)
  [`print(`*`<scale_tree>`*`)`](https://optimal2050.github.io/nestedscales/r/reference/scale_tree.md)
  : The parts of a scale and which of them may change
- [`` `[`( ``*`<NestedScale>`*`)`](https://optimal2050.github.io/nestedscales/r/reference/sub-.NestedScale.md)
  [`` `[`( ``*`<nestedscales::NestedScale>`*`)`](https://optimal2050.github.io/nestedscales/r/reference/sub-.NestedScale.md)
  : Subset a NestedScale

## Navigation and shares

Move between frames and report what a member holds.

- [`scale_children()`](https://optimal2050.github.io/nestedscales/r/reference/scale_navigate.md)
  [`scale_parents()`](https://optimal2050.github.io/nestedscales/r/reference/scale_navigate.md)
  [`scale_descendants()`](https://optimal2050.github.io/nestedscales/r/reference/scale_navigate.md)
  [`scale_ancestors()`](https://optimal2050.github.io/nestedscales/r/reference/scale_navigate.md)
  : Navigate a NestedScale's hierarchy
- [`scale_family()`](https://optimal2050.github.io/nestedscales/r/reference/scale_family.md)
  : Immediate parent-child table between two frames
- [`scale_ancestry()`](https://optimal2050.github.io/nestedscales/r/reference/scale_ancestry.md)
  : Ancestry between all frame pairs
- [`scale_nests()`](https://optimal2050.github.io/nestedscales/r/reference/scale_nests.md)
  : Do two frames nest?
- [`scale_crosses()`](https://optimal2050.github.io/nestedscales/r/reference/scale_crosses.md)
  : Do two frames form a product?
- [`scale_is_uniform()`](https://optimal2050.github.io/nestedscales/r/reference/scale_is_uniform.md)
  : Are the members of a frame the same size?
- [`scale_share()`](https://optimal2050.github.io/nestedscales/r/reference/scale_share.md)
  : Weight shares within a frame
- [`scale_coverage()`](https://optimal2050.github.io/nestedscales/r/reference/scale_coverage.md)
  : Coverage of a sampled NestedScale

## Subsetting

- [`filter_scale()`](https://optimal2050.github.io/nestedscales/r/reference/filter_scale.md)
  : Subset a NestedScale by member
- [`prune_scale()`](https://optimal2050.github.io/nestedscales/r/reference/prune_scale.md)
  : Collapse a NestedScale to a coarser frame

## Attributes and aliases

Values that belong to members but are not weights, alternative labels,
strict matching, and row-wise conversion.

- [`attach_attributes_scale()`](https://optimal2050.github.io/nestedscales/r/reference/attach_attributes_scale.md)
  **\[experimental\]** : Attach physical attributes to a scale
- [`scale_attributes()`](https://optimal2050.github.io/nestedscales/r/reference/scale_attributes.md)
  **\[experimental\]** : Read attributes, resolved along the hierarchy
- [`SCALE_ATTRIBUTE_KINDS`](https://optimal2050.github.io/nestedscales/r/reference/SCALE_ATTRIBUTE_KINDS.md)
  **\[experimental\]** : Kinds of attribute
- [`attach_aliases_scale()`](https://optimal2050.github.io/nestedscales/r/reference/attach_aliases_scale.md)
  : Attach aliases to a scale
- [`scale_aliases()`](https://optimal2050.github.io/nestedscales/r/reference/scale_aliases.md)
  : Read the alias table
- [`scale_match()`](https://optimal2050.github.io/nestedscales/r/reference/scale_match.md)
  : Match labels to members, strictly
- [`attach_labels_scale()`](https://optimal2050.github.io/nestedscales/r/reference/attach_labels_scale.md)
  : Attach labels to a scale
- [`scale_labels()`](https://optimal2050.github.io/nestedscales/r/reference/scale_labels.md)
  : Read the label table
- [`scale_label()`](https://optimal2050.github.io/nestedscales/r/reference/scale_label.md)
  : Look up the labels of members
- [`convert_scale()`](https://optimal2050.github.io/nestedscales/r/reference/convert_scale.md)
  **\[experimental\]** : Convert member-keyed quantities with a member
  attribute

## The data link (experimental)

Record which scale and frame a table’s code columns are on.

- [`bind_scale()`](https://optimal2050.github.io/nestedscales/r/reference/bind_scale.md)
  [`unbind_scale()`](https://optimal2050.github.io/nestedscales/r/reference/bind_scale.md)
  [`scale_link()`](https://optimal2050.github.io/nestedscales/r/reference/bind_scale.md)
  **\[experimental\]** : Bind a table to a scale
- [`scale_id()`](https://optimal2050.github.io/nestedscales/r/reference/scale_id.md)
  : The identity of a scale
- [`as_scale_member()`](https://optimal2050.github.io/nestedscales/r/reference/as_scale_member.md)
  [`is_scale_member()`](https://optimal2050.github.io/nestedscales/r/reference/as_scale_member.md)
  **\[experimental\]** : Codes bound to a scale

## Conversion

Recast data between resolutions, attach labels, and declare rules.

- [`recast_scale()`](https://optimal2050.github.io/nestedscales/r/reference/recast_scale.md)
  : Recast values from one resolution to another
- [`recast()`](https://optimal2050.github.io/nestedscales/r/reference/recast.md)
  : Recast data through a scale
- [`recast_to_leaves()`](https://optimal2050.github.io/nestedscales/r/reference/recast_to_leaves.md)
  [`recast_from_leaves()`](https://optimal2050.github.io/nestedscales/r/reference/recast_to_leaves.md)
  : Recast member data down to the leaf layer, and back
- [`recast_crosswalk()`](https://optimal2050.github.io/nestedscales/r/reference/recast_crosswalk.md)
  : Recast values through a given crosswalk
- [`join_scale()`](https://optimal2050.github.io/nestedscales/r/reference/join_scale.md)
  : Attach scale labels and memberships to a dataset
- [`reconcile_scale()`](https://optimal2050.github.io/nestedscales/r/reference/reconcile_scale.md)
  **\[experimental\]** : Check fine data against an independent parent
  total
- [`SCALE_RULES`](https://optimal2050.github.io/nestedscales/r/reference/SCALE_RULES.md)
  : Supported aggregation rules
- [`register_scale_rule()`](https://optimal2050.github.io/nestedscales/r/reference/register_scale_rule.md)
  : Register how a parameter should be recast
- [`get_scale_rule()`](https://optimal2050.github.io/nestedscales/r/reference/get_scale_rule.md)
  : Look up a registered rule
- [`list_scale_rules()`](https://optimal2050.github.io/nestedscales/r/reference/list_scale_rules.md)
  : List registered rules
- [`clear_scale_rules()`](https://optimal2050.github.io/nestedscales/r/reference/clear_scale_rules.md)
  : Clear the rule registry

## Crosswalks

The map behind every conversion, and the registry of exact ones.

- [`scale_map()`](https://optimal2050.github.io/nestedscales/r/reference/scale_map.md)
  : Crosswalk between two frames of a scale
- [`scale_map_between()`](https://optimal2050.github.io/nestedscales/r/reference/scale_map_between.md)
  : Crosswalk between two scales through their shared leaves
- [`register_scale_map()`](https://optimal2050.github.io/nestedscales/r/reference/register_scale_map.md)
  [`register_scale_map_between()`](https://optimal2050.github.io/nestedscales/r/reference/register_scale_map.md)
  [`get_scale_map()`](https://optimal2050.github.io/nestedscales/r/reference/register_scale_map.md)
  [`get_scale_map_between()`](https://optimal2050.github.io/nestedscales/r/reference/register_scale_map.md)
  [`list_scale_maps()`](https://optimal2050.github.io/nestedscales/r/reference/register_scale_map.md)
  : Register / look up a direct crosswalk
- [`clear_scale_maps()`](https://optimal2050.github.io/nestedscales/r/reference/clear_scale_maps.md)
  : Clear the registered crosswalks

## Products of scales (experimental)

Several scales as one multi-index.

- [`scale_product()`](https://optimal2050.github.io/nestedscales/r/reference/scale_product.md)
  **\[experimental\]** : Combine scales into a product index
- [`ScaleProduct()`](https://optimal2050.github.io/nestedscales/r/reference/ScaleProduct.md)
  **\[experimental\]** : A product of several scales (S7 class)
- [`scale_axes()`](https://optimal2050.github.io/nestedscales/r/reference/scale_axes.md)
  **\[experimental\]** : Axes of a product
- [`product_size()`](https://optimal2050.github.io/nestedscales/r/reference/product_size.md)
  **\[experimental\]** : Size of a product
- [`product_keys()`](https://optimal2050.github.io/nestedscales/r/reference/product_keys.md)
  **\[experimental\]** : The data key column of each axis
- [`product_frames()`](https://optimal2050.github.io/nestedscales/r/reference/product_frames.md)
  **\[experimental\]** : Frames of each axis
- [`product_weights()`](https://optimal2050.github.io/nestedscales/r/reference/product_weights.md)
  **\[experimental\]** : Weight columns of each axis
- [`product_coverage()`](https://optimal2050.github.io/nestedscales/r/reference/product_coverage.md)
  **\[experimental\]** : Coverage of each axis
- [`product_leaves()`](https://optimal2050.github.io/nestedscales/r/reference/product_leaves.md)
  **\[experimental\]** : Realise the leaves of a product
- [`recast_product()`](https://optimal2050.github.io/nestedscales/r/reference/recast_product.md)
  **\[experimental\]** : Recast data indexed by a product of scales
- [`join_product()`](https://optimal2050.github.io/nestedscales/r/reference/join_product.md)
  **\[experimental\]** : Attach every axis's labels to product-indexed
  data
- [`filter_product()`](https://optimal2050.github.io/nestedscales/r/reference/filter_product.md)
  **\[experimental\]** : Subset a product componentwise
- [`summary(`*`<ScaleProduct>`*`)`](https://optimal2050.github.io/nestedscales/r/reference/summary.ScaleProduct.md)
  [`summary(`*`<nestedscales::ScaleProduct>`*`)`](https://optimal2050.github.io/nestedscales/r/reference/summary.ScaleProduct.md)
  [`print(`*`<summary_ScaleProduct>`*`)`](https://optimal2050.github.io/nestedscales/r/reference/summary.ScaleProduct.md)
  : Summarize a product

## Clustering

Group members by their data into a new, coarser frame.

- [`cluster_scale()`](https://optimal2050.github.io/nestedscales/r/reference/cluster_scale.md)
  : Cluster the members of a scale into a new frame
- [`cluster_contiguous()`](https://optimal2050.github.io/nestedscales/r/reference/cluster_contiguous.md)
  : Cluster the members of a scale under a contiguity constraint
- [`cluster_medoids()`](https://optimal2050.github.io/nestedscales/r/reference/cluster_medoids.md)
  : The representative member of each cluster
- [`cluster_sweep()`](https://optimal2050.github.io/nestedscales/r/reference/cluster_sweep.md)
  : Cluster quality across a range of k
- [`scale_distance()`](https://optimal2050.github.io/nestedscales/r/reference/scale_distance.md)
  **\[experimental\]** : Distance between the members of a scale
- [`SCALE_DISTANCES`](https://optimal2050.github.io/nestedscales/r/reference/SCALE_DISTANCES.md)
  **\[experimental\]** : Built-in distances
- [`register_scale_distance()`](https://optimal2050.github.io/nestedscales/r/reference/register_scale_distance.md)
  [`get_scale_distance()`](https://optimal2050.github.io/nestedscales/r/reference/register_scale_distance.md)
  [`list_scale_distances()`](https://optimal2050.github.io/nestedscales/r/reference/register_scale_distance.md)
  [`clear_scale_distances()`](https://optimal2050.github.io/nestedscales/r/reference/register_scale_distance.md)
  **\[experimental\]** : Register a distance

## Definitions and catalogue

Language-neutral definition files and the registry of the ones installed
packages ship.

- [`write_scale()`](https://optimal2050.github.io/nestedscales/r/reference/write_scale.md)
  [`read_scale()`](https://optimal2050.github.io/nestedscales/r/reference/write_scale.md)
  : Write a scale as a definition file, and read one back
- [`register_scale_dir()`](https://optimal2050.github.io/nestedscales/r/reference/scale_catalog.md)
  [`list_scale_dirs()`](https://optimal2050.github.io/nestedscales/r/reference/scale_catalog.md)
  [`clear_scale_dirs()`](https://optimal2050.github.io/nestedscales/r/reference/scale_catalog.md)
  [`scale_catalog()`](https://optimal2050.github.io/nestedscales/r/reference/scale_catalog.md)
  : Shipped scale definitions

## Arrays and storage (experimental)

- [`as_scale_array()`](https://optimal2050.github.io/nestedscales/r/reference/as_scale_array.md)
  [`as_scale_table()`](https://optimal2050.github.io/nestedscales/r/reference/as_scale_array.md)
  **\[experimental\]** : Data on scales as a dense array
- [`write_scale_dataset()`](https://optimal2050.github.io/nestedscales/r/reference/write_scale_dataset.md)
  **\[experimental\]** : Write data and the scales that index it to one
  folder
- [`open_scale_dataset()`](https://optimal2050.github.io/nestedscales/r/reference/open_scale_dataset.md)
  [`print(`*`<scale_dataset>`*`)`](https://optimal2050.github.io/nestedscales/r/reference/open_scale_dataset.md)
  **\[experimental\]** : Open a scale-aware dataset
- [`scale_dataset_info()`](https://optimal2050.github.io/nestedscales/r/reference/scale_dataset_info.md)
  **\[experimental\]** : Describe a stored dataset without opening it
  fully

## Building a dimension package

Hooks and helpers for packages that subclass NestedScale.

- [`scale_alias_property()`](https://optimal2050.github.io/nestedscales/r/reference/scale_alias_property.md)
  : An alias property for a subclass
- [`scale_vocab()`](https://optimal2050.github.io/nestedscales/r/reference/scale_vocab.md)
  : The dimension vocabulary of a scale
- [`scale_payload_slice()`](https://optimal2050.github.io/nestedscales/r/reference/scale_payload_slice.md)
  : Subset a subclass's per-leaf payload
- [`scale_payload_collapse()`](https://optimal2050.github.io/nestedscales/r/reference/scale_payload_collapse.md)
  : Collapse a subclass's per-leaf payload
- [`scale_payload_parts()`](https://optimal2050.github.io/nestedscales/r/reference/scale_payload_parts.md)
  : Describe the parts a subclass adds to a scale
- [`scale_write_payload()`](https://optimal2050.github.io/nestedscales/r/reference/scale_payload_io.md)
  [`scale_read_payload()`](https://optimal2050.github.io/nestedscales/r/reference/scale_payload_io.md)
  [`register_scale_class()`](https://optimal2050.github.io/nestedscales/r/reference/scale_payload_io.md)
  [`list_scale_classes()`](https://optimal2050.github.io/nestedscales/r/reference/scale_payload_io.md)
  : Write and read a subclass's payload in a definition file
- [`scale_leaf_pairs()`](https://optimal2050.github.io/nestedscales/r/reference/scale_leaf_pairs.md)
  : Leaf-level correspondence between two frames
- [`backend_of()`](https://optimal2050.github.io/nestedscales/r/reference/backend.md)
  [`backend_is_lazy()`](https://optimal2050.github.io/nestedscales/r/reference/backend.md)
  [`backend_schema()`](https://optimal2050.github.io/nestedscales/r/reference/backend.md)
  [`backend_lazy()`](https://optimal2050.github.io/nestedscales/r/reference/backend.md)
  [`backend_pull()`](https://optimal2050.github.io/nestedscales/r/reference/backend.md)
  [`backend_restore()`](https://optimal2050.github.io/nestedscales/r/reference/backend.md)
  [`backend_bind_rows()`](https://optimal2050.github.io/nestedscales/r/reference/backend.md)
  : Backends: the table types the verbs accept

## Package

- [`nestedscales`](https://optimal2050.github.io/nestedscales/r/reference/nestedscales-package.md)
  [`nestedscales-package`](https://optimal2050.github.io/nestedscales/r/reference/nestedscales-package.md)
  : nestedscales: Nested Scales and Multi-Dimensional Indexes for
  Modeling
