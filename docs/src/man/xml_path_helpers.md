# XML path helpers
Each varied input type has a helper function that builds its XML path.

## Varying config parameters
[`configPath`](@ref) builds the XML path to almost[^1] any configuration parameter from intuitive tokens. See [Config XML paths](@ref) for the full token reference. Some examples:

```julia
configPath("max_time")
configPath("full_data_interval")
configPath(<substrate_name>, "diffusion_coefficient")
configPath(<cell_type>, "cycle", "rate", 0)
configPath(<cell_type>, "speed")
configPath(<cell_type>, "custom", <tag>)
configPath("user_parameters", <tag>)
```

[^1]: Intracellular parameters are not supported (yet). Others may also be missing. If the [`configPath`](@ref) function does not recognize the tokens you pass it, it will throw an error showing the available tokens (for the given number of tokens you passed).

## Varying rules parameters
[`rulePath`](@ref) builds the XML path to rules parameters. Unlike [`configPath`](@ref), it does not infer the path from tokens — you supply the cell type, the behavior, then the remaining XML-path entries directly:

```julia
rulePath(<cell_type>, <behavior>, "increasing_signals", "max_response")
rulePath(<cell_type>, <behavior>, "decreasing_signals", "max_resposne")
rulePath(<cell_type>, <behavior>, "increasing_signals", "signal:name:<signal_name>", <tag>)
rulePath(<cell_type>, <behavior>, "decreasing_signals", "signal:name:<signal_name>", "reference", "value")
```

## Varying initial cell parameters
PhysiCellModelManager.jl initializes cell locations from XML via [PhysiCellCellCreator.jl](https://github.com/drbergman-lab/PhysiCellCellCreator.jl) (see its docs for the file format). Use [`PhysiCellModelManager.createICCellXMLTemplate`](@ref) to create a template and register it in the database; edit it directly afterward (but per [Best practices](@ref), not after dependent simulations exist).

Vary its parameters with [`icCellsPath`](@ref):

```julia
icCellsPath(<cell_type>, <patch_type>, <patch_id>, <tag>)
```

[PhysiCellCellCreator.jl](https://github.com/drbergman-lab/PhysiCellCellCreator.jl) also supports carveouts (a child element of the patch) that exclude cells from a region. Vary their parameters with:

```julia
icCellsPath(<cell_type>, <patch_type>, <patch_id>, <carveout_type>, <carveout_id>, <tag>)
```

## Varying initial ECM parameters
PhysiCellModelManager.jl initializes ECMs from XML via [PhysiCellECMCreator.jl](https://github.com/drbergman-lab/PhysiCellECMCreator.jl) (see its docs for the file format). Use [`PhysiCellModelManager.createICECMXMLTemplate`](@ref) to create a template and register it in the database; edit it directly afterward (but per [Best practices](@ref), not after dependent simulations exist).

Vary its parameters with [`icECMPath`](@ref):

```julia
icECMPath(<layer_id>, <patch_type>, <patch_id>, <tag>)
```

Or in the case of using a patch type `"ellipse_with_shell"` there are additional parameters for the two (or three) subpatches:
```julia
icECMPath(<layer_id>, "ellipse_with_shell", <patch_id>, <subpatch>, <tag>)
```
where `<subpatch>` is one of `"interior"`, `"shell"`, or `"exterior"`.