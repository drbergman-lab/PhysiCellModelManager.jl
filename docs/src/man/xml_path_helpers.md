# [XML path helpers](@id xml_path_helpers_man)
Each varied input type has a helper function that builds its XML path.

## Varying config parameters

!!! tiergloss
    [`configPath`](@ref) builds the XML path to almost any configuration parameter from intuitive
    tokens. See [Config XML paths](@ref) for the full token reference.

!!! tierwhy
    Intracellular parameters are not supported (yet), and others may be missing. When
    [`configPath`](@ref) does not recognize the tokens you pass, it throws an error listing the
    tokens it does accept for that number of arguments — so a wrong guess tells you the right
    spelling rather than silently building a path to nothing.

```julia
configPath("max_time")
configPath("full_data_interval")
configPath(<substrate_name>, "diffusion_coefficient")
configPath(<cell_type>, "cycle", "rate", 0)
configPath(<cell_type>, "speed")
configPath(<cell_type>, "custom", <tag>)
configPath("user_parameters", <tag>)
```

!!! tierjournal "2026-09-02 — An unrecognized token is an error, not a path"
    **Decided:** `configPath("<cell type>", "motility", <tag>)` closes the class, not the instance.
    A natural guess must either resolve or be rejected by name, so an unrecognized third token under
    `<motility>` or `<chemotaxis>` — both closed tag sets — raises an `ArgumentError` naming the
    valid ones.

    **Rejected:** closing every token set the same way. `advanced_chemotaxis` stays open-ended,
    because its third token is a substrate name and that set is not ours to close.

### Named path helpers

!!! tiergloss
    [`configPath`](@ref) works by inferring, from the tokens you pass, which of a family of
    explicit, narrower path helpers to call. That inference is the whole point: [`configPath`](@ref)
    is what you should call, and the family below is what it calls for you.

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

!!! tierjournal "2026-08-02 — Public, but not exported"
    **Decided:** reachability defines PhysiCellModelManager.jl's public API — a name is public if we
    tell users how to use it, or if it is passed to or returned from something non-internal. The
    narrower `*Path` helpers are documented and callable, so they are `public`; only
    [`configPath`](@ref), [`rulePath`](@ref), [`icCellsPath`](@ref) and [`icECMPath`](@ref) are
    exported, because those are the four a user should reach for.

    **Rejected:** treating every non-underscore-prefixed binding as public, which would have
    promoted nearly every internal in the package.

## Varying rules parameters

!!! tiergloss
    [`rulePath`](@ref) builds the XML path to rules parameters. Unlike [`configPath`](@ref), it does
    not infer the path from tokens — you supply the cell type, the behavior, then the remaining
    XML-path entries directly.

```julia
rulePath(<cell_type>, <behavior>, "increasing_signals", "max_response")
rulePath(<cell_type>, <behavior>, "decreasing_signals", "max_response")
rulePath(<cell_type>, <behavior>, "increasing_signals", "signal:name:<signal_name>", <tag>)
rulePath(<cell_type>, <behavior>, "decreasing_signals", "signal:name:<signal_name>", "reference", "value")
```

## Varying initial cell parameters

!!! tiergloss
    PhysiCellModelManager.jl initializes cell locations from XML via
    [PhysiCellCellCreator.jl](https://github.com/drbergman-lab/PhysiCellCellCreator.jl) (see its
    docs for the file format). [`PhysiCellModelManager.createICCellXMLTemplate`](@ref) creates a
    template and registers it in the database; edit it directly afterward.
    [`icCellsPath`](@ref) then reaches its parameters, including those of the carveouts (a child
    element of the patch) that exclude cells from a region.

!!! tierwhy
    Editing the template in place is the intended workflow, but per
    [Best practices](@ref best_practices_man) only before any simulation depends on it: the database
    records which folder a simulation used, not the contents that folder had at the time.

```julia
icCellsPath(<cell_type>, <patch_type>, <patch_id>, <tag>)
icCellsPath(<cell_type>, <patch_type>, <patch_id>, <carveout_type>, <carveout_id>, <tag>)
```

## Varying initial ECM parameters

!!! tiergloss
    PhysiCellModelManager.jl initializes ECMs from XML via
    [PhysiCellECMCreator.jl](https://github.com/drbergman-lab/PhysiCellECMCreator.jl) (see its docs
    for the file format). [`PhysiCellModelManager.createICECMXMLTemplate`](@ref) creates a template
    and registers it in the database, on the same terms as the IC cells template above, and
    [`icECMPath`](@ref) reaches its parameters.

!!! tierwhy
    The patch type `"ellipse_with_shell"` carries two (or three) subpatches, so its paths take one
    extra token: `<subpatch>` is `"interior"`, `"shell"`, or `"exterior"`.

```julia
icECMPath(<layer_id>, <patch_type>, <patch_id>, <tag>)
icECMPath(<layer_id>, "ellipse_with_shell", <patch_id>, <subpatch>, <tag>)
```
