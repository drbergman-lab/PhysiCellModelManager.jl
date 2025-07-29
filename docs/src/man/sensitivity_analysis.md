# Sensitivity analysis

PhysiCellModelManager.jl supports some sensitivity analysis workflows.
By using PhysiCellModelManager.jl, you will have the opportunity to readily reuse previous simulations to perform and extend sensitivity analyses.

## Supported sensitivity analysis methods
PhysiCellModelManager.jl currently supports three sensitivity analysis methods:
- Morris One-At-A-Time (MOAT)
- Sobol
- Random Balance Design (RBD)

### Morris One-At-A-Time (MOAT)
The Morris One-At-A-Time (MOAT) method gives an intuitive understanding of the sensitivity of a model to its parameters.
What it lacks in theoretical grounding, it makes up for in speed and ease of use.
In short, MOAT will sample parameter space at `n` points.
From each point, it will vary each parameter one at a time and record the change in model output.
Aggregating these changes, MOAT will quantify the sensitivity of the model to each parameter.

`MOAT` uses a Latin Hypercube Sampling (LHS) to sample the parameter space.
By default, it will use the centerpoint of each bin as the point to vary each parameter from.
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

### Sobol
The Sobol method is a more rigorous sensitivity analysis method, relying on the variance of the model output to quantify sensitivity.
It relies on a Sobol sequence, a deterministic sequence of points that are evenly distributed in the unit hypercube.
The important main feature of the Sobol sequence is that it is a _low-discrepancy_ sequence, meaning that it fills the space very evenly.
Thus, using such sequences can give a very good approximation of certain quantities (like integrals) with fewer points than a random sequence would require.
The Sobol sequence is built around powers of 2, and so picking `n=2^k` (as well as ±1) will give the best results.
See [`SobolVariation`](@ref) for more information on how PhysiCellModelManager.jl will use the Sobol sequence to sample the parameter space and how you can control it.

If the extremes of your distributions (where the CDF is 0 or 1) are non-physical, e.g., an unbounded normal distribution, then consider using `n=2^k-1` to pick a subsequence that does not include the extremes.
For example, if you choose `n=7`, then the Sobol sequence will be `[0.5, 0.25, 0.75, 0.125, 0.375, 0.625, 0.875]`.
If you do want to include the extremes, consider using `n=2^k+1`.
For example, if you choose `n=9`, then the Sobol sequence will be `[0, 0.5, 0.25, 0.75, 0.125, 0.375, 0.625, 0.875, 1]`.

You can also choose which method is used to compute the first and total order Sobol indices.
For first order: the choices are `:Sobol1993`, `:Jansen1999`, and `:Saltelli2010`. Default is `:Jansen1999`.
For total order: the choices are `:Homma1996`, `:Jansen1999`, and `:Sobol2007`. Default is `:Jansen1999`.

To use the Sobol method, any of the following signatures can be used:
```julia
Sobolʼ(9)
Sobolʼ(9; skip_start=true) # skip to the odd multiples of 1/32 (smallest one with at least 9)
```

### Random Balance Design (RBD)
The RBD method uses a random design matrix (similar to the Sobol method) and uses a Fourier transform (as in in the FAST method) to compute the sensitivity indices.
It is much cheaper than Sobol, but only gives first order indices.
Choosing `n` design points, RBD will run `n` monads.
It will then rearrange the `n` output values so that each parameter in turn is varied along a sinusoid and computes the Fourier transforms to estimate the first order indices.
By default, it looks up to the 6th harmonic, but you can control this with the `num_harmonics` keyword argument.

By default, PhysiCellModelManager.jl will make use of the Sobol sequence to pick the design points.
It is best to pick `n` such that is differs from a power of 2 by at most 1, e.g. 7, 8, or 9.
In this case, PhysiCellModelManager.jl will actually use a half-period of a sinusoid when converting the design points into CDF space.
Otherwise, PhysiCellModelManager.jl will use random permuations of `n` uniformly spaced points in each parameter dimension and will use a full period of a sinusoid when converting the design points into CDF space.

To use the RBD method, any of the following signatures can be used:
```julia
RBD(9) # will use a Sobol sequence with elements chosen from 0:0.125:1
RBD(32; use_sobol=false) # opt out of using the Sobol sequence
RBD(22) # will use the first 22 elements of the Sobol sequence, including 0
RBD(32; num_harmonics=4) # will look up to the 4th harmonic, instead of the default 6th
```

If you choose `n=2^k - 1` or `n=2^k + 1`, then you will be well-positioned to increment `k` by one and rerun the RBD method to get more accurate results.
The reason: PhysiCellModelManager.jl will start from the start of the Sobol sequence to cover these `n` points, meaning runs will not need to be repeated.
If `n=2^k`, then PhysiCellModelManager.jl will choose the `n` odd multiples of `1/2^(k+1)` from the Sobol sequence, which will not be used if `k` is incremented.

## Setting up a sensitivity analysis

### Simulation inputs
Having chosen a sensitivity analysis method, you must now choose the same set of inputs as required for a sampling. You will need:
- `inputs::InputFolders` containing the `data/inputs/` folder info defining your model
- `n_replicates::Integer` for the number of replicates to run at each parameter vector to get average behavior
- `evs::Vector{<:ElementaryVariation}` to define the parameters to conduct the sensitivity analysis on and their ranges/distributions

Unlike for (most) trials, the `ElementaryVariation`'s you will want here are likely to be [`DistributedVariation`](@ref)'s to allow for a continuum of parameter values to be tested.
PhysiCellModelManager.jl offers [`UniformDistributedVariation`](@ref) and [`NormalDistributedVariation`](@ref) as convenience functions to create these `DistributedVariation`'s.
You can also use any `d::Distribution` to create a `DistributedVariation` directly:
```julia
dv = DistributedVariation(xml_path, d)
```

Currently, PhysiCellModelManager.jl does not support defining relationships between parameters in any context.
`CoVariation`'s are a work-in-progress and will be a sibling of `ElementaryVariation` in the type tree.

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
sensitivity_sampling = run(method, inputs, n_replicates, evs)
```

## Post-processing
The object `sensitivity_sampling` is of type [`PhysiCellModelManager.GSASampling`](@ref), meaning you can use [`PhysiCellModelManager.calculateGSA!`](@ref) to compute sensitivity analyses.
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

Likewise, the `method` will determine how the sensitivity scheme is saved
After running the simulations, PhysiCellModelManager.jl will print a CSV in the `data/outputs/sampling/$(sampling)` folder named based on the `method`.
This can later be used to reload the `GSASampling` and continue doing analysis.
Currently, this requires some ingenuity by the user.
A future version of PhysiCellModelManager.jl could provide convenience functions for simplifying this.
```julia
using CSV, DataFrames
sampling_id = 1 # for example
monad_ids_df = CSV.read("data/outputs/samplings/$(sampling_id)/moat_scheme.csv", DataFrame) # if this was a MOAT scheme
moat_sampling = MOATSampling(Sampling(sampling_id), monad_ids_df, Dict{Function, GlobalSensitivity.MorrisResult}())
```