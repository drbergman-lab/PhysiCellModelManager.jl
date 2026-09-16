# [Varying parameters](@id varying_parameters_man)
PhysiCellModelManager.jl stores all varied inputs in XML files and uses a standard representation for the paths to their parameters.

## XML paths
An XML path is a vector of strings, one per tag. To select among identically tagged children by attribute, format the string as
```julia
"<tag>:<attribute>:<value>"
```

To select by the content of a child element, use `::` to separate the tag from the child tag:
```julia
"<tag>::<child_tag>:<value>"
```
This is needed, e.g., for `initial_parameter_distributions`, where `behavior` is a child of the `distribution` element:
```julia
["cell_definitions", "cell_definition:name:T_cell", "initial_parameter_distributions", "distribution::behavior:cycle entry"]
```

See [XML path helpers](@ref xml_path_helpers_man) for helper functions that build these paths easily for all varied input types.

## Discrete variations
With an XML path defined, create a discrete variation (a finite set of values) with [`DiscreteVariation`](@ref):

```julia
xml_path = configPath("max_time")
dv = DiscreteVariation(xml_path, [1440.0, 2880.0])
```

Optionally set a user-facing `name`, used in reporting outputs (e.g. sensitivity scheme headers):

```jldoctest
using PhysiCellModelManager
xml_path = configPath("max_time")
dv = DiscreteVariation(xml_path, [1440.0, 2880.0]; name="max time")
variationName(dv)
# output
"max time"
```

!!! tierdev
    **Reading a name back.** [`variationName`](@ref) returns the string a variation reports under.
    If `name` was omitted at construction, that string is the convention-based default
    `shortVariationName(location, columnName(target))`.
    [`shortVariationName`](@ref PhysiCellModelManager.shortVariationName) dispatches on the
    simulator — ModelManager's fallback returns the column name unchanged, and
    PhysiCellModelManager.jl extends it to produce the readable `"default: apoptosis death rate"`
    form. Extend it for a new simulator rather than renaming columns.

    **Types underneath.** `DiscreteVariation` and `DistributedVariation` are the two subtypes of
    [`ElementaryVariation`](@ref), the base type for varying a single parameter. Each stores its
    target as an [`XMLPath`](@ref) — a vector of tag strings carrying the same `:` attribute and
    `::` child-content filters described above — so the plain `Vector{String}` that
    [`configPath`](@ref) returns is wrapped by the constructor.

Pass variations to [`createTrial`](@ref) or [`run`](@ref) to create (or run) simulations with those parameters, automatically recording them in the database. Multiple variations are combined on a grid by default (all combinations).

```julia
xml_path = configPath("cd8", "cycle", "rate", 0)
dv_g1 = DiscreteVariation(xml_path, [0.001, 0.002]) #! vary g1 duration

xml_path2 = configPath("cd8", "cycle", "rate", 1)
dv_s = DiscreteVariation(xml_path2, [0.001, 0.002, 0.003]) #! vary s duration

sampling = createTrial(inputs, dv_g1, dv_s; n_replicates=4) #! will run 2x3=6 monads (identical parameters) 4 times each for a total of 24 simulations
```

## Distributed variations
Distributed variations vary a parameter over a continuous range, defined with [`DistributedVariation`](@ref):

```julia
using Distributions
xml_path = configPath("cd8", "apoptosis", "rate")
d = Uniform(0, 0.001)
dv = DistributedVariation(xml_path, d)
```

Two shorthands cover the common distributions, inferring the location from the XML path:

```julia
dv_u = UniformDistributedVariation(configPath("cd8", "apoptosis", "death_rate"), 0.0, 1e-3)
dv_n = NormalDistributedVariation(configPath("cd8", "necrosis", "death_rate"), 1e-4, 1e-5; lb=0.0, ub=1.0) #! truncated Normal(mu, sigma)
```

Like discrete variations, distributed variations also support optional naming:

```julia
dv = DistributedVariation(xml_path, d; name="apoptosis rate")
```

These variations are useful for doing [Sensitivity analysis](@ref sensitivity_analysis_man).

## Sampling the variation space
Several variations define a space of parameter sets; a *design method* decides which points in that
space actually get run. Pass it as the first argument to [`createTrial`](@ref) (or [`run`](@ref)) —
omit it and you get the full factorial grid.

```julia
createTrial(inputs, dv_g1, dv_s; n_replicates=4)                  #! full factorial grid (the default)
createTrial(GridVariation(), inputs, [dv_g1, dv_s])               #! the same thing, spelled out
createTrial(LHSVariation(20), inputs, [dv_apop, dv_cycle])        #! 20 Latin hypercube samples
createTrial(SobolVariation(64), inputs, [dv_apop, dv_cycle])      #! 64 points of a Sobol' sequence
createTrial(RBDVariation(64), inputs, [dv_apop, dv_cycle])        #! 64 points of a random balance design
```

[`GridVariation`](@ref) runs every combination of the discrete values, so its cost multiplies with
each variation added. The other three take a sample count `n` and place that many points in the
space instead. [`LHSVariation`](@ref) spreads them so each parameter's range is covered once — the
usual choice for broad coverage of a continuous space on a fixed budget; `add_noise=true` picks a
random point in each bin rather than its centre. [`SobolVariation`](@ref) uses a low-discrepancy
sequence, best with `n` a power of two or one off it. [`RBDVariation`](@ref) lays points out for a
random balance design. The last two exist mainly to feed
[Sensitivity analysis](@ref sensitivity_analysis_man), which chooses them for you, but nothing stops
you running one as an ordinary sweep.

!!! tierdev
    **Keyword arguments.** `GridVariation()` takes none;
    [`LHSVariation`](@ref)`(n; add_noise=false, rng=Random.GLOBAL_RNG, orthogonalize=true)`,
    [`SobolVariation`](@ref)`(n; n_matrices=1, randomization=NoRand(), skip_start=missing,
    include_one=missing)`, and [`RBDVariation`](@ref)`(n; rng=Random.GLOBAL_RNG, use_sobol=true,
    pow2_diff=missing, num_cycles=missing)`. All four are subtypes of `AddVariationMethod`; a new
    sampling scheme is a new subtype plus an `addVariations` method.

    **The function underneath.** `createTrial` and `run` call
    [`addVariations`](@ref ModelManager.addVariations)`(method, inputs, avs, reference_variation_id)`, which writes the sampled
    parameter sets into the variations database and returns an
    [`AddVariationsResult`](@ref ModelManager.AddVariationsResult) — one subtype per method, carrying what that method's consumer
    needs. [`AddGridVariationsResult`](@ref) holds `variation_ids` shaped like the grid axes;
    [`AddLHSVariationsResult`](@ref) adds the `cdfs` matrix (one row per latent dimension, one column
    per point); [`AddSobolVariationsResult`](@ref) carries a three-dimensional `cdfs` indexed by
    dimension, sample, and design matrix; and [`AddRBDVariationsResult`](@ref) adds
    `variation_matrix`, the IDs re-sorted into the layout RBD-FAST spectral analysis consumes. Call
    `addVariations` directly only when you want the IDs without building a trial around them.

    **Domain bounds in bulk.** [`domainVariations`](@ref) is a PhysiCellModelManager.jl helper that turns a
    named tuple of domain boundaries into the corresponding `DiscreteVariation`s, so a domain-size
    sweep does not need six hand-written `configPath` calls. Keys are matched loosely — each must
    contain `min` or `max` and one of `x`, `y`, `z` — so `x_min`, `xmax`, and `min_y` all work, and
    you need not give all three dimensions. Values may be scalars or vectors; with `covary=true` it
    returns a single `CoVariation` stepping the boundaries together (every multi-valued boundary must
    then have the same number of values) instead of a full factorial over them.