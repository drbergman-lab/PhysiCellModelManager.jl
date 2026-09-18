# [Varying parameters](@id varying_parameters_man)
PhysiCellModelManager.jl stores all varied inputs in XML files and uses a standard representation for the paths to their parameters.

## XML paths

!!! tiergloss
    An XML path is a vector of strings, one per tag. Two suffixed forms pick one of several
    identically tagged children: `"<tag>:<attribute>:<value>"` selects by attribute, and
    `"<tag>::<child_tag>:<value>"` selects by the content of a child element.
    [XML path helpers](@ref xml_path_helpers_man) builds these paths for you for every varied input
    type, so you rarely write one out by hand.

!!! tierwhy
    The `::` form exists because some PhysiCell elements are told apart not by an attribute but by
    the text of a child. `initial_parameter_distributions` is the case that forces it: every
    `<distribution>` sibling looks alike until you read its `<behavior>` child, so the last line
    below asks for the distribution whose `behavior` is `cycle entry`.

```julia
"<tag>:<attribute>:<value>"       #! select among identically tagged children by attribute
"<tag>::<child_tag>:<value>"      #! select by the content of a child element

["cell_definitions", "cell_definition:name:T_cell", "initial_parameter_distributions",
 "distribution::behavior:cycle entry"]
```

## Discrete variations

!!! tiergloss
    [`DiscreteVariation`](@ref) pairs an XML path with a finite set of values. The optional `name`
    keyword sets the string the variation reports under; [`variationName`](@ref) reads it back.

!!! tierwhy
    Without a `name`, a variation reports under a default built from its target,
    `shortVariationName(location, columnName(target))`.
    [`shortVariationName`](@ref PhysiCellModelManager.shortVariationName) returns the display name
    for one variation column at one location — for PhysiCellModelManager.jl, the readable
    `"default: apoptosis death rate"` rather than the raw slash-separated path. Naming is worth the
    keystrokes as soon as the variation reaches a report: sensitivity scheme headers and summary
    tables use whatever [`variationName`](@ref) returns.

```julia
xml_path = configPath("max_time")
dv = DiscreteVariation(xml_path, [1440.0, 2880.0])
```

```jldoctest
using PhysiCellModelManager
xml_path = configPath("max_time")
dv = DiscreteVariation(xml_path, [1440.0, 2880.0]; name="max time")
variationName(dv)
# output
"max time"
```

!!! tierdev
    **Types underneath.** `DiscreteVariation` and `DistributedVariation` are the two subtypes of
    [`ElementaryVariation`](@ref), the base type for varying a single parameter. Each stores its
    target as an [`XMLPath`](@ref) — a vector of tag strings carrying the same `:` attribute and
    `::` child-content filters described above — so the plain `Vector{String}` that
    [`configPath`](@ref) returns is wrapped by the constructor.

!!! tierjournal "2026-03-31 — Variation names are optional metadata"
    **Decided:** `name` is a keyword on [`DiscreteVariation`](@ref), [`DistributedVariation`](@ref),
    [`CoVariation`](@ref) and [`LatentVariation`](@ref), so the positional constructors are
    unchanged, and [`variationName`](@ref) is the single accessor. The default follows
    `shortVariationName(location, columnName(target))` so that labels agree with summary-table
    naming.

    **Rejected:** letting a name change how a variation is stored. The keys in the variations
    database stay XML-path-based; a name is metadata that reaches reports and nothing else.

!!! tiergloss
    Pass variations to [`createTrial`](@ref) or [`run`](@ref) to create (or run) simulations with
    those parameters, recorded in the database. Several variations are combined on a grid by
    default: every combination of their values.

```julia
xml_path = configPath("cd8", "cycle", "rate", 0)
dv_g1 = DiscreteVariation(xml_path, [0.001, 0.002]) #! vary g1 duration

xml_path2 = configPath("cd8", "cycle", "rate", 1)
dv_s = DiscreteVariation(xml_path2, [0.001, 0.002, 0.003]) #! vary s duration

sampling = createTrial(inputs, dv_g1, dv_s; n_replicates=4) #! 2x3=6 monads, 4 replicates each: 24 simulations
```

## Distributed variations

!!! tiergloss
    [`DistributedVariation`](@ref) varies a parameter over a continuous range given by a
    `Distributions.jl` distribution. [`UniformDistributedVariation`](@ref) and
    [`NormalDistributedVariation`](@ref) are shorthands for the two common cases, and take the same
    optional `name` keyword as [`DiscreteVariation`](@ref).

!!! tierwhy
    A distributed variation names a range, not a list of points; which points get run is decided
    later by the design method, below. That is what makes it the input
    [Sensitivity analysis](@ref sensitivity_analysis_man) expects — a Sobol' or RBD scheme needs a
    distribution to invert, not an enumeration.

```julia
using Distributions
xml_path = configPath("cd8", "apoptosis", "rate")
d = Uniform(0, 0.001)
dv = DistributedVariation(xml_path, d)
dv = DistributedVariation(xml_path, d; name="apoptosis rate") #! optional name, as for DiscreteVariation

dv_u = UniformDistributedVariation(configPath("cd8", "apoptosis", "death_rate"), 0.0, 1e-3)
dv_n = NormalDistributedVariation(configPath("cd8", "necrosis", "death_rate"), 1e-4, 1e-5; lb=0.0, ub=1.0) #! truncated Normal(mu, sigma)
```

## Sampling the variation space

!!! tiergloss
    A *design method* decides which points of the space the variations define actually get run. Pass
    one as the first argument to [`createTrial`](@ref) or [`run`](@ref); omit it for the full
    factorial grid. [`GridVariation`](@ref) runs every combination of the discrete values. The other
    three take a sample count `n` and place that many points in the space:
    [`LHSVariation`](@ref) by Latin hypercube, [`SobolVariation`](@ref) along a Sobol' quasi-random
    sequence, [`RBDVariation`](@ref) in the layout a random balance design needs.

!!! tierwhy
    **[`GridVariation`](@ref)`()`** enumerates all combinations of the discrete values, so its cost
    multiplies with each variation added; it takes no arguments.

    **[`LHSVariation`](@ref)`(n; add_noise=false, rng=Random.GLOBAL_RNG, orthogonalize=true)`**
    spreads `n` points so that each parameter's range is covered once — the usual choice for broad
    coverage of a continuous space on a fixed budget. `add_noise=true` picks a random point within
    each bin rather than its center.

    **[`SobolVariation`](@ref)`(n; n_matrices=1, randomization=NoRand(), skip_start=missing,
    include_one=missing)`** draws `n` points of a Sobol' quasi-random sequence, optionally as
    several design matrices at once.

    **[`RBDVariation`](@ref)`(n; rng=Random.GLOBAL_RNG, use_sobol=true, pow2_diff=missing,
    num_cycles=missing)`** lays `n` points out for a random balance design.

    The last two exist mainly to feed [Sensitivity analysis](@ref sensitivity_analysis_man), which
    picks one for you, but nothing stops you running either as an ordinary sweep. Each name above
    links to its reference entry, which lists every field.

```julia
createTrial(inputs, dv_g1, dv_s; n_replicates=4)                  #! full factorial grid (the default)
createTrial(GridVariation(), inputs, [dv_g1, dv_s])               #! the same thing, spelled out
createTrial(LHSVariation(20), inputs, [dv_apop, dv_cycle])        #! 20 Latin hypercube samples
createTrial(SobolVariation(64), inputs, [dv_apop, dv_cycle])      #! 64 points of a Sobol' sequence
createTrial(RBDVariation(64), inputs, [dv_apop, dv_cycle])        #! 64 points of a random balance design
```

!!! tierdev
    **The function underneath.** All four are subtypes of `AddVariationMethod`, and a new sampling
    scheme is a new subtype plus an `addVariations` method. `createTrial` and `run` call
    [`addVariations`](@ref ModelManager.addVariations)`(method, inputs, avs, reference_variation_id)`,
    which writes the sampled parameter sets into the variations database and returns an
    [`AddVariationsResult`](@ref ModelManager.AddVariationsResult) — one subtype per method, carrying
    what that method's consumer needs. [`AddGridVariationsResult`](@ref) holds `variation_ids` shaped
    like the grid axes; [`AddLHSVariationsResult`](@ref) adds the `cdfs` matrix (one row per latent
    dimension, one column per point); [`AddSobolVariationsResult`](@ref) carries a three-dimensional
    `cdfs` indexed by dimension, sample, and design matrix; and [`AddRBDVariationsResult`](@ref) adds
    `variation_matrix`, the IDs re-sorted into the layout RBD-FAST spectral analysis consumes. Call
    `addVariations` directly only when you want the IDs without building a trial around them.

## Domain bounds in bulk

```julia
domainVariations((x_min=-78, xmax=78, min_y=-30, maxy=[30, 60], z_max=10))
domainVariations(x_min=-78, xmax=78, min_y=-30, maxy=[30, 60], z_max=10)         #! keywords work too

domainVariations((x_min=[-78, -70], xmax=[78, 70], min_y=-30); covary=true)      #! 2 domain sizes, not 4
```

!!! tierdev
    [`domainVariations`](@ref) turns a named tuple of domain boundaries into the corresponding
    `DiscreteVariation`s, so a domain-size sweep needs no hand-written [`configPath`](@ref) calls.
    Keys are matched loosely — each must contain `min` or `max` and one of `x`, `y`, `z` (other than
    the `x` in `max`) — so `x_min`, `xmax`, and `min_y` all work, and you need not give all three
    dimensions. Values may be scalars or vectors; with `covary=true` it returns a single
    [`CoVariation`](@ref) stepping the boundaries together, in which case every multi-valued boundary
    must have the same number of values.
