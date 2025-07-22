# Helper functions to define targets
For each of the varied input types, pcvct has a helper function to create the XML path.

## Varying config parameters
The [`configPath`](@ref) function can be used to create the XML path to almost[^1] any parameter in the configuration file intuitively.
See [Config XML paths](@ref) for an exhaustive explanation of the available tokens.
Here are some simple examples to get you started:

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
The [`rulePath`](@ref) function can help start the XML path to rules parameters.
It does not infer the full path from tokens like [`configPath`](@ref), but relies on the user knowing the structure of the rules XML file.
The first argument is the cell type and the second argument is the behavior.
The remaining arguments are the remaining entries in the XML path.
Here are some examples:

```julia
rulePath(<cell_type>, <behavior>, "increasing_signals", "max_response")
rulePath(<cell_type>, <behavior>, "decreasing_signals", "max_resposne")
rulePath(<cell_type>, <behavior>, "increasing_signals", "signal:name:<signal_name>", <tag>)
rulePath(<cell_type>, <behavior>, "decreasing_signals", "signal:name:<signal_name>", "reference", "value")
```

## Varying initial cell parameters
pcvct supports an XML-based initialization of cell locations using [PhysiCellCellCreator.jl](https://github.com/drbergman-lab/PhysiCellCellCreator.jl).
See the documentation of that package for details on how to create the XML file.
Use [`pcvct.createICCellXMLTemplate`](@ref) to create a template XML file and automatically add it to the database.
From there, you can edit it directly (though as per [Best practices](@ref) do not edit after simulations are created that rely on it).

To vary parameters in this XML file, the [`icCellsPath`](@ref) function can be used.
The signature is as follows:

```julia
icCellsPath(<cell_type>, <patch_type>, <patch_id>, <tag>)
```

[PhysiCellCellCreator.jl](https://github.com/drbergman-lab/PhysiCellCellCreator.jl) supports carveouts that can be used to not place cells within the given patches.
These are contained in a child element of the patch element and their parameters can be varied using the following signature:

```julia
icCellsPath(<cell_type>, <patch_type>, <patch_id>, <carveout_type>, <carveout_id>, <tag>)
```

## Varying initial ECM parameters
pcvct supports an XML-based initialization of ECMs using [PhysiCellECMCreator.jl](https://github.com/drbergman-lab/PhysiCellECMCreator.jl).
See the documentation of that package for details on how to create the XML file.
Use [`pcvct.createICECMXMLTemplate`](@ref) to create a template XML file and automatically add it to the database.
From there, you can edit it directly (though as per [Best practices](@ref) do not edit after simulations are created that rely on it).

To vary parameters in this XML file, the [`icECMPath`](@ref) function can be used.
The signature is as follows:

```julia
icECMPath(<layer_id>, <patch_type>, <patch_id>, <tag>)
```

Or in the case of using a patch type `"ellipse_with_shell"` there are additional parameters for the two (or three) subpatches:
```julia
icECMPath(<layer_id>, "ellipse_with_shell", <patch_id>, <subpatch>, <tag>)
```
where `<subpatch>` is one of `"interior"`, `"shell"`, or `"exterior"`.