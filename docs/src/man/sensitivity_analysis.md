# Sensitivity analysis

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

By default, PhysiCellModelManager.jl will make use of the Sobol' sequence to pick the design points.
It is best to pick `n` such that is differs from a power of 2 by at most 1, e.g. 7, 8, or 9.
In this case, PhysiCellModelManager.jl will actually use a half-period of a sinusoid when converting the design points into CDF space.
Otherwise, PhysiCellModelManager.jl will use random permuations of `n` uniformly spaced points in each parameter dimension and will use a full period of a sinusoid when converting the design points into CDF space.

To use the RBD method, any of the following signatures can be used:
```julia
RBD(9) # will use a Sobol' sequence with elements chosen from 0:0.125:1
RBD(32; use_sobol=false) # opt out of using the Sobol' sequence
RBD(22) # will use the first 22 elements of the Sobol' sequence, including 0
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

[`CoVariation`](@ref)s draw all member parameters from the same CDF value; pass `flip` to negatively correlate some of them. For more complex relationships, use [`LatentVariations`](@ref) to transform latent variables into the parameters of interest.

All variation types accept `name=...`, used in the scheme DataFrame/CSV headers. Inspect the effective name with [`variationName`](@ref).

### Sensitivity functions
At the time of starting the sensitivity analysis, you can include any number of sensitivity functions to compute.
They must take a single argument, the simulation ID (an `Int64`) and return a `Number` (or any type that `Statistics.mean` will accept a `Vector` of).
For example, `finalPopulationCount` returns a dictionary of the final population counts of each cell type from a simulation ID.
So, if you want to know the sensitivity of the final population count of cell type "cancer", you could define a function like:
```julia
f(sim_id) = finalPopulationCount(sim_id)["cancer"]
```

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
f(sim_id) = finalPopulationCount(sim_id)["cancer"]
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
f = simulation_id -> finalPopulationCount(simulation_id)["default"] # count the final population of cell type "default"
calculateGSA!(sensitivity_sampling, f)
```
These results are stored in a `Dict` in the `sensitivity_sampling` object:
```julia
println(sensitivity_sampling.results[f])
```

The exact concrete type of `sensitivity_sampling` will depend on the `method` used.
This, in turn, is used by `calculateGSA!` to determine how to compute the sensitivity indices.

Likewise, the `method` will determine how the sensitivity scheme is saved.
After running the simulations, PhysiCellModelManager.jl will print a CSV in the `data/outputs/sampling/$(sampling.id)` folder named based on the `method`.
Parameter columns in this CSV use the latent parameter names for the sampling design, which include user-specified variation names when provided.
This can later be used to reload the `GSASampling` and continue doing analysis.
The simplest way to do that in a new Julia session is to re-run the code that generated the `GSASampling` object.
So long as the `use_previous` keyword argument is set to `true`, the previous results will be reused.