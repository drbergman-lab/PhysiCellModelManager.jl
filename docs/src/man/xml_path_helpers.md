# [XML path helpers](@id xml_path_helpers_man)
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

### Named path helpers
[`configPath`](@ref) works by inferring, from the tokens you pass, which of a family of explicit,
narrower path helpers to call. That inference is the whole point: [`configPath`](@ref) is what you
should call, and the family below is what it calls for you.

!!! tierdev
    **Calling them directly.** None of these are exported, so each needs the package prefix —
    `PhysiCellModelManager.motilityPath("cd8", "speed")`. Reach for one when you are extending the
    token inference, or when [`configPath`](@ref) has no spelling for the element you want.

    **Cell definition.** [`cellDefinitionPath`](@ref PhysiCellModelManager.cellDefinitionPath)`(cell_type, path_elements...)`
    roots a path at one `<cell_definition>`, and
    [`phenotypePath`](@ref PhysiCellModelManager.phenotypePath) descends into its `<phenotype>`.
    Everything else in this group narrows one step further:
    [`cyclePath`](@ref PhysiCellModelManager.cyclePath) (phase durations and transition rates),
    [`deathPath`](@ref PhysiCellModelManager.deathPath) (the raw `<death>` element — prefer the two
    that name a model), [`apoptosisPath`](@ref PhysiCellModelManager.apoptosisPath) (`model:code:100`),
    [`necrosisPath`](@ref PhysiCellModelManager.necrosisPath) (`model:code:101`, two phases rather
    than one), [`volumePath`](@ref PhysiCellModelManager.volumePath),
    [`mechanicsPath`](@ref PhysiCellModelManager.mechanicsPath) (adhesion, repulsion, attachment
    rates, affinities), [`motilityPath`](@ref PhysiCellModelManager.motilityPath) (speed, bias,
    chemotaxis and advanced chemotaxis),
    [`secretionPath`](@ref PhysiCellModelManager.secretionPath)`(cell_type, substrate, tag)`, and
    [`cellInteractionsPath`](@ref PhysiCellModelManager.cellInteractionsPath) for the scalar tags
    under `<cell_interactions>`. The per-target rates inside that element each have their own helper,
    because they are keyed by a second cell type:
    [`attackRatePath`](@ref PhysiCellModelManager.attackRatePath)`(attacker, target)` — with
    [`attackPath`](@ref PhysiCellModelManager.attackPath) and
    [`attackRatesPath`](@ref PhysiCellModelManager.attackRatesPath) as aliases for it —
    [`fusionPath`](@ref PhysiCellModelManager.fusionPath)`(from, to)`,
    [`phagocytosisPath`](@ref PhysiCellModelManager.phagocytosisPath)`(eater, prey)` (pass a `Symbol`
    — `:apoptosis`, `:necrosis`, `:other_dead` — instead of a cell type for the dead-cell rates), and
    [`transformationPath`](@ref PhysiCellModelManager.transformationPath)`(from, to)`. Outside the
    phenotype: [`integrityPath`](@ref PhysiCellModelManager.integrityPath) (damage and repair rates),
    [`customDataPath`](@ref PhysiCellModelManager.customDataPath)`(cell_type, tag)`, and
    [`initialParameterDistributionPath`](@ref PhysiCellModelManager.initialParameterDistributionPath)`(cell_type, behavior, path_elements...)`,
    whose tail depends on the distribution `type` (`min`/`max`, or `mu`/`sigma`/`lower_bound`/`upper_bound`).

    **Domain, time, and saves.** [`domainPath`](@ref PhysiCellModelManager.domainPath)`(tag)` covers
    `x_min` … `z_max`, `dx`/`dy`/`dz`, and `use_2D`;
    [`timePath`](@ref PhysiCellModelManager.timePath)`(tag)` covers `max_time` and the `dt_*` step
    sizes; [`fullSavePath`](@ref PhysiCellModelManager.fullSavePath)`()` and
    [`svgSavePath`](@ref PhysiCellModelManager.svgSavePath)`()` take no arguments and return the two
    save intervals.

    **Substrates.** [`substratePath`](@ref PhysiCellModelManager.substratePath)`(substrate_name, path_elements...)`
    reaches the diffusion coefficient and decay rate (under `"physical_parameter_set"`), the initial
    and Dirichlet conditions, and per-boundary Dirichlet values.

    **User parameters.** [`userParameterPath`](@ref PhysiCellModelManager.userParameterPath)`(tag)`,
    with [`userParametersPath`](@ref PhysiCellModelManager.userParametersPath) as a synonym, returns
    `["user_parameters", tag]`.

## Varying rules parameters
[`rulePath`](@ref) builds the XML path to rules parameters. Unlike [`configPath`](@ref), it does not infer the path from tokens — you supply the cell type, the behavior, then the remaining XML-path entries directly:

```julia
rulePath(<cell_type>, <behavior>, "increasing_signals", "max_response")
rulePath(<cell_type>, <behavior>, "decreasing_signals", "max_resposne")
rulePath(<cell_type>, <behavior>, "increasing_signals", "signal:name:<signal_name>", <tag>)
rulePath(<cell_type>, <behavior>, "decreasing_signals", "signal:name:<signal_name>", "reference", "value")
```

## Varying initial cell parameters
PhysiCellModelManager.jl initializes cell locations from XML via [PhysiCellCellCreator.jl](https://github.com/drbergman-lab/PhysiCellCellCreator.jl) (see its docs for the file format). Use [`PhysiCellModelManager.createICCellXMLTemplate`](@ref) to create a template and register it in the database; edit it directly afterward (but per [Best practices](@ref best_practices_man), not after dependent simulations exist).

Vary its parameters with [`icCellsPath`](@ref):

```julia
icCellsPath(<cell_type>, <patch_type>, <patch_id>, <tag>)
```

[PhysiCellCellCreator.jl](https://github.com/drbergman-lab/PhysiCellCellCreator.jl) also supports carveouts (a child element of the patch) that exclude cells from a region. Vary their parameters with:

```julia
icCellsPath(<cell_type>, <patch_type>, <patch_id>, <carveout_type>, <carveout_id>, <tag>)
```

## Varying initial ECM parameters
PhysiCellModelManager.jl initializes ECMs from XML via [PhysiCellECMCreator.jl](https://github.com/drbergman-lab/PhysiCellECMCreator.jl) (see its docs for the file format). Use [`PhysiCellModelManager.createICECMXMLTemplate`](@ref) to create a template and register it in the database; edit it directly afterward (but per [Best practices](@ref best_practices_man), not after dependent simulations exist).

Vary its parameters with [`icECMPath`](@ref):

```julia
icECMPath(<layer_id>, <patch_type>, <patch_id>, <tag>)
```

Or in the case of using a patch type `"ellipse_with_shell"` there are additional parameters for the two (or three) subpatches:
```julia
icECMPath(<layer_id>, "ellipse_with_shell", <patch_id>, <subpatch>, <tag>)
```
where `<subpatch>` is one of `"interior"`, `"shell"`, or `"exterior"`.