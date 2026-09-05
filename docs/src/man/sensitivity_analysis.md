# [Sensitivity analysis](@id sensitivity_analysis_man)

PhysiCellModelManager.jl supports sensitivity analysis workflows and can reuse previous simulations to perform and extend them.

## Supported sensitivity analysis methods
Three methods are currently supported:
- Morris One-At-A-Time (MOAT)
- Sobol'
- Random Balance Design (RBD)

### Morris One-At-A-Time (MOAT)
MOAT is fast and easy to use, trading theoretical rigor for an intuitive sensitivity estimate. It samples parameter space at `n` points; from each, it varies one parameter at a time and records the change in output, then aggregates those changes into a sensitivity for each parameter.

`MOAT` samples via Latin Hypercube Sampling (LHS), using each bin's centerpoint as the base point by default.
To pick a random point within the bin, set `add_noise=true`.

`MOAT` furthermore uses an orthogonal LHS, if possible.
If `n=k^d` for some integer `k`, then the LHS will be orthogonal.
Here, `n` is the requested number of base points and `d` is the number of parameters varied.
For example, if `n=16` and `d=4`, then `k=2` and the LHS will be orthogonal.
To force PhysiCellModelManager.jl to NOT use an orthogonal LHS, set `orthogonalize=false`.

To use the MOAT method, any of the following signatures can be used:
```julia
MOAT() # will default to n=15
MOAT(8) # set n=8
MOAT(8; add_noise=true) # use a random point in the bin, not necessarily the center
MOAT(8; orthogonalize=false) # do not use an orthogonal LHS (even if d=3, so k=2 would make an orthogonal LHS)
```

### Sobol'
The Sobol' method is more rigorous, quantifying sensitivity from the variance of the model output. It uses a Sobol' sequence — a deterministic _low-discrepancy_ sequence that fills the unit hypercube very evenly, approximating quantities like integrals with far fewer points than random sampling. The sequence is built around powers of 2, so `n=2^k` (or ±1) gives the best results.
See [`SobolVariation`](@ref) for more information on how PhysiCellModelManager.jl will use the Sobol' sequence to sample the parameter space and how you can control it.

If the extremes of your distributions (where the CDF is 0 or 1) are non-physical, e.g., an unbounded normal distribution, then consider using `n=2^k-1` to pick a subsequence that does not include the extremes.
For example, if you choose `n=7`, then the Sobol' sequence will be `[0.5, 0.25, 0.75, 0.125, 0.375, 0.625, 0.875]`.
If you do want to include the extremes, consider using `n=2^k+1`.
For example, if you choose `n=9`, then the Sobol' sequence will be `[0, 0.5, 0.25, 0.75, 0.125, 0.375, 0.625, 0.875, 1]`.

You can also choose which method is used to compute the first and total order Sobol' indices.
For first order: the choices are `:Sobol1993`, `:Jansen1999`, and `:Saltelli2010`. Default is `:Jansen1999`.
For total order: the choices are `:Homma1996`, `:Jansen1999`, and `:Sobol2007`. Default is `:Jansen1999`.

To use the Sobol' method, any of the following signatures can be used:
```julia
Sobolʼ(9)
Sobolʼ(9; skip_start=true) # skip to the odd multiples of 1/32 (smallest one with at least 9)
```

The rasp symbol is used to avoid conflict with the Sobol module.
To type it in VS Code, use `\\rasp` and then press `tab`.
Alternatively, the constructor [`SobolMM`](@ref) is provided as an alias for convenience.

### Random Balance Design (RBD)
RBD uses a random design matrix (like Sobol') and a Fourier transform (as in the FAST method) to compute sensitivity indices. It is much cheaper than Sobol' but gives only first-order indices. For `n` design points it runs `n` monads, then rearranges the outputs so each parameter in turn varies along a sinusoid and estimates first-order indices via Fourier transforms. It looks up to the 6th harmonic by default (set with `num_harmonics`).

By default the Sobol' sequence picks the design points, and `n` **must** then be within 1 of a power
of 2 — 7, 8 or 9, say. This is a requirement, not a preference: a value further away raises an error
at construction rather than falling back. A half-period of a sinusoid is used when converting the
design points into CDF space.

Pass `use_sobol=false` to lift the restriction. `n` is then unconstrained, random permutations of `n`
uniformly spaced points are used in each parameter dimension, and a full period of a sinusoid is used
for the CDF conversion.

To use the RBD method, any of the following signatures can be used:
```julia
RBD(9) # will use a Sobol' sequence with elements chosen from 0:0.125:1
RBD(32; use_sobol=false) # opt out of using the Sobol' sequence
RBD(22; use_sobol=false) # `n` need not sit near a power of 2 once you opt out of Sobol'
RBD(32; num_harmonics=4) # will look up to the 4th harmonic, instead of the default 6th
```

If you choose `n=2^k - 1` or `n=2^k + 1`, then you will be well-positioned to increment `k` by one and rerun the RBD method to get more accurate results.
The reason: PhysiCellModelManager.jl will start from the start of the Sobol' sequence to cover these `n` points, meaning runs will not need to be repeated.
If `n=2^k`, then PhysiCellModelManager.jl will choose the `n` odd multiples of `1/2^(k+1)` from the Sobol' sequence, which will not be used if `k` is incremented.

## Setting up a sensitivity analysis

### Simulation inputs
A sensitivity analysis takes the same inputs as a sampling:
- `inputs::InputFolders` — the `data/inputs/` folders defining your model.
- `evs::Vector{<:ElementaryVariation}` — the parameters to analyze and their ranges/distributions.

Unlike most trials, these are usually [`DistributedVariation`](@ref)s, so a continuum of values can be tested. Use the convenience constructors [`UniformDistributedVariation`](@ref) and [`NormalDistributedVariation`](@ref), or any `d::Distribution` directly:
```julia
dv = DistributedVariation(xml_path, d)
```

[`CoVariation`](@ref)s draw all member parameters from the same CDF value; pass `flip` to negatively correlate some of them. For more complex relationships, use [LatentVariations](@ref latent_variations_man) to transform latent variables into the parameters of interest.

All variation types accept `name=...`, used in the scheme DataFrame/CSV headers. Inspect the effective name with [`variationName`](@ref).

### Sensitivity functions
At the time of starting the sensitivity analysis, you can include any number of sensitivity functions to compute.
They must take a single argument, a `Simulation`; declare it `::Simulation`. A bare function's per-replicate values must average to a `Real`; passed as a [`QoI`](@ref ModelManager.QoI), `reduce` may instead return a `Dict`/`NamedTuple` of `Real`s, which spreads — see below.
For example, `finalPopulationCount` returns a dictionary of the final population counts of each cell type from a `Simulation`.
So, if you want to know the sensitivity of the final population count of cell type "cancer", you could define a function like:
```julia
f(sim::Simulation) = finalPopulationCount(sim)["cancer"]
```

### [One measurement, one analysis per cell type](@id gsa_keyed_qoi)
Naming a cell type up front means one function per cell type. Pass a [`QoI`](@ref ModelManager.QoI)
whose `reduce` returns a `Dict` instead, and each key becomes its own sensitivity analysis labelled
`"<qoi name>.<key>"`. The ready-made builders do this already:

```julia
run(method, inputs, evs; n_replicates=n_replicates, functions=[endpointPopulationCountQoI()])
```

That yields `endpoint_population_count.cancer`, `endpoint_population_count.immune`, and one more for
every other cell type — without naming any of them in advance, since they are read from the
simulation's own output.
[`endpointPopulationFractionQoI`](@ref) works the same way.

!!! note "Two shapes that are not spread"
    Two separate rules. A bare `Vector` return is **not** spread by index: only its length can be
    checked across the design, and equal length is not equal meaning. Separately, every spread
    component must itself be a `Real`. It is the second that rules out
    [`meanPopulationTimeSeriesQoI`](@ref): its `Dict` *is* spread, and each value is then rejected
    for being a time series rather than a number. Reduce a series to a scalar to ask a sensitivity
    question about it.
    [`populationCountQoI`](@ref) is also out, for a different reason: it defines no `reduce`, so it
    is for the [post-processing sink](@ref post_processing_man) only.

Every parameter set in the design must reduce to the *same* keys; a mismatch is refused rather than
filled in, because a sensitivity index computed over a missing value is wrong rather than
approximate. PCMM's builders satisfy this by construction: the key set is the model's own cell-type
roster, taken from the snapshot's metadata rather than from which types happen to have living cells,
so a type driven extinct by some parameter set still reports a count of zero instead of dropping its
key.

## Running the analysis
Putting it all together, you can run this analysis:
```julia
config_folder = "default"
custom_codes = "default"
inputs = InputFolders(config_folder, custom_codes)
n_replicates = 3
evs = [NormalDistributedVariation(configPath("cancer", "apoptosis", "rate"), 1e-3, 1e-4; lb=0),
       UniformDistributedVariation(configPath("cancer", "cycle", "duration", 0), 720, 2880)]
method = MOAT(15)
f(sim::Simulation) = finalPopulationCount(sim)["cancer"]
sensitivity_sampling = run(method, inputs, evs; n_replicates=n_replicates, functions=[f])
```

Named example:
```julia
evs = [NormalDistributedVariation(configPath("cancer", "apoptosis", "rate"), 1e-3, 1e-4; lb=0, name="Apoptosis rate"),
       UniformDistributedVariation(configPath("cancer", "cycle", "duration", 0), 720, 2880; name="Cycle duration")]
```

## Post-processing
The object `sensitivity_sampling` is of type [`GSASampling`](@ref PhysiCellModelManager.ModelManager.GSASampling), meaning you can use [`PhysiCellModelManager.calculateGSA!`](@ref) to compute sensitivity analyses.
```julia
g(sim::Simulation) = finalPopulationCount(sim)["default"] # a *new* measurement, under a new name
calculateGSA!(sensitivity_sampling, g)
```

Results accumulate, and a measurement whose name is already present is **skipped** — so reusing the
name `f` from the run above would do nothing at all, silently. Pass `recompute=true` to force
re-evaluation; it has to be explicit, because redefining a function's body leaves it
indistinguishable from the one already evaluated.
These results are stored in a `Dict` in the `sensitivity_sampling` object, keyed by the label of the
measurement that produced them — a measurement's own name, or `"<name>.<key>"` for each key of a
`Dict`-valued one. [`gsaLabels`](@ref ModelManager.gsaLabels) lists what is there — it is public in
ModelManager but not exported, so it needs the prefix:
```julia
ModelManager.gsaLabels(sensitivity_sampling)   # e.g. ["endpoint_population_count.cancer", "f"]
println(sensitivity_sampling.results["f"])
```

The exact concrete type of `sensitivity_sampling` will depend on the `method` used.
This, in turn, is used by `calculateGSA!` to determine how to compute the sensitivity indices.

Likewise, the `method` will determine how the sensitivity scheme is saved.
After running the simulations, PhysiCellModelManager.jl will print a CSV in the `data/outputs/samplings/$(sampling.id)` folder, named after the `method` — `moat_scheme.csv`, `sobol_scheme.csv`, or `rbd_scheme.csv`.
Parameter columns in this CSV use the latent parameter names for the sampling design, which include user-specified variation names when provided.
This can later be used to reload the `GSASampling` and continue doing analysis.
The simplest way to do that in a new Julia session is to re-run the code that generated the `GSASampling` object.
So long as the `use_previous` keyword argument is set to `true`, the previous results will be reused.